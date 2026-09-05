//
//  CorrectionLearningService.swift
//  Fluid
//
//  Correction auto-learning: when the user fixes freshly typed dictation
//  output right after it lands, re-read the edited field via Accessibility,
//  diff it against what was typed, and store the fix as a pending dictionary
//  suggestion (see CorrectionSuggestionStore).
//
//  Privacy: everything stays on this Mac. Only the most recent dictation
//  output is held, in memory, and only the extracted (original -> corrected)
//  pairs are persisted — never the transcript or the field content. All
//  Accessibility reads are gated on the "Learn from my corrections" flag and
//  on the focused app matching the app the text was typed into.
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class CorrectionLearningService {
    static let shared = CorrectionLearningService()

    // MARK: - Tuning

    /// Keyboard quiet time after a qualifying edit before the field is re-read.
    private static let settleQuietInterval: TimeInterval = 3.0
    /// Upper bound on the settle wait so the capture cannot trail far behind the edit.
    private static let settleMaxWait: TimeInterval = 10.0
    /// Poll interval while waiting for typing to settle.
    private static let settlePollInterval: TimeInterval = 0.5

    // MARK: - State (in memory only; never persisted)

    private struct RememberedOutput {
        let text: String
        let targetPID: pid_t?
        let timestamp: Date
    }

    /// Only the most recent externally typed dictation output is held.
    private var lastOutput: RememberedOutput?
    private var lastKeyActivityAt = Date.distantPast
    private var settleTask: Task<Void, Never>?
    private var isWatching = false

    private init() {}

    // MARK: - Wiring

    /// Hooks into PostTranscriptionEditTracker's existing event-tap monitoring
    /// (no second event tap). Safe to call more than once.
    func beginWatching() {
        guard !self.isWatching else { return }
        self.isWatching = true

        Task {
            await PostTranscriptionEditTracker.shared.setKeyActivityObserver { date in
                Task { @MainActor in
                    CorrectionLearningService.shared.lastKeyActivityAt = date
                }
            }
            await PostTranscriptionEditTracker.shared.setOnQualifyingEdit {
                Task { @MainActor in
                    CorrectionLearningService.shared.handleQualifyingEdit()
                }
            }
        }
    }

    /// Remembers the most recent dictation output that was typed into another
    /// app. Held in memory only; replaced by the next dictation.
    func recordDictationOutput(typedText: String, targetPID: pid_t?, timestamp: Date) {
        // A new dictation supersedes any capture still waiting to settle.
        self.settleTask?.cancel()
        self.settleTask = nil

        guard CorrectionSuggestionStore.shared.isEnabled else {
            self.lastOutput = nil
            return
        }
        guard !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.lastOutput = nil
            return
        }

        self.lastOutput = RememberedOutput(text: typedText, targetPID: targetPID, timestamp: timestamp)
    }

    // MARK: - Capture flow

    private func handleQualifyingEdit() {
        guard CorrectionSuggestionStore.shared.isEnabled else { return }
        guard let output = self.lastOutput else { return }

        self.settleTask?.cancel()
        // The edit keystroke itself counts as activity.
        self.lastKeyActivityAt = Date()
        self.settleTask = Task { [weak self] in
            await self?.waitForTypingToSettle()
            guard let self, !Task.isCancelled else { return }
            self.captureCorrection(for: output)
        }
    }

    private func waitForTypingToSettle() async {
        let started = Date()
        while !Task.isCancelled {
            let now = Date()
            if now.timeIntervalSince(self.lastKeyActivityAt) >= Self.settleQuietInterval { return }
            if now.timeIntervalSince(started) >= Self.settleMaxWait { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.settlePollInterval * 1_000_000_000))
        }
    }

    private func captureCorrection(for output: RememberedOutput) {
        // Single-shot: drop the remembered output up front so no dictation
        // content lingers past this capture attempt.
        if self.lastOutput?.timestamp == output.timestamp {
            self.lastOutput = nil
        }

        // The enabled flag gates every Accessibility read; check it before any AX call.
        guard CorrectionSuggestionStore.shared.isEnabled else { return }
        guard let targetPID = output.targetPID else { return }
        // Missing Accessibility permission: silently no-op.
        guard AXIsProcessTrusted() else { return }
        // Only re-read the app the text was typed into; abort silently otherwise.
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontmostPID == targetPID
        else { return }
        guard let fieldText = TextSelectionService.shared.focusedElementText(forPID: targetPID) else { return }

        let pairs = CorrectionDiff.extractCorrectionPairs(typedText: output.text, fieldText: fieldText)
        guard !pairs.isEmpty else { return }

        for pair in pairs {
            CorrectionSuggestionStore.shared.recordPair(original: pair.original, corrected: pair.corrected)
        }

        // Log counts only — never content.
        DebugLogger.shared.debug(
            "Captured \(pairs.count) correction pair(s) from post-dictation edit",
            source: "CorrectionLearningService"
        )
    }
}

// MARK: - Correction Diff

/// Token-level diff between the typed dictation output and the corresponding
/// region of the edited field text. Pure functions; retains no content.
enum CorrectionDiff {
    struct Pair: Equatable {
        let original: String
        let corrected: String
    }

    /// Maximum pairs extracted per dictation.
    static let maxPairs = 3
    /// Both sides of a pair must be 1...maxSpanTokens tokens.
    static let maxSpanTokens = 4
    /// Guardrails on diff size.
    private static let maxTypedTokens = 600
    private static let maxFieldTokens = 10000
    /// Longest token run tried when anchoring the typed output inside the field text.
    private static let maxAnchorTokens = 20

    static func extractCorrectionPairs(typedText: String, fieldText: String) -> [Pair] {
        let trimmedTyped = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTyped.isEmpty else { return [] }
        // Output still present verbatim -> nothing was corrected.
        if fieldText.contains(trimmedTyped) { return [] }

        let typed = tokenize(typedText)
        guard typed.count >= 2, typed.count <= maxTypedTokens else { return [] }
        let field = tokenize(fieldText)
        guard !field.isEmpty, field.count <= maxFieldTokens else { return [] }

        guard let regionRange = alignedRegion(typed: typed, field: field) else { return [] }
        let region = Array(field[regionRange])
        guard !region.isEmpty, region.count <= maxTypedTokens else { return [] }

        // Rewrite gate: require >=50% of the typed tokens unchanged. Measured
        // case- and punctuation-insensitively so case fixes still qualify.
        let normalizedMatched = lcsLength(typed.map(anchorKey), region.map(anchorKey))
        guard normalizedMatched * 2 >= typed.count else { return [] }

        // Replaced spans come from a case-sensitive alignment so case-only
        // fixes surface as pairs.
        let spans = replacedSpans(typed: typed, region: region)

        var pairs: [Pair] = []
        for span in spans {
            guard pairs.count < maxPairs else { break }
            guard (1...maxSpanTokens).contains(span.typed.count),
                  (1...maxSpanTokens).contains(span.region.count)
            else { continue }

            let original = strippedJoined(Array(typed[span.typed]))
            let corrected = strippedJoined(Array(region[span.region]))
            guard !original.isEmpty, !corrected.isEmpty, original != corrected else { continue }

            // Ignore pure whitespace/punctuation-only changes.
            let originalLetters = withoutPunctuation(original)
            let correctedLetters = withoutPunctuation(corrected)
            guard !originalLetters.isEmpty, !correctedLetters.isEmpty else { continue }
            if originalLetters == correctedLetters { continue }

            // Case-only changes count only when the span is not sentence-initial.
            if originalLetters.lowercased() == correctedLetters.lowercased(),
               isSentenceInitial(spanStart: span.typed.lowerBound, typed: typed)
            {
                continue
            }

            pairs.append(Pair(original: original, corrected: corrected))
        }
        return pairs
    }

    // MARK: Tokenization

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Punctuation- and case-insensitive form used for anchoring and the rewrite gate.
    private static func anchorKey(_ token: String) -> String {
        let stripped = withoutPunctuation(token).lowercased()
        return stripped.isEmpty ? token.lowercased() : stripped
    }

    private static func withoutPunctuation(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0) &&
                !CharacterSet.whitespacesAndNewlines.contains($0)
        }))
    }

    private static func strippedJoined(_ tokens: [String]) -> String {
        tokens.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private static func isSentenceInitial(spanStart: Int, typed: [String]) -> Bool {
        guard spanStart > 0 else { return true }
        guard let last = typed[spanStart - 1].last else { return true }
        return ".!?…".contains(last)
    }

    // MARK: Region alignment

    /// Locates the region of the field text that corresponds to the typed
    /// output, anchoring on the longest common prefix/suffix token runs.
    private static func alignedRegion(typed: [String], field: [String]) -> Range<Int>? {
        let n = typed.count
        let normalizedTyped = typed.map(anchorKey)
        let normalizedField = field.map(anchorKey)

        // Prefix anchor: longest leading run of typed tokens found contiguously
        // in the field (last occurrence — dictation lands near the cursor).
        var prefixStart: Int?
        var k = min(n, maxAnchorTokens)
        while k >= 1 {
            if let start = lastMatch(of: Array(normalizedTyped[0..<k]), in: normalizedField) {
                prefixStart = start
                break
            }
            k -= 1
        }

        // Suffix anchor: longest trailing run, at or after the prefix anchor.
        var suffixEnd: Int?
        var s = min(n, maxAnchorTokens)
        while s >= 1 {
            if let start = lastMatch(of: Array(normalizedTyped[(n - s)...]), in: normalizedField, from: prefixStart ?? 0) {
                suffixEnd = start + s
                break
            }
            s -= 1
        }

        let maxRegionLength = n * 2 + 8

        switch (prefixStart, suffixEnd) {
        case let (.some(start), .some(end)) where end > start:
            guard end - start <= maxRegionLength else { return nil }
            return start..<end
        case let (.some(start), _):
            return bestWindow(normalizedTyped: normalizedTyped, normalizedField: normalizedField, prefixStart: start)
        case let (_, .some(end)):
            return bestWindow(normalizedTyped: normalizedTyped, normalizedField: normalizedField, suffixEnd: end)
        default:
            return nil
        }
    }

    /// With only one anchor, the region length is ambiguous: try lengths near
    /// the typed length and keep the window with the strongest normalized LCS,
    /// tie-broken toward the typed length.
    private static func bestWindow(
        normalizedTyped: [String],
        normalizedField: [String],
        prefixStart: Int? = nil,
        suffixEnd: Int? = nil
    ) -> Range<Int>? {
        let n = normalizedTyped.count
        var best: (range: Range<Int>, matched: Int, lengthDelta: Int)?

        for length in max(1, n - 2)...(n + maxSpanTokens) {
            let range: Range<Int>
            if let start = prefixStart {
                guard start + length <= normalizedField.count else { break }
                range = start..<(start + length)
            } else if let end = suffixEnd {
                guard end - length >= 0 else { break }
                range = (end - length)..<end
            } else {
                return nil
            }

            let matched = lcsLength(normalizedTyped, Array(normalizedField[range]))
            let delta = abs(length - n)
            if let current = best {
                if matched > current.matched || (matched == current.matched && delta < current.lengthDelta) {
                    best = (range, matched, delta)
                }
            } else {
                best = (range, matched, delta)
            }
        }
        return best?.range
    }

    /// Index of the last contiguous occurrence of `pattern` in `tokens`, at or
    /// after `startIndex`.
    private static func lastMatch(of pattern: [String], in tokens: [String], from startIndex: Int = 0) -> Int? {
        guard !pattern.isEmpty, tokens.count >= pattern.count else { return nil }
        var found: Int?
        var index = max(0, startIndex)
        let limit = tokens.count - pattern.count
        while index <= limit {
            var matches = true
            for offset in 0..<pattern.count where tokens[index + offset] != pattern[offset] {
                matches = false
                break
            }
            if matches { found = index }
            index += 1
        }
        return found
    }

    // MARK: LCS

    private static func lcsTable(_ left: [String], _ right: [String]) -> [[Int]] {
        let n = left.count
        let m = right.count
        // dp[i][j] = LCS length of left[i...] and right[j...]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if left[i] == right[j] {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        return dp
    }

    private static func lcsLength(_ left: [String], _ right: [String]) -> Int {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return lcsTable(left, right)[0][0]
    }

    /// Walks the case-sensitive LCS alignment and returns the contiguous
    /// replaced spans: gaps where both sides have unmatched tokens.
    private static func replacedSpans(typed: [String], region: [String]) -> [(typed: Range<Int>, region: Range<Int>)] {
        let n = typed.count
        let m = region.count
        guard n > 0, m > 0 else { return [] }
        let dp = lcsTable(typed, region)

        var spans: [(typed: Range<Int>, region: Range<Int>)] = []
        var i = 0
        var j = 0
        var typedGapStart = 0
        var regionGapStart = 0
        var inGap = false

        while i < n, j < m {
            if typed[i] == region[j] {
                if inGap {
                    spans.append((typedGapStart..<i, regionGapStart..<j))
                    inGap = false
                }
                i += 1
                j += 1
            } else {
                if !inGap {
                    typedGapStart = i
                    regionGapStart = j
                    inGap = true
                }
                if dp[i + 1][j] >= dp[i][j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
        }

        if i < n || j < m {
            if !inGap {
                typedGapStart = i
                regionGapStart = j
            }
            spans.append((typedGapStart..<n, regionGapStart..<m))
        } else if inGap {
            spans.append((typedGapStart..<i, regionGapStart..<j))
        }

        return spans
    }
}

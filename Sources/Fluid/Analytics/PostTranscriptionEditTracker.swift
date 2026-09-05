import AppKit
import Foundation

/// Tracks whether the user immediately edits freshly-typed dictation output (Backspace / Cmd+A).
/// Privacy: stores only low-cardinality metadata; never stores transcript content.
actor PostTranscriptionEditTracker {
    static let shared = PostTranscriptionEditTracker()

    private init() {}

    // MARK: - State

    private struct ActiveWindow {
        let completedAt: Date
        let wordsBucket: String
        let xSeconds: Int
        let aiUsed: Bool
        let aiModel: String?
        let aiProvider: String?
        let mode: String
        let outputMethod: String
    }

    private var active: ActiveWindow?

    // MARK: - Correction learning observers

    /// Called on every observed keyDown (timestamp only; no key content). Lets
    /// CorrectionLearningService detect when post-dictation typing has settled
    /// without installing a second event tap.
    private var keyActivityObserver: (@Sendable (Date) -> Void)?

    /// Called once per transcription window when a qualifying immediate edit is
    /// detected (Backspace or Cmd+A within the window; carries no content).
    private var onQualifyingEdit: (@Sendable () -> Void)?

    func setKeyActivityObserver(_ observer: (@Sendable (Date) -> Void)?) {
        self.keyActivityObserver = observer
    }

    func setOnQualifyingEdit(_ handler: (@Sendable () -> Void)?) {
        self.onQualifyingEdit = handler
    }

    // MARK: - Public API

    func markTranscriptionCompleted(
        mode: String,
        outputMethod: String,
        wordsBucket: String,
        aiUsed: Bool,
        aiModel: String?,
        aiProvider: String?
    ) {
        let x = Self.xSeconds(forWordsBucket: wordsBucket)
        guard x > 0 else {
            self.active = nil
            return
        }

        self.active = ActiveWindow(
            completedAt: Date(),
            wordsBucket: wordsBucket,
            xSeconds: x,
            aiUsed: aiUsed,
            aiModel: aiUsed ? aiModel : nil,
            aiProvider: aiUsed ? aiProvider : nil,
            mode: mode,
            outputMethod: outputMethod
        )
    }

    func handleKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) async {
        self.keyActivityObserver?(Date())

        guard let active else { return }

        let elapsed = Date().timeIntervalSince(active.completedAt)
        if elapsed < 0 || elapsed > Double(active.xSeconds) {
            self.active = nil
            return
        }

        let action: String?
        if keyCode == 51 { // Backspace (delete)
            action = "backspace"
        } else if keyCode == 0, modifiers.contains(.command) { // Cmd + A
            action = "cmd_a"
        } else {
            action = nil
        }

        guard action != nil else { return }

        // Notify correction learning (no content leaves this call).
        self.onQualifyingEdit?()

        // Single-fire per transcription window.
        self.active = nil
    }

    // MARK: - Word bucketing

    /// Low-cardinality word-count bucketing used to size the edit window.
    nonisolated static func wordCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    nonisolated static func bucketWords(_ count: Int) -> String {
        switch count {
        case ...0: return "0"
        case 1...5: return "1-5"
        case 6...20: return "6-20"
        case 21...50: return "21-50"
        case 51...100: return "51-100"
        case 101...300: return "101-300"
        default: return "301+"
        }
    }

    // MARK: - Window mapping

    private static func xSeconds(forWordsBucket bucket: String) -> Int {
        switch bucket {
        case "0": return 0
        case "1-5": return 2
        case "6-20": return 3
        case "21-50": return 5
        case "51-100": return 8
        case "101-300": return 12
        case "301+": return 15
        default: return 5
        }
    }
}

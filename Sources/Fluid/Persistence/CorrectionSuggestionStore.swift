//
//  CorrectionSuggestionStore.swift
//  Fluid
//
//  Persistence for correction auto-learning: when the user fixes freshly typed
//  dictation output, the extracted (original -> corrected) pair is stored as a
//  pending dictionary suggestion the user can accept or dismiss.
//  Privacy: stores only the extracted pairs — never the transcript or the
//  content of the field that was edited.
//

import Combine
import Foundation

// MARK: - Correction Suggestion Model

struct CorrectionSuggestion: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case pending
        case dismissed
    }

    let id: UUID
    var original: String
    var corrected: String
    var occurrenceCount: Int
    let firstSeen: Date
    var lastSeen: Date
    var status: Status

    init(
        id: UUID = UUID(),
        original: String,
        corrected: String,
        occurrenceCount: Int = 1,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        status: Status = .pending
    ) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.occurrenceCount = occurrenceCount
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.status = status
    }
}

// MARK: - Correction Suggestion Store

@MainActor
final class CorrectionSuggestionStore: ObservableObject {
    static let shared = CorrectionSuggestionStore()

    /// Occurrence count at which a previously dismissed pair is re-suggested (once).
    static let dismissedRependThreshold = 3
    /// Cap on stored suggestions; oldest dismissed entries are dropped first.
    static let maxStoredSuggestions = 200

    private static let enabledDefaultsKey = "CorrectionLearningEnabled"

    private let appSupportFolder = "FluidVoice"
    private let suggestionsFileName = "correction_suggestions.json"
    private let fileManager = FileManager.default

    @Published private(set) var suggestions: [CorrectionSuggestion] = []

    private init() {
        self.loadSuggestions()
    }

    // MARK: - Enabled flag

    /// Whether correction auto-learning is on. Default true. Gates every capture
    /// and every Accessibility read performed by CorrectionLearningService.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey)
        }
    }

    // MARK: - Public Methods

    var pendingSuggestions: [CorrectionSuggestion] {
        self.suggestions.filter { $0.status == .pending }
    }

    /// Records a captured correction pair. The same (original, corrected) pair
    /// merges into the existing suggestion (occurrence count + last seen). A
    /// dismissed pair stays dismissed unless it reaches the re-pend threshold,
    /// at which point it is re-suggested once.
    func recordPair(original: String, corrected: String) {
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !corrected.isEmpty, original != corrected else { return }

        if let index = self.suggestions.firstIndex(where: { $0.original == original && $0.corrected == corrected }) {
            self.suggestions[index].occurrenceCount += 1
            self.suggestions[index].lastSeen = Date()
            if self.suggestions[index].status == .dismissed,
               self.suggestions[index].occurrenceCount == Self.dismissedRependThreshold
            {
                self.suggestions[index].status = .pending
            }
        } else {
            self.suggestions.insert(CorrectionSuggestion(original: original, corrected: corrected), at: 0)
        }

        self.enforceStorageCap()
        self.saveSuggestions()
    }

    func dismiss(id: UUID) {
        guard let index = self.suggestions.firstIndex(where: { $0.id == id }) else { return }
        self.suggestions[index].status = .dismissed
        self.saveSuggestions()
    }

    /// Removes a suggestion outright (used after accepting it into the dictionary).
    func removeSuggestion(id: UUID) {
        self.suggestions.removeAll { $0.id == id }
        self.saveSuggestions()
    }

    // MARK: - Storage cap

    private func enforceStorageCap() {
        while self.suggestions.count > Self.maxStoredSuggestions {
            let dismissedIndices = self.suggestions.indices.filter { self.suggestions[$0].status == .dismissed }
            if let oldestDismissed = dismissedIndices.min(by: { self.suggestions[$0].lastSeen < self.suggestions[$1].lastSeen }) {
                self.suggestions.remove(at: oldestDismissed)
            } else if let oldest = self.suggestions.indices.min(by: { self.suggestions[$0].lastSeen < self.suggestions[$1].lastSeen }) {
                self.suggestions.remove(at: oldest)
            } else {
                break
            }
        }
    }

    // MARK: - Persistence

    private func suggestionsFileURL(createDirectoryIfNeeded: Bool = false) -> URL? {
        guard let base = self.fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent(self.appSupportFolder, isDirectory: true)
        if createDirectoryIfNeeded {
            try? self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(self.suggestionsFileName, isDirectory: false)
    }

    private func loadSuggestions() {
        guard let url = self.suggestionsFileURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CorrectionSuggestion].self, from: data)
        else {
            self.suggestions = []
            return
        }
        self.suggestions = decoded
    }

    private func saveSuggestions() {
        if let url = self.suggestionsFileURL(createDirectoryIfNeeded: true),
           let encoded = try? JSONEncoder().encode(self.suggestions)
        {
            try? encoded.write(to: url, options: .atomic)
        }

        DebugLogger.shared.debug("Saved \(self.suggestions.count) correction suggestions", source: "CorrectionSuggestionStore")
    }
}

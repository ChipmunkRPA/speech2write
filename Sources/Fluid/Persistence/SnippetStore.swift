//
//  SnippetStore.swift
//  Fluid
//
//  Persistence for voice-triggered snippets: say a trigger phrase while
//  dictating and it expands into a pre-written text block.
//

import Combine
import Foundation

// MARK: - Snippet Model

struct Snippet: Codable, Identifiable, Equatable {
    static let maxExpansionLength = 4000

    let id: UUID
    var trigger: String
    var expansion: String
    var isEnabled: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        trigger: String,
        expansion: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expansion = String(expansion.prefix(Snippet.maxExpansionLength))
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// Preview text for list display (expansion flattened to one line, first 80 chars)
    var previewText: String {
        let flattened = self.expansion
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if flattened.count > 80 {
            return String(flattened.prefix(77)) + "..."
        }
        return flattened
    }
}

// MARK: - Snippet Store

@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    private let appSupportFolder = "FluidVoice"
    private let snippetsFileName = "snippets.json"
    private let fileManager = FileManager.default

    @Published private(set) var snippets: [Snippet] = []

    private init() {
        self.loadSnippets()
    }

    // MARK: - Public Methods

    func addSnippet(_ snippet: Snippet) {
        self.snippets.insert(snippet, at: 0)
        self.saveSnippets()
    }

    func updateSnippet(_ snippet: Snippet) {
        guard let index = self.snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        self.snippets[index] = snippet
        self.saveSnippets()
    }

    func setEnabled(_ isEnabled: Bool, id: UUID) {
        guard let index = self.snippets.firstIndex(where: { $0.id == id }) else { return }
        self.snippets[index].isEnabled = isEnabled
        self.saveSnippets()
    }

    func deleteSnippet(id: UUID) {
        self.snippets.removeAll { $0.id == id }
        self.saveSnippets()
    }

    // MARK: - Persistence

    private func snippetsFileURL(createDirectoryIfNeeded: Bool = false) -> URL? {
        guard let base = self.fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent(self.appSupportFolder, isDirectory: true)
        if createDirectoryIfNeeded {
            try? self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(self.snippetsFileName, isDirectory: false)
    }

    private func loadSnippets() {
        guard let url = self.snippetsFileURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else {
            self.snippets = []
            return
        }
        self.snippets = decoded
    }

    private func saveSnippets() {
        if let url = self.snippetsFileURL(createDirectoryIfNeeded: true),
           let encoded = try? JSONEncoder().encode(self.snippets)
        {
            try? encoded.write(to: url, options: .atomic)
        }
        ASRService.invalidateSnippetCache()

        DebugLogger.shared.debug("Saved \(self.snippets.count) snippets", source: "SnippetStore")
    }
}

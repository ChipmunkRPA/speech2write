//
//  AISettingsView.swift
//  fluid
//
//  Hosts the shared AI-settings enums and layout constants used by the
//  AI settings views and view models.
//  Created: 2025-12-14
//

import SwiftUI

// MARK: - Connection Status Enum

enum AIConnectionStatus {
    case unknown, testing, success, failed
}

enum PromptEditorMode: Identifiable, Equatable {
    case defaultPrompt(mode: SettingsStore.PromptMode)
    case newPrompt(prefillMode: SettingsStore.PromptMode)
    case edit(promptID: String)

    var id: String {
        switch self {
        case let .defaultPrompt(mode): return "default:\(mode.rawValue)"
        case let .newPrompt(prefillMode): return "new:\(prefillMode.rawValue)"
        case let .edit(promptID): return "edit:\(promptID)"
        }
    }

    var isDefault: Bool {
        if case .defaultPrompt = self { return true }
        return false
    }

    var editingPromptID: String? {
        if case let .edit(promptID) = self { return promptID }
        return nil
    }

    var isNewPrompt: Bool {
        if case .newPrompt = self { return true }
        return false
    }

    var mode: SettingsStore.PromptMode? {
        switch self {
        case let .defaultPrompt(mode): return mode
        case let .newPrompt(prefillMode): return prefillMode
        case .edit: return nil
        }
    }
}

enum ModelSortOption: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case accuracy = "Accuracy"
    case speed = "Speed"

    var id: String { self.rawValue }
}

enum SpeechProviderFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case nvidia = "NVIDIA"
    case apple = "Apple"
    case cohere = "Cohere"
    case openai = "OpenAI"

    var id: String { self.rawValue }
}

enum AISettingsLayout {
    static let labelWidth: CGFloat = 110
    static let pickerWidth: CGFloat = 220
    static let controlHeight: CGFloat = 34
    static let providerRowControlHeight: CGFloat = 34
    static let actionMinWidth: CGFloat = 120
    static let compactActionMinWidth: CGFloat = 96
    static let wideActionMinWidth: CGFloat = 140
    static let primaryActionMinWidth: CGFloat = 150
    static let promptActionMinWidth: CGFloat = 90
    static let promptModeMinHeight: CGFloat = 260
    static let promptModeHintHeight: CGFloat = 18
    static let promptInlinePickerWidth: CGFloat = 145
    static let promptInlineModelWidth: CGFloat = 180
    static let promptScopeLabelWidth: CGFloat = 110
    static let promptEditorLabelColumnWidth: CGFloat = 180
    static let promptEditorControlColumnWidth: CGFloat = 270
    static let rowLeadingIndent: CGFloat = labelWidth + 12
}

import Foundation

/// Shared gating logic for whether dictation AI post-processing is usable/configured.
enum DictationAIPostProcessingGate {
    /// Returns true if dictation AI post-processing should be allowed, given current settings.
    /// - Requires dictation prompt selection to not be `Off`
    /// - Requires the selected provider connection to still be verified
    static func isConfigured() -> Bool {
        self.isConfigured(for: .primary, appBundleID: nil)
    }

    static func isConfigured(for slot: SettingsStore.DictationShortcutSlot, appBundleID: String? = nil) -> Bool {
        let settings = SettingsStore.shared
        let promptSelection = settings.dictationPromptSelection(for: slot)
        guard promptSelection != .off else { return false }
        if let appBundleID,
           settings.promptRoutingScope(for: .dictate) == .selectedAppsOnly,
           !settings.hasAppPromptBinding(for: .dictate, appBundleID: appBundleID)
        {
            return false
        }

        return self.isProviderConfigured()
    }

    /// Returns true if the selected AI provider is currently verified/configured,
    /// regardless of the AI toggle or prompt selection. Used to gate prompt-mode hotkey AI processing.
    /// Apple Intelligence is the only enhancement provider in this build.
    static func isProviderConfigured() -> Bool {
        let settings = SettingsStore.shared
        guard settings.selectedProviderID == "apple-intelligence" else { return false }
        return settings.verifiedProviderFingerprints["apple-intelligence"] == "apple-intelligence"
            && AppleIntelligenceService.isAvailable
    }
}

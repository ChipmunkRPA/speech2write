//
//  ModelRepository.swift
//  Fluid
//
//  Single source of truth for default model lists per provider.
//  All views (AISettings, ContentView, RewriteMode) should use this
//  instead of maintaining their own hardcoded lists.
//

import Foundation

final class ModelRepository {
    static let shared = ModelRepository()

    private init() {}

    /// Speech2Write is local-only: enhancement runs on-device with Apple
    /// Intelligence. Local-server providers (Ollama, LM Studio) and cloud
    /// providers are not selectable, addable, or verifiable. Every provider
    /// enumeration must filter through this allowlist (mirrors
    /// SpeechModel.enabledModels).
    static let allowedProviderIDs: [String] = ["apple-intelligence"]

    /// All built-in provider IDs (not including custom/saved providers)
    static var builtInProviderIDs: [String] {
        allowedProviderIDs
    }

    /// Check if a provider ID is allowed in this local-only build.
    func isAllowedProvider(_ providerID: String) -> Bool {
        Self.builtInProviderIDs.contains(providerID)
    }

    /// Returns the default models for a given provider ID.
    /// This is used when the user has not added any custom models for that provider.
    func defaultModels(for providerID: String) -> [String] {
        switch providerID {
        case "apple-intelligence":
            return ["System Model"]
        default:
            return []
        }
    }

    /// Returns the default base URL for a given provider ID.
    /// Apple Intelligence runs in-process, so no built-in provider has one.
    func defaultBaseURL(for providerID: String) -> String {
        ""
    }

    /// Returns the display name for a provider ID
    func displayName(for providerID: String) -> String {
        switch providerID {
        case "apple-intelligence": return "Apple Intelligence"
        default: return providerID.capitalized
        }
    }

    /// Check if a provider ID is a built-in provider
    func isBuiltIn(_ providerID: String) -> Bool {
        Self.builtInProviderIDs.contains(providerID)
    }

    /// Returns the website URL for setting up the provider software.
    /// Returns nil for providers that don't have a relevant URL (e.g., Apple Intelligence).
    func providerWebsiteURL(for providerID: String) -> (url: String, label: String)? {
        nil
    }

    /// Check if a URL points at this machine: only localhost / loopback hosts
    /// pass, not private-network addresses.
    /// Speech2Write is local-only, so editable base URLs must satisfy this.
    func isLocalhostEndpoint(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host else { return false }
        let hostLower = host.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if hostLower == "localhost" || hostLower == "::1" { return true }
        return hostLower == "127.0.0.1" || hostLower.hasPrefix("127.")
    }

    /// Returns the list of built-in providers for UI pickers
    /// - Parameter includeAppleIntelligence: Whether to include Apple Intelligence
    /// - Parameter appleIntelligenceAvailable: Whether Apple Intelligence is available on this device
    /// - Parameter appleIntelligenceDisabledReason: Optional reason if disabled (e.g., "No tools")
    func builtInProvidersList(
        includeAppleIntelligence: Bool = true,
        appleIntelligenceAvailable: Bool = false,
        appleIntelligenceDisabledReason: String? = nil
    ) -> [(id: String, name: String)] {
        var list: [(id: String, name: String)] = []

        if includeAppleIntelligence {
            if appleIntelligenceAvailable {
                list.append(("apple-intelligence", "Apple Intelligence"))
            } else if let reason = appleIntelligenceDisabledReason {
                list.append(("apple-intelligence-disabled", "Apple Intelligence (\(reason))"))
            } else {
                list.append(("apple-intelligence-disabled", "Apple Intelligence (Unavailable)"))
            }
        }

        return list
    }

    /// Converts a provider ID to a storage key for UserDefaults
    /// Built-in providers use their ID directly; custom providers get "custom:" prefix
    func providerKey(for providerID: String) -> String {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return providerID }

        // Built-in providers use their ID directly
        if self.isBuiltIn(trimmed) {
            return trimmed
        }

        // Custom providers: ensure "custom:" prefix
        if trimmed.hasPrefix("custom:") {
            return trimmed
        }
        return "custom:\(trimmed)"
    }

    /// Returns all possible keys for a provider (for looking up stored settings)
    func providerKeys(for providerID: String) -> [String] {
        var keys: [String] = []
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return [providerID]
        }

        // Built-in providers: just use the ID
        if self.isBuiltIn(trimmed) {
            return [trimmed]
        }

        // Custom providers: try both with and without prefix
        if trimmed.hasPrefix("custom:") {
            keys.append(trimmed)
            keys.append(String(trimmed.dropFirst("custom:".count)))
        } else {
            keys.append("custom:\(trimmed)")
            keys.append(trimmed)
        }

        return Array(Set(keys))
    }

}

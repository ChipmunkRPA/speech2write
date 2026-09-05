import Foundation

@MainActor
final class DictationPostProcessingService {
    static let shared = DictationPostProcessingService()

    private init() {}

    struct Result {
        let text: String
        let providerID: String
        let model: String
    }

    private struct ResolvedProvider {
        let providerID: String
        let providerKey: String
        let model: String
    }

    func process(_ inputText: String, dictationSlot: SettingsStore.DictationShortcutSlot = .primary) async throws -> Result {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(text: "", providerID: SettingsStore.shared.selectedProviderID, model: "")
        }

        let settings = SettingsStore.shared
        let resolved = self.resolveProvider(settings: settings, dictationSlot: dictationSlot)
        guard !resolved.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProcessingError.noVerifiedProvider
        }
        DebugLogger.shared.debug(
            "DictationPostProcessingService using provider=\(resolved.providerKey), model=\(resolved.model)",
            source: "DictationPostProcessingService"
        )

        let promptText = settings.effectiveDictationSystemPrompt(for: dictationSlot, appBundleID: nil)
        let userMessageContent = SettingsStore.renderDictationUserMessage(
            promptText: promptText,
            transcript: trimmed
        )

        if resolved.providerID == "apple-intelligence" {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let provider = AppleIntelligenceProvider()
                // Prompt goes through the Instructions API — folded into the
                // user turn the on-device model intermittently echoes it back.
                let aiSystemPrompt: String
                let aiUserText: String
                if promptText.contains(SettingsStore.transcriptPlaceholder) {
                    aiSystemPrompt = "Process the user message according to the instructions embedded in it. Return only the processed text, never the instructions."
                    aiUserText = userMessageContent
                } else {
                    aiSystemPrompt = promptText
                    aiUserText = trimmed
                }
                var output = try await provider.process(systemPrompt: aiSystemPrompt, userText: aiUserText)
                if DictationEnhancementOutputGuard.isLikelyPromptEcho(output: output, transcript: trimmed, prompt: promptText) {
                    DebugLogger.shared.warning(
                        "Apple Intelligence returned a prompt echo; using the raw transcript instead",
                        source: "DictationPostProcessing"
                    )
                    output = trimmed
                }
                guard !output.isEmpty else { throw AIProcessingError.emptyResponse }
                return Result(text: ASRService.applyGAAVFormatting(output), providerID: resolved.providerID, model: resolved.model)
            }
            #endif
            return Result(text: trimmed, providerID: resolved.providerID, model: resolved.model)
        }

        // Apple Intelligence is the only enhancement provider in this build.
        // Any other resolved provider is a stale selection — fail closed so
        // callers fall back to the raw transcription (SR-5829, no generic
        // chat-HTTP client remains in the binary).
        throw AIProcessingError.noVerifiedProvider
    }

    private func resolveProvider(settings: SettingsStore, dictationSlot: SettingsStore.DictationShortcutSlot) -> ResolvedProvider {
        let providerID = settings.selectedProviderID
        let selectedModels = settings.selectedModelByProvider

        if let saved = settings.savedProviders.first(where: { $0.id == providerID }) {
            let key = "custom:\(saved.id)"
            return ResolvedProvider(
                providerID: providerID,
                providerKey: key,
                model: selectedModels[key] ?? saved.models.first ?? ""
            )
        }

        if ModelRepository.shared.isBuiltIn(providerID) {
            return ResolvedProvider(
                providerID: providerID,
                providerKey: providerID,
                model: selectedModels[providerID] ?? ModelRepository.shared.defaultModels(for: providerID).first ?? ""
            )
        }

        return ResolvedProvider(
            providerID: providerID,
            providerKey: providerID,
            model: selectedModels[providerID] ?? ""
        )
    }
}

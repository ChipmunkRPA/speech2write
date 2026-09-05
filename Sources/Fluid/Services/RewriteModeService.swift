import AppKit
import Combine
import Foundation

@MainActor
final class RewriteModeService: ObservableObject {
    @Published var originalText: String = ""
    @Published var selectedContextText: String = ""
    @Published var rewrittenText: String = ""
    @Published var streamingThinkingText: String = "" // Real-time thinking tokens for UI
    @Published var isProcessing = false
    @Published var conversationHistory: [Message] = []
    @Published var isWriteMode: Bool = false // true = no text selected (write/improve), false = text selected (rewrite)
    private var promptAppBundleID: String?

    private let textSelectionService = TextSelectionService.shared
    private let typingService = TypingService()
    private var forcePromptTraceToConsole: Bool {
        ProcessInfo.processInfo.environment["FLUID_PROMPT_TRACE"] == "1"
    }

    private var diagnosticsEnabled: Bool {
        if ProcessInfo.processInfo.environment["FLUID_REWRITE_DIAGNOSTICS"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "RewriteModeDiagnosticsEnabled")
    }

    private var shouldTracePromptProcessing: Bool {
        if let explicit = UserDefaults.standard.object(forKey: "RewriteModePromptTraceEnabled") as? Bool {
            return explicit
        }
        // Default OFF to avoid logging prompt/context content in normal usage.
        return false
    }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let content: String

        enum Role: Equatable {
            case user
            case assistant
        }
    }

    func captureSelectedText() -> Bool {
        if let text = textSelectionService.getSelectedText(), !text.isEmpty {
            self.originalText = text
            self.selectedContextText = text
            self.rewrittenText = ""
            self.conversationHistory = []
            self.isWriteMode = false
            if self.shouldTracePromptProcessing {
                self.logPromptTrace("Captured selected context", value: text)
            }
            return true
        }
        return false
    }

    /// Start rewrite mode without selected text - user will provide text via voice
    func startWithoutSelection() {
        self.originalText = ""
        self.selectedContextText = ""
        self.rewrittenText = ""
        self.conversationHistory = []
        self.isWriteMode = true
        if self.shouldTracePromptProcessing {
            self.logPromptTrace("Starting edit with no selected context", value: "<empty>")
        }
    }

    /// Set the original text directly (from voice input when no text was selected)
    func setOriginalText(_ text: String) {
        self.originalText = text
        self.rewrittenText = ""
        self.conversationHistory = []
    }

    func processRewriteRequest(_ prompt: String) async {
        let startTime = Date()
        self.appendDiagnosticLog(
            "processRewriteRequest start | promptChars=\(prompt.count) | hadOriginal=\(!self.originalText.isEmpty) | contextChars=\(self.selectedContextText.count)"
        )
        // If no original text, we're in "Write Mode" - generate content based on user's request
        if self.originalText.isEmpty {
            self.originalText = prompt
            self.isWriteMode = true

            // Write Mode: User is asking AI to write/generate something
            self.conversationHistory.append(Message(role: .user, content: prompt))
        } else {
            // Rewrite Mode: User has selected text and is giving instructions
            self.isWriteMode = false
            let hasContext = !self.selectedContextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if self.conversationHistory.isEmpty {
                let rewritePrompt: String
                if hasContext {
                    rewritePrompt = """
                    User's instruction: \(prompt)

                    Apply the instruction to the selected context. Output ONLY the rewritten text, nothing else.
                    """
                } else {
                    rewritePrompt = """
                    User's instruction: \(prompt)

                    Output ONLY the requested text, nothing else.
                    """
                }
                self.conversationHistory.append(Message(role: .user, content: rewritePrompt))
            } else {
                // Follow-up request
                self.conversationHistory.append(Message(role: .user, content: "Follow-up instruction: \(prompt)\n\nApply this to the previous result. Output ONLY the updated text."))
            }
        }

        guard !self.conversationHistory.isEmpty else { return }

        self.isProcessing = true

        do {
            let response = try await callLLM(messages: conversationHistory, isWriteMode: isWriteMode)
            self.conversationHistory.append(Message(role: .assistant, content: response))
            self.rewrittenText = response
            self.isProcessing = false
            self.appendDiagnosticLog(
                "processRewriteRequest success | writeMode=\(self.isWriteMode) | outputChars=\(response.count) | latency=\(String(format: "%.2fs", Date().timeIntervalSince(startTime)))"
            )
        } catch {
            self.conversationHistory.append(Message(role: .assistant, content: "Error: \(error.localizedDescription)"))
            self.isProcessing = false
            self.appendDiagnosticLog(
                "processRewriteRequest failure | writeMode=\(self.isWriteMode) | error=\(error.localizedDescription)"
            )
        }
    }

    func acceptRewrite() {
        guard !self.rewrittenText.isEmpty else { return }
        NSApp.hide(nil) // Restore focus to the previous app
        self.typingService.typeTextInstantly(self.rewrittenText)
    }

    func clearState() {
        self.originalText = ""
        self.selectedContextText = ""
        self.rewrittenText = ""
        self.streamingThinkingText = ""
        self.conversationHistory = []
        self.isWriteMode = false
        self.promptAppBundleID = nil
    }

    func setPromptAppBundleID(_ bundleID: String?) {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.promptAppBundleID = (trimmed?.isEmpty == true) ? nil : trimmed
    }

    // MARK: - LLM Integration

    private func callLLM(messages: [Message], isWriteMode: Bool) async throws -> String {
        let settings = SettingsStore.shared
        let promptMode: SettingsStore.PromptMode = .edit
        let appBundleID = self.promptAppBundleID
        let selectedProfile = settings.resolvedPromptProfile(for: promptMode, appBundleID: appBundleID)
        let selectedPromptName: String = {
            if let profile = selectedProfile {
                return profile.name.isEmpty ? "Untitled Prompt" : profile.name
            }
            return "Default Edit"
        }()
        let promptBody = settings.effectivePromptBody(for: promptMode, appBundleID: appBundleID)
        let builtInDefaultPrompt = SettingsStore.defaultSystemPromptText(for: promptMode)
        let systemPromptBeforeContext = settings.effectiveSystemPrompt(for: promptMode, appBundleID: appBundleID)
        // Use global provider/model when linked, otherwise use Edit Mode's independent settings.
        let providerID: String = {
            if settings.rewriteModeLinkedToGlobal {
                return settings.selectedProviderID
            }
            return settings.rewriteModeSelectedProviderID
        }()
        guard !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "RewriteMode",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No verified AI provider selected"]
            )
        }
        guard self.isProviderVerified(providerID, settings: settings) else {
            throw NSError(
                domain: "RewriteMode",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Selected AI provider is not verified"]
            )
        }

        var systemPrompt = systemPromptBeforeContext
        let contextText = self.selectedContextText.trimmingCharacters(in: .whitespacesAndNewlines)
        var contextBlock = ""
        contextBlock = SettingsStore.runtimeContextBlock(
            context: self.selectedContextText,
            template: SettingsStore.contextTemplateText()
        )
        if !contextBlock.isEmpty {
            systemPrompt = "\(systemPrompt)\n\n\(contextBlock)"
            DebugLogger.shared.debug("Injected selected-text context into \(promptMode.rawValue) prompt", source: "RewriteModeService")
        }

        if self.shouldTracePromptProcessing {
            let messageDump = messages.map {
                let role = ($0.role == .user) ? "user" : "assistant"
                return "[\(role)]\n\($0.content)"
            }.joined(separator: "\n\n")
            self.logPromptTrace("Mode", value: isWriteMode ? "Edit (write)" : "Edit (rewrite)")
            self.logPromptTrace("Selected prompt profile", value: selectedPromptName)
            self.logPromptTrace("Prompt body (custom/default body)", value: promptBody)
            self.logPromptTrace("Built-in default system prompt (baseline)", value: builtInDefaultPrompt)
            self.logPromptTrace("System prompt before context", value: systemPromptBeforeContext)
            self.logPromptTrace("Selected context text", value: contextText.isEmpty ? "<empty>" : contextText)
            self.logPromptTrace("Context block injected", value: contextBlock.isEmpty ? "<none>" : contextBlock)
            self.logPromptTrace("Final system prompt sent to model", value: systemPrompt)
            self.logPromptTrace("Conversation input (Q/history)", value: messageDump.isEmpty ? "<empty>" : messageDump)
        }

        // Route to Apple Intelligence if selected
        if providerID == "apple-intelligence" {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let provider = AppleIntelligenceProvider()
                let messageTuples = messages
                    .map { (role: $0.role == .user ? "user" : "assistant", content: $0.content) }
                DebugLogger.shared.debug("Using Apple Intelligence for edit mode", source: "RewriteModeService")
                let output = try await provider.processRewrite(messages: messageTuples, systemPrompt: systemPrompt)
                if self.shouldTracePromptProcessing {
                    self.logPromptTrace("Model answer (A)", value: output)
                }
                return output
            }
            #endif
            throw NSError(
                domain: "RewriteMode",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence not available"]
            )
        }

        // Apple Intelligence is the only enhancement provider in this build.
        // Any other verified selection is stale — fail with a clear message
        // (SR-5829, no generic chat-HTTP client remains in the binary).
        self.appendDiagnosticLog("Unsupported provider for Edit mode | provider=\(providerID)")
        throw NSError(
            domain: "RewriteMode",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "Only Apple Intelligence is supported for Edit mode in this build"]
        )
    }

    private func logPromptTrace(_ title: String, value: String) {
        let line = "[PromptTrace][Edit] \(title):\n\(value)"
        if self.forcePromptTraceToConsole {
            print(line)
        }
        self.appendDiagnosticLog(line)
    }

    private func appendDiagnosticLog(_ message: String) {
        guard self.diagnosticsEnabled || self.forcePromptTraceToConsole else { return }
        let line = "[RewriteModeService] \(message)"
        FileLogger.shared.append(line: line)
        DebugLogger.shared.debug(line, source: "RewriteModeService")
    }

    private func isProviderVerified(_ providerID: String, settings: SettingsStore) -> Bool {
        // Apple Intelligence is the only verifiable provider in this build.
        guard providerID == "apple-intelligence" else { return false }
        return settings.verifiedProviderFingerprints["apple-intelligence"] == "apple-intelligence"
    }
}

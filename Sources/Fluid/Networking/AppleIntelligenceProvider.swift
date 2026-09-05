import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Intelligence Availability Service

enum AppleIntelligenceService {
    /// Whether the current OS supports FoundationModels (compile-time + runtime check)
    static var isSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    /// Whether Apple Intelligence is available and enabled on this device
    static var isAvailable: Bool {
        guard isSupported else { return false }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Human-readable reason why Apple Intelligence is unavailable
    static var unavailabilityReason: String? {
        if !isSupported {
            return "Requires macOS 26 (Tahoe) or later"
        }
        if !isAvailable {
            return "Enable in System Settings → Apple Intelligence & Siri"
        }
        return nil
    }
}

// MARK: - Apple Intelligence Provider

#if canImport(FoundationModels)
@available(macOS 26.0, *)
final class AppleIntelligenceProvider {
    /// Process text with a system prompt (for transcription enhancement).
    /// The system prompt must go through the Instructions API: the on-device
    /// model treats instructions and prompt content differently, and folding
    /// both into one prompt makes it intermittently echo the instructions
    /// back as output.
    func process(systemPrompt: String, userText: String) async throws -> String {
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = trimmedSystemPrompt.isEmpty
            ? LanguageModelSession()
            : LanguageModelSession(instructions: trimmedSystemPrompt)

        let response = try await session.respond(to: userText)
        return response.content
    }

    /// Process rewrite/write requests with conversation history
    func processRewrite(messages: [(role: String, content: String)], systemPrompt: String) async throws -> String {
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = trimmedSystemPrompt.isEmpty
            ? LanguageModelSession()
            : LanguageModelSession(instructions: trimmedSystemPrompt)

        // Build the conversation as a single prompt since FoundationModels
        // doesn't have the same multi-turn API as OpenAI
        var fullPrompt = ""

        // Add conversation history
        for message in messages {
            if message.role == "user" {
                fullPrompt += "User: \(message.content)\n\n"
            } else if message.role == "assistant" {
                fullPrompt += "Assistant: \(message.content)\n\n"
            }
        }

        fullPrompt += "Assistant:"

        let response = try await session.respond(to: fullPrompt)
        return response.content
    }
}
#endif

// MARK: - Dictation Output Guard

/// Detects when an enhancement model returned its own instructions instead of
/// the cleaned transcript (observed intermittently with the on-device Apple
/// Intelligence model). Callers fall back to the raw transcript on detection —
/// typing the user's words unpolished is always safer than typing the prompt.
enum DictationEnhancementOutputGuard {
    static func isLikelyPromptEcho(output: String, transcript: String, prompt: String) -> Bool {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return false }

        // Cleaned dictation stays in the transcript's length ballpark. A long
        // output that also reproduces instruction lines verbatim is an echo;
        // an extremely long output is rejected even without overlap.
        if trimmedOutput.count > max(transcript.count * 3, transcript.count + 400) {
            if self.containsInstructionLines(trimmedOutput, prompt: prompt, minimumMatches: 1) { return true }
            return trimmedOutput.count > transcript.count * 8 + 800
        }

        return self.containsInstructionLines(trimmedOutput, prompt: prompt, minimumMatches: 2)
    }

    private static func containsInstructionLines(_ output: String, prompt: String, minimumMatches: Int) -> Bool {
        var matches = 0
        for line in prompt.split(separator: "\n") {
            let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.count >= 25 else { continue }
            if output.contains(candidate) {
                matches += 1
                if matches >= minimumMatches { return true }
            }
        }
        return false
    }
}

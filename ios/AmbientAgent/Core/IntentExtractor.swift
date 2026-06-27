import Foundation
import FoundationModels

/// Wraps Apple's on-device language model. Takes the fused conversation context
/// (transcript + visual context + user memory) and produces a `TaskSpec`.
struct IntentExtractor {

    enum ExtractorError: Error, LocalizedError {
        case modelUnavailable(String)
        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let why): return "On-device model unavailable: \(why)"
            }
        }
    }

    /// Load the on-device model ahead of the first real request (call on launch).
    static func warm() async {
        guard availabilityMessage() == nil else { return }
        let session = LanguageModelSession(instructions: "Warmup.")
        _ = try? await session.respond(to: "Hi")
    }

    /// Check Apple Intelligence availability up front so we can fail friendly.
    static func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use the assistant."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable(let other):
            return "On-device model unavailable (\(other))."
        @unknown default:
            return "On-device model unavailable."
        }
    }

    func extract(transcript: String,
                 visualContext: String?,
                 calendar: [String] = [],
                 memory: UserProfile) async throws -> TaskSpec {

        if let msg = Self.availabilityMessage() {
            throw ExtractorError.modelUnavailable(msg)
        }

        let session = LanguageModelSession(instructions: Self.instructions(memory: memory))

        var prompt = "User said: \"\(transcript)\""
        if let vc = visualContext, !vc.isEmpty {
            prompt += "\nCamera sees: \(vc)"
        }
        if !calendar.isEmpty {
            prompt += "\nUpcoming calendar:\n" + calendar.map { "  - \($0)" }.joined(separator: "\n")
        }
        prompt += "\nProduce the TaskSpec."

        let response = try await session.respond(to: prompt, generating: TaskSpec.self)
        return response.content
    }

    private static func instructions(memory: UserProfile) -> String {
        """
        You convert a short spoken request into a structured TaskSpec for an agent
        system to execute later. You DO NOT perform the task yourself.

        Rules:
        - Pick the single best `intent`.
        - For messages, resolve the recipient against the user's known contacts and
          put the resolved name (or the alias if unknown) in `recipient`, and the
          message text in `messageBody`.
        - Only set `needsClarification` = true when you genuinely cannot proceed
          without more info; otherwise make reasonable assumptions and fill slots.
        - Keep `summary` to one sentence.

        \(memory.promptContext())
        """
    }
}

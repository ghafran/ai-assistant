import Foundation
import FoundationModels

/// The structured handoff the on-device loop emits for the cloud agent layer.
/// The local model NEVER executes the task — it only fills in this shape.
///
/// `@Generable` + `@Guide` constrain the on-device model so the output is
/// guaranteed to match this type (guided generation), no JSON parsing/repair.
@Generable
struct TaskSpec: Equatable, Codable {
    @Guide(description: "The coarse action class that best fits the request.")
    var intent: Intent

    @Guide(description: "One short sentence restating what the user wants, in plain language.")
    var summary: String

    @Guide(description: "Recipient name or alias for a message (e.g. 'g'), else empty string.")
    var recipient: String

    @Guide(description: "The exact message body to send, else empty string.")
    var messageBody: String

    @Guide(description: "Destination or subject for travel/search, else empty string.")
    var destination: String

    @Guide(description: "Timeframe in the user's words, e.g. 'this weekend', else empty string.")
    var timeframe: String

    @Guide(description: "Set true ONLY if the request cannot be acted on without asking the user something.")
    var needsClarification: Bool

    @Guide(description: "The single follow-up question to ask, else empty string.")
    var clarifyingQuestion: String

    @Guide(description: "Your confidence from 0.0 to 1.0 that this captures the user's intent.", .range(0.0...1.0))
    var confidence: Double
}

@Generable
enum Intent: String, Codable, CaseIterable {
    case bookTravel = "book_travel"
    case sendMessage = "send_message"
    case reminder = "reminder"
    case search = "search"
    case unknown = "unknown"
}

import Foundation

/// The tiny contract shared by the watchOS button and the iOS receiver.
/// Compiled into both targets.
enum WatchMessage {
    static let key = "action"
    static let wake = "wake"

    static var wakePayload: [String: Any] { [key: wake] }

    static func isWake(_ message: [String: Any]) -> Bool {
        message[key] as? String == wake
    }
}

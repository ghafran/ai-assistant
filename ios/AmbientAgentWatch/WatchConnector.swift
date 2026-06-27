import Foundation
import WatchConnectivity

/// The watch side of the link. Tapping the button sends a `wake` to the phone.
/// Uses sendMessage when the phone is reachable (instant), and falls back to a
/// queued transfer (which can wake the phone app in the background) otherwise.
@MainActor
final class WatchConnector: NSObject, ObservableObject, WCSessionDelegate {
    @Published var lastSentAt: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendWake() {
        let session = WCSession.default
        let payload = WatchMessage.wakePayload
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // Immediate send failed — queue it so it still gets there.
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
        lastSentAt = Date()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
}

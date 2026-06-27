import Foundation
import WatchConnectivity

/// The phone side of the link. When the watch sends `wake`, it calls into the
/// conversation loop — the same entry point the on-screen button uses.
@MainActor
final class WatchLink: NSObject, WCSessionDelegate {
    private let onWake: () -> Void

    init(onWake: @escaping () -> Void) {
        self.onWake = onWake
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Reachable path (phone in foreground / active session).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    // Queued path (can wake the phone app in the background).
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        deliver(userInfo)
    }

    private nonisolated func deliver(_ payload: [String: Any]) {
        guard WatchMessage.isWake(payload) else { return }
        Task { @MainActor in self.onWake() }
    }

    // Required on iOS so a re-paired watch keeps working.
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

#if os(iOS)
import Foundation
import WatchConnectivity

/// Mirrors the widget snapshot to the paired Apple Watch as WatchConnectivity application
/// context: the system persists it and delivers the latest value when the watch app wakes,
/// with no polling and no extra battery cost. Push-only — the watch never sends commands.
final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchBridge()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func push(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        // Application context replaces the previous value — always the freshest state.
        try? session.updateApplicationContext(["snapshot": data])
    }

    // MARK: WCSessionDelegate (connection lifecycle only — nothing flows watch → phone)

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after a watch switch so the new watch keeps receiving updates.
        session.activate()
    }
}
#endif

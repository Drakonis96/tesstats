import Foundation
import WatchConnectivity

/// Receives the iPhone app's `WidgetSnapshot` over WatchConnectivity. The phone pushes it
/// as application context, which the system persists and delivers even when this app was
/// not running — so the watch always has the last known state without polling anything.
@Observable
final class WatchSnapshotStore: NSObject, WCSessionDelegate, @unchecked Sendable {
    private(set) var snapshot: WidgetSnapshot?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        decode(session.receivedApplicationContext)
    }

    private func decode(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        Task { @MainActor in
            self.snapshot = snap
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        decode(session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        decode(applicationContext)
    }
}

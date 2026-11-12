import Foundation
import WatchConnectivity

/// Whether an Apple Watch is paired with this iPhone. Every iPhone can schedule watch workouts, so that alone doesn't
/// say whether the athlete has a watch; Watch Connectivity does, and it works without TrackStar having a watch app.
/// Calls `onChange` (on the main actor) once it knows, and again if a watch is paired or unpaired later.
nonisolated final class WatchPairing: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onChange: @MainActor @Sendable (Bool) -> Void

    init(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.onChange = onChange
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func report(_ session: WCSession) {
        let paired = session.isPaired
        Task { @MainActor in onChange(paired) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        report(session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) { report(session) }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: carry on with the new one.
        session.activate()
    }
}

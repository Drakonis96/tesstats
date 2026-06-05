import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if os(iOS)
import ActivityKit
#endif

/// Bridges the live vehicle state to the widget extension: writes the shared App Group
/// snapshot, nudges WidgetKit to reload, and starts/updates/ends the charging Live Activity.
/// All read-only — it only reflects TeslaMate data.
@MainActor
enum WidgetBridge {
    private static var lastSnapshotWrite = Date.distantPast
    private static var lastActivityUpdate = Date.distantPast
    private static let store = WidgetSharedStore()

    static func update(state: VehicleState, carName: String, config: ServerConfig, cache: CacheStore, force: Bool = false) {
        // Live Activity is evaluated every call (cheap, no disk) so it starts/ends promptly.
        #if os(iOS)
        updateLiveActivity(state: state, carName: carName, config: config)
        #endif

        // The widget snapshot + timeline reload are throttled (they hit disk and the OS).
        let now = Date()
        guard force || now.timeIntervalSince(lastSnapshotWrite) >= 20 else { return }
        lastSnapshotWrite = now

        var snap = WidgetSnapshot()
        snap.carName = carName
        snap.stateRaw = state.state?.rawValue ?? (state.isCharging ? "charging" : "offline")
        snap.batteryLevel = state.batteryLevel ?? 0
        snap.usableLevel = state.usableBatteryLevel
        snap.rangeKm = state.range(for: config.rangeKind)
        snap.isCharging = state.isCharging
        snap.chargerPowerKw = state.chargerPower
        snap.chargeLimitSoc = state.chargeLimitSoc
        snap.timeToFullHours = state.timeToFullCharge
        snap.odometerKm = state.odometer
        snap.isImperial = config.units == .imperial
        snap.lastUpdated = state.lastUpdated == .distantPast ? now : state.lastUpdated
        if let trip = cache.loadDrives(carID: state.carID).first {
            snap.lastTripTitle = "\(trip.originName) → \(trip.destinationName)"
            snap.lastTripDistanceKm = trip.distanceKm
            snap.lastTripDate = trip.startDate
        }

        store.save(snap)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Clear the shared snapshot, stop activities and refresh widgets (used by "Delete all data").
    static func clearAll() {
        store.clear()
        stopLiveActivities()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Tear down any running Live Activity (e.g. when the user disables it).
    static func stopLiveActivities() {
        #if os(iOS)
        for activity in Activity<ChargingActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    #if os(iOS)
    private static func updateLiveActivity(state: VehicleState, carName: String, config: ServerConfig) {
        guard config.liveActivityEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            stopLiveActivities()
            return
        }
        let content = ChargingActivityAttributes.ContentState(
            batteryLevel: state.batteryLevel ?? 0,
            chargeLimitSoc: state.chargeLimitSoc ?? 100,
            chargerPowerKw: state.chargerPower ?? 0,
            timeToFullHours: state.timeToFullCharge ?? 0,
            rangeKm: state.range(for: config.rangeKind) ?? 0,
            isImperial: config.units == .imperial,
            isComplete: !state.isCharging)

        let existing = Activity<ChargingActivityAttributes>.activities.first

        if state.isCharging {
            if let existing {
                // Throttle in-flight updates to avoid ActivityKit rate limits.
                let now = Date()
                guard now.timeIntervalSince(lastActivityUpdate) >= 5 else { return }
                lastActivityUpdate = now
                Task { await existing.update(ActivityContent(state: content, staleDate: nil)) }
            } else {
                lastActivityUpdate = Date()
                do {
                    _ = try Activity.request(
                        attributes: ChargingActivityAttributes(carName: carName),
                        content: ActivityContent(state: content, staleDate: Date().addingTimeInterval(3600)),
                        pushType: nil)
                } catch {
                    // Rate-limited or disabled mid-flight — ignore.
                }
            }
        } else if let existing {
            // Charging ended — show the final state briefly, then dismiss.
            Task {
                await existing.end(ActivityContent(state: content, staleDate: nil),
                                   dismissalPolicy: .after(Date().addingTimeInterval(8)))
            }
        }
    }
    #endif
}

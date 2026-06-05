import Foundation
import UserNotifications

struct NotificationPreferences: Codable, Sendable, Equatable {
    var enabled = true
    var chargeComplete = true
    var chargeStarted = false
    var chargeTargetReached = true
    var leftUnplugged = true
    var pluggedNotCharging = true
    var openingsOrUnlocked = true
    var lowBattery = true
    var lowBatteryThreshold = 20
    var softwareUpdate = true
    var geofence = true
    var sentryInferred = true

    // Tire pressure (TPMS) — threshold stored canonically in bar; the UI lets the user
    // enter it in bar or psi. Default ~2.4 bar (≈ 35 psi), a common low-pressure warning point.
    var tpmsLow = false
    var tpmsThresholdBar = 2.4
    var tpmsUnitIsPsi = false

    // Quiet hours — minutes since midnight; suppresses local alerts inside the window.
    var quietHoursEnabled = false
    var quietStartMinutes = 22 * 60      // 22:00
    var quietEndMinutes = 7 * 60         // 07:00

    static let barPerPsi = 0.0689476

    var tpmsThresholdDisplay: Double {
        get { tpmsUnitIsPsi ? tpmsThresholdBar / Self.barPerPsi : tpmsThresholdBar }
        set { tpmsThresholdBar = tpmsUnitIsPsi ? newValue * Self.barPerPsi : newValue }
    }
}

/// On-device notification engine. Generates **local** notifications from live MQTT
/// transitions whenever the app has execution (foreground, or a background window the OS
/// grants). iOS cannot poll 24/7 reliably in the background — for guaranteed alerts with
/// the app closed, run the optional APNs push microservice (see /server). This is stated
/// honestly here and in the UI.
@MainActor
@Observable
final class NotificationEngine {
    var prefs: NotificationPreferences
    var authorized = false

    private let defaultsKey = "tesstats.notification.prefs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let loaded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            self.prefs = loaded
        } else {
            self.prefs = NotificationPreferences()
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: defaultsKey) }
    }

    /// Restore notification preferences to their defaults (used by "Delete all data").
    func resetToDefaults() {
        prefs = NotificationPreferences()
        defaults.removeObject(forKey: defaultsKey)
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = granted
    }

    /// Diff two consecutive snapshots and emit notifications for noteworthy transitions.
    func process(previous: VehicleState?, current: VehicleState, carName: String) {
        guard prefs.enabled, let previous else { return }

        // Charge complete
        if prefs.chargeComplete,
           previous.chargingState != .complete, current.chargingState == .complete {
            post(id: "charge-complete",
                 title: L("Charging complete"),
                 body: L("\(carName) finished charging at \(current.batteryLevel ?? 100)%."))
        }

        // Charge started
        if prefs.chargeStarted,
           previous.chargingState != .charging, current.chargingState == .charging {
            let power = current.chargerPower.map { " \(Int($0)) kW" } ?? ""
            post(id: "charge-started",
                 title: L("Charging started"),
                 body: L("\(carName) started charging\(power) at \(current.batteryLevel ?? 0)%."))
        }

        // Charge target (limit SoC) reached
        if prefs.chargeTargetReached, let limit = current.chargeLimitSoc,
           let prev = previous.batteryLevel, let now = current.batteryLevel,
           prev < limit, now >= limit, current.pluggedIn == true || current.isCharging {
            post(id: "charge-target",
                 title: L("Charge limit reached"),
                 body: L("\(carName) hit its \(limit)% charge limit."))
        }

        // Tire pressure low (any wheel crosses below the configured threshold)
        if prefs.tpmsLow {
            let low = current.tiresBelow(bar: prefs.tpmsThresholdBar)
            let wasLow = !previous.tiresBelow(bar: prefs.tpmsThresholdBar).isEmpty
            if !low.isEmpty, !wasLow {
                let psi = prefs.tpmsUnitIsPsi
                let detail = low.map { t -> String in
                    let v = psi ? t.bar / NotificationPreferences.barPerPsi : t.bar
                    let unit = psi ? "psi" : "bar"
                    return "\(t.label) \(String(format: "%.1f", v)) \(unit)"
                }.joined(separator: ", ")
                post(id: "tpms-low",
                     title: L("Low tire pressure"),
                     body: L("\(carName): \(detail)."))
            }
        }

        // Parked and left unplugged
        if prefs.leftUnplugged, previous.isDriving, !current.isDriving, current.pluggedIn == false {
            post(id: "unplugged",
                 title: L("Not plugged in"),
                 body: L("\(carName) was parked without being plugged in."))
        }

        // Plugged in but not charging
        if prefs.pluggedNotCharging,
           current.pluggedIn == true,
           previous.chargingState != .stopped, current.chargingState == .stopped {
            post(id: "plugged-idle",
                 title: L("Plugged in, not charging"),
                 body: L("\(carName) is connected but charging is stopped."))
        }

        // Openings / unlocked after parking
        if prefs.openingsOrUnlocked, !current.isDriving {
            if !previous.anyOpeningOpen, current.anyOpeningOpen {
                post(id: "opening",
                     title: L("Something is open"),
                     body: L("A door, window, frunk or trunk on \(carName) is open."))
            }
            if previous.locked == true, current.locked == false {
                post(id: "unlocked",
                     title: L("Vehicle unlocked"),
                     body: L("\(carName) is unlocked while parked."))
            }
        }

        // Low battery threshold crossing
        if prefs.lowBattery, let prev = previous.batteryLevel, let now = current.batteryLevel,
           prev > prefs.lowBatteryThreshold, now <= prefs.lowBatteryThreshold {
            post(id: "low-battery",
                 title: L("Low battery"),
                 body: L("\(carName) dropped to \(now)%."))
        }

        // Software update available
        if prefs.softwareUpdate, previous.updateAvailable != true, current.updateAvailable == true {
            post(id: "update",
                 title: L("Software update available"),
                 body: L("\(carName): \(current.updateVersion ?? "new version") is ready to install."))
        }

        // Geofence enter / exit
        if prefs.geofence, previous.geofence != current.geofence {
            if let g = current.geofence, !g.isEmpty {
                post(id: "geofence-enter",
                     title: L("Arrived"),
                     body: L("\(carName) entered \(g)."))
            } else if let g = previous.geofence, !g.isEmpty {
                post(id: "geofence-exit",
                     title: L("Departed"),
                     body: L("\(carName) left \(g)."))
            }
        }

        // Inferred Sentry event (center_display_state == 7). Honest: inference, no video.
        if prefs.sentryInferred, !previous.sentryBannerActive, current.sentryBannerActive {
            let place = current.geofence ?? current.activeRouteDestination ?? L("its location")
            post(id: "sentry",
                 title: L("Possible Sentry event"),
                 body: L("\(carName) showed the Sentry banner near \(place). Inferred from the screen — any clip is on the car's USB, not available via TeslaMate."))
        }
    }

    /// True if `date` falls inside the user's quiet-hours window (handles overnight wrap).
    func isQuietTime(_ date: Date = Date()) -> Bool {
        guard prefs.quietHoursEnabled else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = prefs.quietStartMinutes, end = prefs.quietEndMinutes
        if start == end { return false }
        return start < end ? (mins >= start && mins < end)
                           : (mins >= start || mins < end)   // window crosses midnight
    }

    private func post(id: String, title: String, body: String) {
        if isQuietTime() { return }   // respect quiet hours for on-device alerts
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

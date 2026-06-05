import Foundation
#if os(iOS)
import ActivityKit
#endif

/// App Group shared between the app and the widget/Live-Activity extension (separate process).
enum AppGroup {
    static let identifier = "group.com.tesstats.app"
}

/// Minimal, self-contained snapshot the widgets render. Written by the app on every live
/// update and read by the widget timeline provider. Kept separate from the rich `VehicleState`
/// so the widget target needs none of the app's MQTT / model layer.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    var carName = "Tesla"
    var stateRaw = "offline"            // online / charging / driving / asleep / offline …
    var batteryLevel = 0
    var usableLevel: Int?
    var rangeKm: Double?
    var isCharging = false
    var chargerPowerKw: Double?
    var chargeLimitSoc: Int?
    var timeToFullHours: Double?
    var odometerKm: Double?
    var isImperial = false
    var lastUpdated = Date.distantPast
    var lastTripTitle: String?
    var lastTripDistanceKm: Double?
    var lastTripDate: Date?

    static let placeholder: WidgetSnapshot = {
        var s = WidgetSnapshot()
        s.carName = "Tesla"
        s.stateRaw = "charging"
        s.batteryLevel = 72
        s.usableLevel = 71
        s.rangeKm = 358
        s.isCharging = true
        s.chargerPowerKw = 11
        s.chargeLimitSoc = 80
        s.timeToFullHours = 1.2
        s.odometerKm = 28_450
        s.lastUpdated = Date()
        s.lastTripTitle = "Home → Work"
        s.lastTripDistanceKm = 14.2
        s.lastTripDate = Date()
        return s
    }()
}

// MARK: - Unit-aware formatting (no app dependencies)

extension WidgetSnapshot {
    private static let kmPerMile = 1.609344
    var distanceUnit: String { isImperial ? "mi" : "km" }

    func rangeString() -> String {
        guard let rangeKm else { return "—" }
        let v = isImperial ? rangeKm / Self.kmPerMile : rangeKm
        return "\(Int(v.rounded())) \(distanceUnit)"
    }

    func distanceString(_ km: Double?, digits: Int = 1) -> String {
        guard let km else { return "—" }
        let v = isImperial ? km / Self.kmPerMile : km
        return String(format: "%.\(digits)f %@", v, distanceUnit)
    }

    var powerString: String {
        guard let chargerPowerKw, chargerPowerKw > 0 else { return "—" }
        return String(format: "%.0f kW", chargerPowerKw)
    }

    var batteryString: String { "\(batteryLevel)%" }

    static func timeString(hours: Double?) -> String {
        guard let hours, hours > 0 else { return "—" }
        let mins = Int((hours * 60).rounded())
        return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
    }
}

// MARK: - App Group store

struct WidgetSharedStore {
    private let defaults: UserDefaults?
    private let key = "tesstats.widget.snapshot"

    init() { defaults = UserDefaults(suiteName: AppGroup.identifier) }

    func save(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func clear() { defaults?.removeObject(forKey: key) }
}

// MARK: - Live Activity attributes

#if os(iOS)
/// Live Activity describing an in-progress charging session. Read-only — it only mirrors what
/// TeslaMate reports and never controls the car.
struct ChargingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var batteryLevel: Int
        var chargeLimitSoc: Int
        var chargerPowerKw: Double
        var timeToFullHours: Double
        var rangeKm: Double
        var isImperial: Bool
        var isComplete: Bool

        var rangeString: String {
            let v = isImperial ? rangeKm / 1.609344 : rangeKm
            return "\(Int(v.rounded())) \(isImperial ? "mi" : "km")"
        }
        var powerString: String { chargerPowerKw > 0 ? String(format: "%.0f kW", chargerPowerKw) : "—" }
        var etaString: String { WidgetSnapshot.timeString(hours: timeToFullHours) }
        /// 0…1 progress of the current charge toward the target limit.
        var progress: Double {
            let target = max(chargeLimitSoc, batteryLevel, 1)
            return min(1, Double(batteryLevel) / Double(target))
        }
    }

    var carName: String
}
#endif

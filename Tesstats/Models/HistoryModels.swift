import Foundation

// MARK: - Vehicle info (from TeslaMateApi /cars)

struct CarInfo: Sendable, Equatable, Codable {
    var id: Int
    var name: String
    var model: String?
    var trimBadging: String?
    var vin: String?
    var exteriorColor: String?
    var wheelType: String?
    var efficiencyKwhPerKm: Double?
    var totalDrives: Int?
    var totalCharges: Int?
    var totalUpdates: Int?
}

// MARK: - Drives

struct DriveRecord: Identifiable, Sendable, Codable, Hashable {
    let id: Int
    var startDate: Date
    var endDate: Date?
    var startAddress: String?
    var endAddress: String?
    var startGeofence: String?
    var endGeofence: String?
    var distanceKm: Double
    var durationMin: Int
    var startBattery: Int?
    var endBattery: Int?
    var startRangeKm: Double?
    var endRangeKm: Double?
    var avgSpeedKmh: Double?
    var maxSpeedKmh: Double?
    var maxPowerKw: Double?
    var outsideTempAvg: Double?
    var insideTempAvg: Double?
    var startCoord: Coordinate?
    var endCoord: Coordinate?
    /// Path of the drive. May be a rich trace, or just [start, end] when the
    /// positions endpoint is unavailable (documented limitation of TeslaMateApi).
    var path: [Coordinate]

    var originName: String { startGeofence ?? startAddress ?? L("Origin") }
    var destinationName: String { endGeofence ?? endAddress ?? L("Destination") }

    /// Consumption in Wh/km derived from range delta if not provided directly.
    var consumptionWhPerKm: Double?

    var elevationProfile: [Double]   // optional sampled elevation (m) for the detail chart
}

// MARK: - Charges

struct ChargeRecord: Identifiable, Sendable, Codable, Hashable {
    let id: Int
    var startDate: Date
    var endDate: Date?
    var address: String?
    var geofence: String?
    var energyAddedKwh: Double
    var startBattery: Int?
    var endBattery: Int?
    var startRangeKm: Double?
    var endRangeKm: Double?
    var durationMin: Int
    var cost: Double?
    /// Session AVERAGE power (kWh ÷ hours) — the list endpoint has no per-point data, so this
    /// is not the peak. The real peak comes from the per-point curve (`ChargeCurvePoint`).
    var avgPowerKw: Double?
    var coord: Coordinate?
    /// Fast / public DC charging (Supercharger etc.) vs. slower AC/home.
    var isFastCharger: Bool

    var locationName: String { geofence ?? address ?? L("Unknown location") }
    var isHome: Bool { (geofence?.localizedCaseInsensitiveContains("home") ?? false) }
}

// MARK: - Charge curve (per-point kW vs SoC, from the charge-detail endpoint)

struct ChargeCurvePoint: Identifiable, Sendable, Codable, Hashable {
    var id: Date { date }
    var date: Date
    var soc: Int           // battery_level (%)
    var powerKw: Double     // charger_power (kW)
    var voltage: Int?
    var current: Int?
}

// MARK: - Battery health / degradation

struct BatteryHealthPoint: Identifiable, Sendable, Codable, Hashable {
    var id: Date { date }
    var date: Date
    var odometerKm: Double
    /// Observed maximum rated range at ~100% (km) — the degradation curve.
    var maxRangeKm: Double
    var usableCapacityKwh: Double?
}

// MARK: - Aggregates

struct ChargeAggregates: Sendable {
    var totalEnergyKwh: Double = 0
    var totalCost: Double = 0
    var homeEnergyKwh: Double = 0
    var publicEnergyKwh: Double = 0
    var homeCost: Double = 0
    var publicCost: Double = 0
    var sessionCount: Int = 0

    static func from(_ charges: [ChargeRecord]) -> ChargeAggregates {
        var agg = ChargeAggregates()
        for c in charges {
            agg.sessionCount += 1
            agg.totalEnergyKwh += c.energyAddedKwh
            agg.totalCost += c.cost ?? 0
            // Classify AC (home/destination) vs DC fast (public) by power — more reliable
            // than geofence names, which many setups don't configure.
            if c.isFastCharger {
                agg.publicEnergyKwh += c.energyAddedKwh
                agg.publicCost += c.cost ?? 0
            } else {
                agg.homeEnergyKwh += c.energyAddedKwh
                agg.homeCost += c.cost ?? 0
            }
        }
        return agg
    }
}

struct EfficiencySummary: Sendable {
    var avgWhPerKm: Double = 0
    var totalDistanceKm: Double = 0
    var totalDrives: Int = 0
    var maxSpeedKmh: Double = 0

    static func from(_ drives: [DriveRecord]) -> EfficiencySummary {
        var s = EfficiencySummary()
        // Distance-weighted average: a 2 km cold-start drive shouldn't count the same as a
        // 200 km motorway run. (A plain mean of per-drive Wh/km biases the figure high.)
        var weightedSum = 0.0, weightedDistance = 0.0
        for d in drives {
            s.totalDrives += 1
            s.totalDistanceKm += d.distanceKm
            if let m = d.maxSpeedKmh { s.maxSpeedKmh = max(s.maxSpeedKmh, m) }
            if let c = d.consumptionWhPerKm, c > 0, d.distanceKm > 0 {
                weightedSum += c * d.distanceKm
                weightedDistance += d.distanceKm
            }
        }
        if weightedDistance > 0 { s.avgWhPerKm = weightedSum / weightedDistance }
        return s
    }
}

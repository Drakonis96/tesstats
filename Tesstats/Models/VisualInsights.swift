import Foundation

struct DailyHistoryGroup<Item>: Identifiable {
    var day: Date
    var items: [Item]
    var title: String
    var detail: String

    var id: Date { day }
}

enum DailyHistoryGrouper {
    static func group<Item>(
        _ items: [Item],
        calendar: Calendar = .current,
        date: (Item) -> Date,
        title: (Date) -> String,
        detail: ([Item]) -> String
    ) -> [DailyHistoryGroup<Item>] {
        let buckets = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: date(item))
        }
        return buckets.keys.sorted(by: >).map { day in
            let bucket = (buckets[day] ?? []).sorted { date($0) > date($1) }
            return DailyHistoryGroup(day: day, items: bucket, title: title(day), detail: detail(bucket))
        }
    }
}

struct DashboardActivitySegment: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case driving, charging, online
    }

    var id: String { "\(kind.rawValue)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    var kind: Kind
    var start: Date
    var end: Date
}

struct DashboardInsights: Sendable {
    var lastDrive: DriveRecord?
    var efficiency30dWhPerKm: Double?
    var activity48h: [DashboardActivitySegment]
}

enum DashboardInsightEngine {
    static func insights(drives: [DriveRecord], charges: [ChargeRecord], now: Date = Date()) -> DashboardInsights {
        let lastDrive = drives.sorted { $0.startDate > $1.startDate }.first
        let cutoff30 = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let recent = drives.filter { $0.startDate >= cutoff30 }
        let efficiency = EfficiencySummary.from(recent).avgWhPerKm
        return DashboardInsights(
            lastDrive: lastDrive,
            efficiency30dWhPerKm: efficiency > 0 ? efficiency : nil,
            activity48h: activitySegments(drives: drives, charges: charges, now: now)
        )
    }

    static func activitySegments(drives: [DriveRecord], charges: [ChargeRecord], now: Date = Date()) -> [DashboardActivitySegment] {
        let start = now.addingTimeInterval(-48 * 3600)
        var segments: [DashboardActivitySegment] = []
        for drive in drives {
            guard let end = drive.endDate else { continue }
            if let clipped = clip(start: drive.startDate, end: end, windowStart: start, windowEnd: now) {
                segments.append(DashboardActivitySegment(kind: .driving, start: clipped.0, end: clipped.1))
            }
        }
        for charge in charges {
            guard let end = charge.endDate else { continue }
            if let clipped = clip(start: charge.startDate, end: end, windowStart: start, windowEnd: now) {
                segments.append(DashboardActivitySegment(kind: .charging, start: clipped.0, end: clipped.1))
            }
        }
        return segments.sorted { $0.start < $1.start }
    }

    private static func clip(start: Date, end: Date, windowStart: Date, windowEnd: Date) -> (Date, Date)? {
        let a = max(start, windowStart)
        let b = min(end, windowEnd)
        return b > a ? (a, b) : nil
    }
}

struct TripCost: Sendable, Equatable {
    var electricCost: Double
    var fuelEquivalentCost: Double
    var savings: Double
    var pricePerKwh: Double
}

enum TripCostEngine {
    static func cost(
        for drive: DriveRecord,
        pricePerKwh: Double,
        fuelPricePerLiter: Double,
        fuelConsumptionLPer100km: Double
    ) -> TripCost? {
        let energy = energyKwh(for: drive)
        guard energy > 0, pricePerKwh > 0 else { return nil }
        let electric = energy * pricePerKwh
        let liters = drive.distanceKm / 100 * max(0, fuelConsumptionLPer100km)
        let fuel = liters * max(0, fuelPricePerLiter)
        return TripCost(electricCost: electric, fuelEquivalentCost: fuel, savings: fuel - electric, pricePerKwh: pricePerKwh)
    }

    static func energyKwh(for drive: DriveRecord) -> Double {
        if let energy = drive.energyConsumedKwh, energy > 0 { return energy }
        if let wh = drive.consumptionWhPerKm, wh > 0, drive.distanceKm > 0 {
            return wh * drive.distanceKm / 1000
        }
        return 0
    }
}

struct ParkingSession: Identifiable, Sendable, Codable, Hashable {
    var id: String
    var locationName: String
    var startDate: Date
    var endDate: Date?
    var startBattery: Int?
    var endBattery: Int?
    var startRangeKm: Double?
    var endRangeKm: Double?
    var coordinate: Coordinate?
    var energyLostKwh: Double
    var cost: Double
    var isLive: Bool

    var durationMinutes: Int {
        let end = endDate ?? Date()
        return max(0, Int(end.timeIntervalSince(startDate) / 60))
    }

    var rangeLostKm: Double {
        guard let startRangeKm, let endRangeKm else { return 0 }
        return max(0, startRangeKm - endRangeKm)
    }

    var socDelta: Int? {
        guard let startBattery, let endBattery else { return nil }
        return endBattery - startBattery
    }

    var whPerHour: Double? {
        let hours = Double(durationMinutes) / 60
        guard hours > 0, energyLostKwh > 0 else { return nil }
        return energyLostKwh * 1000 / hours
    }
}

enum ParkingSessionEngine {
    static func derive(
        drives: [DriveRecord],
        charges: [ChargeRecord],
        currentState: VehicleState?,
        pricePerKwh: Double,
        efficiencyKwhPerKm: Double?,
        now: Date = Date(),
        minimumMinutes: Int = 30
    ) -> [ParkingSession] {
        let ordered = drives.sorted { $0.startDate < $1.startDate }
        var sessions: [ParkingSession] = []
        for pair in zip(ordered, ordered.dropFirst()) {
            let previous = pair.0
            let next = pair.1
            guard let start = previous.endDate else { continue }
            let end = next.startDate
            let minutes = Int(end.timeIntervalSince(start) / 60)
            guard minutes >= minimumMinutes else { continue }
            if charges.contains(where: { overlaps($0, start: start, end: end) }) { continue }
            let lost = energyLostKwh(startBattery: previous.endBattery,
                                     endBattery: next.startBattery,
                                     startRangeKm: previous.endRangeKm,
                                     endRangeKm: next.startRangeKm,
                                     efficiencyKwhPerKm: efficiencyKwhPerKm)
            sessions.append(ParkingSession(
                id: "park-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))",
                locationName: previous.destinationName,
                startDate: start,
                endDate: end,
                startBattery: previous.endBattery,
                endBattery: next.startBattery,
                startRangeKm: previous.endRangeKm,
                endRangeKm: next.startRangeKm,
                coordinate: previous.endCoord ?? previous.path.last,
                energyLostKwh: lost,
                cost: lost * max(0, pricePerKwh),
                isLive: false
            ))
        }
        if let live = liveSession(from: currentState, pricePerKwh: pricePerKwh, now: now, minimumMinutes: minimumMinutes) {
            sessions.append(live)
        }
        return sessions.sorted { $0.startDate > $1.startDate }
    }

    private static func liveSession(from state: VehicleState?, pricePerKwh: Double, now: Date, minimumMinutes: Int) -> ParkingSession? {
        guard let state, !state.isDriving, !state.isCharging, let start = state.since else { return nil }
        let minutes = Int(now.timeIntervalSince(start) / 60)
        guard minutes >= minimumMinutes else { return nil }
        return ParkingSession(
            id: "live-\(state.carID)",
            locationName: state.geofence ?? state.displayName ?? L("Current location"),
            startDate: start,
            endDate: nil,
            startBattery: state.batteryLevel,
            endBattery: state.batteryLevel,
            startRangeKm: state.range(for: .rated),
            endRangeKm: state.range(for: .rated),
            coordinate: state.coordinate,
            energyLostKwh: 0,
            cost: 0 * max(0, pricePerKwh),
            isLive: true
        )
    }

    private static func energyLostKwh(startBattery: Int?, endBattery: Int?, startRangeKm: Double?, endRangeKm: Double?, efficiencyKwhPerKm: Double?) -> Double {
        if let startBattery, let endBattery, startBattery > endBattery {
            return Double(startBattery - endBattery) / 100 * 75
        }
        if let startRangeKm, let endRangeKm, startRangeKm > endRangeKm, let efficiencyKwhPerKm, efficiencyKwhPerKm > 0 {
            return (startRangeKm - endRangeKm) * efficiencyKwhPerKm
        }
        return 0
    }

    private static func overlaps(_ charge: ChargeRecord, start: Date, end: Date) -> Bool {
        guard let chargeEnd = charge.endDate else { return false }
        return charge.startDate < end && chargeEnd > start
    }
}

enum EventInboxCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case vehicle, tesstats

    var id: String { rawValue }
    var label: String {
        switch self {
        case .vehicle: L("Vehicle")
        case .tesstats: L("Tesstats")
        }
    }
}

struct EventInboxItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var category: EventInboxCategory
    var title: String
    var body: String
    var symbol: String
}

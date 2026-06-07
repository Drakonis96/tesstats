import Foundation

// Pure, value-type analytics derived from the locally-held drive & charge history.
// Everything here is `Sendable` and side-effect free so it can run off the main actor and
// be unit-reasoned about. Views format the raw numbers through `Units`.

// MARK: - Monthly trend point

struct MonthlyStat: Identifiable, Sendable, Hashable {
    var id: Date { month }
    var month: Date                 // first day of the month
    var distanceKm: Double = 0
    var energyChargedKwh: Double = 0
    var chargeCost: Double = 0      // recorded or estimated by the caller
    var driveCount: Int = 0
    var chargeCount: Int = 0
    /// Distance-weighted average consumption (Wh/km) across the month's drives.
    var avgConsumptionWhPerKm: Double = 0
}

// MARK: - Period comparison

struct PeriodComparison: Sendable {
    var label: String                // e.g. "vs last month"
    var distanceKm: (current: Double, previous: Double)
    var energyKwh: (current: Double, previous: Double)
    var cost: (current: Double, previous: Double)
    var consumptionWhPerKm: (current: Double, previous: Double)
    var drives: (current: Int, previous: Int)

    static func delta(_ pair: (current: Double, previous: Double)) -> Double? {
        guard pair.previous > 0 else { return nil }
        return (pair.current - pair.previous) / pair.previous * 100
    }
}

// MARK: - Records / superlatives

struct Superlatives: Sendable {
    var longestDrive: DriveRecord?
    var mostEfficientDrive: DriveRecord?     // lowest Wh/km, min distance applied
    var fastestDrive: DriveRecord?           // highest max speed
    var bestRegenDrive: DriveRecord?         // highest peak regen (most-negative power_min)
    var biggestCharge: ChargeRecord?         // most energy added
    var longestCharge: ChargeRecord?         // longest duration
    var fastestCharge: ChargeRecord?         // highest peak power
    var topSpeedKmh: Double?
    var maxRegenKw: Double?                   // peak regenerative-braking power seen (kW)
}

// MARK: - Cost summary

struct CostSummary: Sendable {
    var totalCost: Double = 0
    var totalEnergyKwh: Double = 0
    var totalDistanceKm: Double = 0
    var costPer100Km: Double?               // currency / 100 km
    var avgPricePerKwh: Double?             // currency / kWh (from sessions with a known cost)
    var monthlyProjection: Double?          // projected spend per month
    var annualProjection: Double?
    var costIsEstimated: Bool = false
}

// MARK: - Usage patterns

struct WeekdayUsage: Identifiable, Sendable, Hashable {
    var id: Int { weekday }                  // 1 = Sunday … 7 = Saturday (Calendar)
    var weekday: Int
    var driveCount: Int = 0
    var distanceKm: Double = 0
}

struct HourUsage: Identifiable, Sendable, Hashable {
    var id: Int { hour }                     // 0…23, drive start hour
    var hour: Int
    var driveCount: Int = 0
}

struct CalendarDay: Identifiable, Sendable, Hashable {
    var id: Date { day }
    var day: Date                            // start of day
    var distanceKm: Double
}

// MARK: - Environmental impact

struct EcoImpact: Sendable {
    var distanceKm: Double = 0
    var litersAvoided: Double = 0            // petrol litres an ICE would have burned
    var co2AvoidedKg: Double = 0             // vs combustion comparison car
    var treeYears: Double = 0               // ~21 kg CO2 absorbed per tree per year
}

// MARK: - Temperature correlation

struct TempConsumptionPoint: Identifiable, Sendable, Hashable {
    var id: Int { index }
    var index: Int
    var outsideTempC: Double
    var consumptionWhPerKm: Double
    var distanceKm: Double
}

struct TempBin: Identifiable, Sendable, Hashable {
    var id: Int { lowerC }
    var lowerC: Int                          // bin lower bound in °C
    var avgConsumptionWhPerKm: Double
    var sampleCount: Int
}

// MARK: - Phantom / vampire drain

struct PhantomDrain: Sendable {
    var avgPercentPerDay: Double
    var avgRangeLossKmPerDay: Double
    var idleSamples: Int                     // number of parked gaps analysed
    var totalIdleDays: Double
}

// MARK: - Charging location

struct ChargingLocation: Identifiable, Sendable, Hashable {
    var id: String { name }
    var name: String
    var sessions: Int = 0
    var energyKwh: Double = 0
    var cost: Double = 0                 // effective: recorded where present, else estimated
    var avgPowerKw: Double = 0
    var isFast: Bool = false
}

// MARK: - Charge pricing

/// Resolves what a charge costs, honoring an optional per-location price override.
/// TeslaMate's recorded cost always wins; otherwise the energy is valued at the location's
/// custom price (when set) or the global default.
struct ChargePricing: Sendable {
    var defaultPricePerKwh: Double
    var perLocation: [String: Double]

    init(defaultPricePerKwh: Double, perLocation: [String: Double] = [:]) {
        self.defaultPricePerKwh = defaultPricePerKwh
        self.perLocation = perLocation
    }

    /// Price applied to a location's *unpriced* sessions — its custom override or the default.
    func price(for locationName: String) -> Double {
        perLocation[locationName] ?? defaultPricePerKwh
    }

    /// Effective cost of a single charge. A recorded cost is used only when it carries a real
    /// value: TeslaMate frequently reports `0` (rather than null) when no cost is configured,
    /// so a `0`/nil falls through to the price-based estimate.
    func cost(for charge: ChargeRecord) -> Double {
        if let recorded = charge.cost, recorded > 0.01 { return recorded }
        return charge.energyAddedKwh * price(for: charge.locationName)
    }
}

// MARK: - Engine

enum StatsEngine {
    private static var calendar: Calendar { Calendar.current }

    // Monthly aggregation ----------------------------------------------------

    static func monthly(drives: [DriveRecord], charges: [ChargeRecord], pricing: ChargePricing) -> [MonthlyStat] {
        let cal = calendar
        var buckets: [Date: MonthlyStat] = [:]
        // Track distance-weighted consumption per month.
        var consWeighted: [Date: (sum: Double, dist: Double)] = [:]

        func month(of date: Date) -> Date? {
            cal.date(from: cal.dateComponents([.year, .month], from: date))
        }

        for d in drives {
            guard let m = month(of: d.startDate) else { continue }
            var stat = buckets[m] ?? MonthlyStat(month: m)
            stat.distanceKm += d.distanceKm
            stat.driveCount += 1
            buckets[m] = stat
            if let c = d.consumptionWhPerKm, c > 0, d.distanceKm > 0 {
                var w = consWeighted[m] ?? (0, 0)
                w.sum += c * d.distanceKm
                w.dist += d.distanceKm
                consWeighted[m] = w
            }
        }
        for c in charges {
            guard let m = month(of: c.startDate) else { continue }
            var stat = buckets[m] ?? MonthlyStat(month: m)
            stat.energyChargedKwh += c.energyAddedKwh
            stat.chargeCount += 1
            stat.chargeCost += pricing.cost(for: c)
            buckets[m] = stat
        }
        for (m, w) in consWeighted where w.dist > 0 {
            buckets[m]?.avgConsumptionWhPerKm = w.sum / w.dist
        }
        return buckets.values.sorted { $0.month < $1.month }
    }

    // Period comparison ------------------------------------------------------

    /// Compare the most recent calendar month with the one before it.
    static func monthOverMonth(drives: [DriveRecord], charges: [ChargeRecord], pricing: ChargePricing, now: Date = Date()) -> PeriodComparison? {
        let cal = calendar
        guard let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart),
              let nextMonthStart = cal.date(byAdding: .month, value: 1, to: thisMonthStart) else { return nil }

        func driveAgg(_ range: Range<Date>) -> (dist: Double, cons: Double, count: Int) {
            var dist = 0.0, consSum = 0.0, consDist = 0.0, count = 0
            for d in drives where range.contains(d.startDate) {
                dist += d.distanceKm; count += 1
                if let c = d.consumptionWhPerKm, c > 0, d.distanceKm > 0 { consSum += c * d.distanceKm; consDist += d.distanceKm }
            }
            return (dist, consDist > 0 ? consSum / consDist : 0, count)
        }
        func chargeAgg(_ range: Range<Date>) -> (energy: Double, cost: Double) {
            var energy = 0.0, cost = 0.0
            for c in charges where range.contains(c.startDate) {
                energy += c.energyAddedKwh
                cost += pricing.cost(for: c)
            }
            return (energy, cost)
        }

        let cur = thisMonthStart..<nextMonthStart
        let prev = lastMonthStart..<thisMonthStart
        let dCur = driveAgg(cur), dPrev = driveAgg(prev)
        let cCur = chargeAgg(cur), cPrev = chargeAgg(prev)
        // Only meaningful if there is at least some data either side.
        guard dCur.count + dPrev.count + Int(cCur.energy + cPrev.energy) > 0 else { return nil }
        return PeriodComparison(
            label: L("vs last month"),
            distanceKm: (dCur.dist, dPrev.dist),
            energyKwh: (cCur.energy, cPrev.energy),
            cost: (cCur.cost, cPrev.cost),
            consumptionWhPerKm: (dCur.cons, dPrev.cons),
            drives: (dCur.count, dPrev.count))
    }

    // Records ----------------------------------------------------------------

    static func superlatives(drives: [DriveRecord], charges: [ChargeRecord]) -> Superlatives {
        var s = Superlatives()
        s.longestDrive = drives.max { $0.distanceKm < $1.distanceKm }
        s.mostEfficientDrive = drives
            .filter { ($0.consumptionWhPerKm ?? 0) > 0 && $0.distanceKm >= 3 }
            .min { ($0.consumptionWhPerKm ?? .infinity) < ($1.consumptionWhPerKm ?? .infinity) }
        s.fastestDrive = drives.max { ($0.maxSpeedKmh ?? 0) < ($1.maxSpeedKmh ?? 0) }
        s.topSpeedKmh = drives.compactMap { $0.maxSpeedKmh }.max()
        s.bestRegenDrive = drives.filter { ($0.maxRegenKw ?? 0) > 0 }.max { ($0.maxRegenKw ?? 0) < ($1.maxRegenKw ?? 0) }
        s.maxRegenKw = drives.compactMap { $0.maxRegenKw }.max()
        s.biggestCharge = charges.max { $0.energyAddedKwh < $1.energyAddedKwh }
        s.longestCharge = charges.max { $0.durationMin < $1.durationMin }
        s.fastestCharge = charges.max { ($0.avgPowerKw ?? 0) < ($1.avgPowerKw ?? 0) }
        return s
    }

    // Cost -------------------------------------------------------------------

    static func cost(drives: [DriveRecord], charges: [ChargeRecord], pricing: ChargePricing, now: Date = Date()) -> CostSummary {
        var c = CostSummary()
        c.totalDistanceKm = drives.reduce(0) { $0 + $1.distanceKm }
        c.totalEnergyKwh = charges.reduce(0) { $0 + $1.energyAddedKwh }

        let recordedCost = charges.reduce(0.0) { $0 + ($1.cost ?? 0) }
        c.costIsEstimated = recordedCost <= 0.01
        // Sum each session's effective cost: recorded where present, priced estimate otherwise
        // (so sessions TeslaMate left without a cost still count, at their location's price).
        c.totalCost = charges.reduce(0) { $0 + pricing.cost(for: $1) }

        if c.totalDistanceKm > 0 { c.costPer100Km = c.totalCost / c.totalDistanceKm * 100 }

        // Average price/kWh from sessions that actually carry a cost.
        let priced = charges.filter { ($0.cost ?? 0) > 0 && $0.energyAddedKwh > 0 }
        if !priced.isEmpty {
            let energy = priced.reduce(0) { $0 + $1.energyAddedKwh }
            let cost = priced.reduce(0) { $0 + ($1.cost ?? 0) }
            if energy > 0 { c.avgPricePerKwh = cost / energy }
        } else if pricing.defaultPricePerKwh > 0 {
            c.avgPricePerKwh = pricing.defaultPricePerKwh
        }

        // Projection: spread the recorded cost over the days actually covered.
        if let earliest = charges.map(\.startDate).min(), c.totalCost > 0 {
            let days = max(1, now.timeIntervalSince(earliest) / 86_400)
            let perDay = c.totalCost / days
            c.monthlyProjection = perDay * 30.4
            c.annualProjection = perDay * 365
        }
        return c
    }

    // Usage patterns ---------------------------------------------------------

    static func weekdayUsage(_ drives: [DriveRecord]) -> [WeekdayUsage] {
        let cal = calendar
        var map: [Int: WeekdayUsage] = [:]
        for wd in 1...7 { map[wd] = WeekdayUsage(weekday: wd) }
        for d in drives {
            let wd = cal.component(.weekday, from: d.startDate)
            map[wd]?.driveCount += 1
            map[wd]?.distanceKm += d.distanceKm
        }
        // Order from the locale's first weekday (Monday across most of Europe) rather than
        // always Sunday, so the chart reads the way the user's calendar does.
        let first = cal.firstWeekday
        let order = (0..<7).map { ((first - 1 + $0) % 7) + 1 }
        return order.compactMap { map[$0] }
    }

    static func hourUsage(_ drives: [DriveRecord]) -> [HourUsage] {
        let cal = calendar
        var map: [Int: HourUsage] = [:]
        for h in 0..<24 { map[h] = HourUsage(hour: h) }
        for d in drives {
            let h = cal.component(.hour, from: d.startDate)
            map[h]?.driveCount += 1
        }
        return (0..<24).compactMap { map[$0] }
    }

    /// Distance per calendar day across the last `weeks` weeks (for a GitHub-style heatmap).
    static func calendarHeatmap(_ drives: [DriveRecord], weeks: Int = 18, now: Date = Date()) -> [CalendarDay] {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) else { return [] }
        var map: [Date: Double] = [:]
        for d in drives {
            let day = cal.startOfDay(for: d.startDate)
            guard day >= start else { continue }
            map[day, default: 0] += d.distanceKm
        }
        var days: [CalendarDay] = []
        var cursor = start
        while cursor <= today {
            days.append(CalendarDay(day: cursor, distanceKm: map[cursor] ?? 0))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    // Environmental impact ---------------------------------------------------

    /// CO₂ avoided vs an equivalent combustion car. ~2.31 kg CO₂ per litre of petrol burned.
    static func eco(drives: [DriveRecord], fuelLPer100km: Double) -> EcoImpact {
        var e = EcoImpact()
        e.distanceKm = drives.reduce(0) { $0 + $1.distanceKm }
        e.litersAvoided = e.distanceKm / 100 * max(0, fuelLPer100km)
        e.co2AvoidedKg = e.litersAvoided * 2.31
        e.treeYears = e.co2AvoidedKg / 21.0
        return e
    }

    // Temperature correlation ------------------------------------------------

    static func tempConsumption(_ drives: [DriveRecord]) -> [TempConsumptionPoint] {
        drives.enumerated().compactMap { idx, d in
            guard let t = d.outsideTempAvg, let c = d.consumptionWhPerKm, c > 0, d.distanceKm >= 1 else { return nil }
            return TempConsumptionPoint(index: idx, outsideTempC: t, consumptionWhPerKm: c, distanceKm: d.distanceKm)
        }
    }

    static func tempBins(_ points: [TempConsumptionPoint], width: Int = 5) -> [TempBin] {
        guard !points.isEmpty else { return [] }
        var buckets: [Int: (sum: Double, dist: Double, n: Int)] = [:]
        for p in points {
            let lower = Int((p.outsideTempC / Double(width)).rounded(.down)) * width
            var b = buckets[lower] ?? (0, 0, 0)
            b.sum += p.consumptionWhPerKm * p.distanceKm
            b.dist += p.distanceKm
            b.n += 1
            buckets[lower] = b
        }
        return buckets
            .map { TempBin(lowerC: $0.key, avgConsumptionWhPerKm: $0.value.dist > 0 ? $0.value.sum / $0.value.dist : 0, sampleCount: $0.value.n) }
            .sorted { $0.lowerC < $1.lowerC }
    }

    // Phantom / vampire drain ------------------------------------------------

    /// Estimate standby battery loss by looking at consecutive drives: when the car was
    /// parked between two drives and NOT charged in the gap, the range/SoC it lost while
    /// idle is vampire drain. Aggregated to a daily rate.
    static func phantomDrain(drives: [DriveRecord], charges: [ChargeRecord]) -> PhantomDrain? {
        let ordered = drives.sorted { $0.startDate < $1.startDate }
        var pctPerDay: [Double] = []
        var kmPerDay: [Double] = []
        var totalIdle = 0.0
        var samples = 0

        for i in 0..<max(0, ordered.count - 1) {
            let a = ordered[i], b = ordered[i + 1]
            let aEnd = a.endDate ?? a.startDate
            let idle = b.startDate.timeIntervalSince(aEnd)
            // Require a real, sane parked gap: 2h … 14d.
            guard idle >= 7_200, idle <= 1_209_600 else { continue }
            // Skip if a charge happened during the gap (it would mask the drain).
            let charged = charges.contains { $0.startDate > aEnd && $0.startDate < b.startDate }
            if charged { continue }
            let idleDays = idle / 86_400

            if let ab = a.endBattery, let bb = b.startBattery, ab - bb >= 0, ab - bb <= 30 {
                pctPerDay.append(Double(ab - bb) / idleDays)
                totalIdle += idleDays
                samples += 1
            }
            if let ar = a.endRangeKm, let br = b.startRangeKm, ar - br >= 0, ar - br <= 150 {
                kmPerDay.append((ar - br) / idleDays)
            }
        }
        guard samples > 0 else { return nil }
        let avgPct = pctPerDay.isEmpty ? 0 : pctPerDay.reduce(0, +) / Double(pctPerDay.count)
        let avgKm = kmPerDay.isEmpty ? 0 : kmPerDay.reduce(0, +) / Double(kmPerDay.count)
        return PhantomDrain(avgPercentPerDay: avgPct, avgRangeLossKmPerDay: avgKm, idleSamples: samples, totalIdleDays: totalIdle)
    }

    // Charging by location ---------------------------------------------------

    static func chargingLocations(_ charges: [ChargeRecord], pricing: ChargePricing) -> [ChargingLocation] {
        var map: [String: ChargingLocation] = [:]
        var powerAcc: [String: (sum: Double, n: Int)] = [:]
        for c in charges {
            let name = c.locationName
            var loc = map[name] ?? ChargingLocation(name: name)
            loc.sessions += 1
            loc.energyKwh += c.energyAddedKwh
            loc.cost += pricing.cost(for: c)
            loc.isFast = loc.isFast || c.isFastCharger
            map[name] = loc
            if let p = c.avgPowerKw, p > 0 {
                var pa = powerAcc[name] ?? (0, 0)
                pa.sum += p; pa.n += 1
                powerAcc[name] = pa
            }
        }
        for (name, pa) in powerAcc where pa.n > 0 {
            map[name]?.avgPowerKw = pa.sum / Double(pa.n)
        }
        return map.values.sorted { $0.energyKwh > $1.energyKwh }
    }
}

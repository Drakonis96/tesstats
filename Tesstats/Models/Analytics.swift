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
    var driveCount: Int = 0
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

// MARK: - State-of-charge timeline

/// One battery-level sample reconstructed from the recorded history. TeslaMate history has
/// no continuous SoC series, but every drive and charge carries its start/end level — chaining
/// those boundaries yields a faithful battery timeline (flat-ish gaps are parked periods).
struct SocSample: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable { case drive, charge }
    var id: Date { date }
    var date: Date
    var soc: Int
    var kind: Kind
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

// MARK: - Time-of-use tariff

/// One time-of-day price band (e.g. 00:00–08:00 at 0.08/kWh). Bands may wrap past
/// midnight (start > end, e.g. 22:00–06:00). Minutes are counted from midnight, 0…1439.
struct TariffPeriod: Codable, Equatable, Sendable, Identifiable, Hashable {
    var id = UUID()
    var startMinute: Int = 0
    var endMinute: Int = 480          // exclusive
    var pricePerKwh: Double = 0.10

    /// Whether a given minute-of-day falls inside this band, honoring midnight wrap.
    func contains(minuteOfDay m: Int) -> Bool {
        if startMinute == endMinute { return false }        // empty band
        if startMinute < endMinute { return m >= startMinute && m < endMinute }
        return m >= startMinute || m < endMinute            // wraps midnight
    }
}

/// A set of time-of-day price bands. Minutes not covered by any band cost the default price.
struct TimeOfUseTariff: Codable, Equatable, Sendable {
    var periods: [TariffPeriod]

    /// Price at one moment: the first band containing it, or the default.
    func price(at date: Date, defaultPrice: Double, calendar: Calendar = .current) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return periods.first { $0.contains(minuteOfDay: minute) }?.pricePerKwh ?? defaultPrice
    }

    /// Time-weighted average price across a session, sampling per minute. Assumes energy
    /// flows roughly uniformly over the session — a good approximation for AC charging,
    /// which is what time-of-use tariffs apply to.
    func averagePrice(for interval: DateInterval, defaultPrice: Double, calendar: Calendar = .current) -> Double {
        // Cap the walk at 7 days to bound the work on degenerate data.
        let minutes = min(Int(interval.duration / 60), 7 * 24 * 60)
        guard minutes >= 1 else { return price(at: interval.start, defaultPrice: defaultPrice, calendar: calendar) }
        var sum = 0.0
        for i in 0..<minutes {
            let t = interval.start.addingTimeInterval(Double(i) * 60)
            sum += price(at: t, defaultPrice: defaultPrice, calendar: calendar)
        }
        return sum / Double(minutes)
    }
}

// MARK: - Tariff plans

/// What a band is for, so a plan reads at a glance and the day bar can colour it.
enum TariffBandKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case valley, flat, peak
    var id: String { rawValue }
    var label: String {
        switch self {
        case .valley: L("Off-peak")
        case .flat: L("Standard")
        case .peak: L("Peak")
        }
    }
}

/// One band of a plan. Only `startMinute` is user-editable: `endMinute` is derived by
/// `TariffPlan.normalized()` so the bands always tile a full 24 h with no gap or overlap.
struct TariffBand: Codable, Equatable, Sendable, Identifiable, Hashable {
    var id = UUID()
    var kind: TariffBandKind = .flat
    var startMinute: Int = 0
    var endMinute: Int = 0            // derived; exclusive
    var buyPricePerKwh: Double = 0.10
    /// Price paid for energy exported back. `nil` means "same as buy".
    var sellPricePerKwh: Double?

    var effectiveSellPrice: Double { sellPricePerKwh ?? buyPricePerKwh }

    /// A single band that starts and ends at the same minute covers the whole day, which is
    /// what a one-band plan means.
    func contains(minuteOfDay m: Int) -> Bool {
        if startMinute == endMinute { return true }
        if startMinute < endMinute { return m >= startMinute && m < endMinute }
        return m >= startMinute || m < endMinute            // wraps midnight
    }

    var durationMinutes: Int {
        if startMinute == endMinute { return 1440 }
        return startMinute < endMinute ? endMinute - startMinute : 1440 - startMinute + endMinute
    }
}

/// A named set of price bands covering the whole day.
struct TariffPlan: Codable, Equatable, Sendable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var bands: [TariffBand] = []

    /// Sort by start time, drop duplicate starts, and close every band on the next one's start
    /// (the last wraps to the first) so the day is always exactly covered.
    func normalized() -> TariffPlan {
        var copy = self
        var seen = Set<Int>()
        let sorted = bands
            .map { band -> TariffBand in
                var b = band
                b.startMinute = ((b.startMinute % 1440) + 1440) % 1440
                return b
            }
            .sorted { $0.startMinute < $1.startMinute }
            .filter { seen.insert($0.startMinute).inserted }

        copy.bands = sorted.enumerated().map { index, band in
            var b = band
            b.endMinute = sorted.count == 1 ? band.startMinute : sorted[(index + 1) % sorted.count].startMinute
            return b
        }
        return copy
    }

    /// Midpoint of the longest band — adding a band there splits the biggest slot rather than
    /// landing on top of an existing boundary.
    func suggestedStartForNewBand() -> Int {
        let n = normalized()
        guard let longest = n.bands.max(by: { $0.durationMinutes < $1.durationMinutes }) else { return 0 }
        return (longest.startMinute + longest.durationMinutes / 2) % 1440
    }

    func band(at date: Date, calendar: Calendar = .current) -> TariffBand? {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return normalized().bands.first { $0.contains(minuteOfDay: minute) }
    }

    func buyPrice(at date: Date, defaultPrice: Double, calendar: Calendar = .current) -> Double {
        band(at: date, calendar: calendar)?.buyPricePerKwh ?? defaultPrice
    }

    /// Time-weighted average buy price across a session, sampled per minute. Assumes energy
    /// flows roughly uniformly, which is a good approximation for the AC charging that
    /// time-of-use tariffs apply to.
    func averageBuyPrice(for interval: DateInterval, defaultPrice: Double, calendar: Calendar = .current) -> Double {
        let minutes = min(Int(interval.duration / 60), 7 * 24 * 60)   // bounded on degenerate data
        guard minutes >= 1 else { return buyPrice(at: interval.start, defaultPrice: defaultPrice, calendar: calendar) }
        let n = normalized()
        var sum = 0.0
        for i in 0..<minutes {
            sum += n.buyPrice(at: interval.start.addingTimeInterval(Double(i) * 60),
                              defaultPrice: defaultPrice, calendar: calendar)
        }
        return sum / Double(minutes)
    }
}

// MARK: - Charge pricing

/// Resolves what a charge costs. Resolution order:
///   1. TeslaMate's recorded cost (when it carries a real value),
///   2. the location's custom price override,
///   3. the time-of-use tariff (time-weighted across the session), when enabled,
///   4. the global default price.
struct ChargePricing: Sendable, Equatable {
    var defaultPricePerKwh: Double
    var perLocation: [String: Double]
    /// A plan tiles the whole day, so every minute has a price.
    var plan: TariffPlan?
    /// Pre-plan band list. Bands may leave part of the day uncovered, and those minutes cost
    /// the default price — different semantics from a plan, so the two stay separate.
    var tariff: TimeOfUseTariff?

    init(defaultPricePerKwh: Double,
         perLocation: [String: Double] = [:],
         plan: TariffPlan? = nil,
         tariff: TimeOfUseTariff? = nil) {
        self.defaultPricePerKwh = defaultPricePerKwh
        self.perLocation = perLocation
        self.plan = plan
        self.tariff = tariff
    }

    /// Everything pricing needs, straight from the app configuration. A selected plan wins;
    /// otherwise a pre-plan band list keeps pricing exactly as it did before plans existed.
    init(config: ServerConfig) {
        let selected = config.tariffEnabled
            ? config.tariffPlans.first { $0.id.uuidString == config.activeTariffPlanID && !$0.bands.isEmpty }
            : nil
        self.init(defaultPricePerKwh: config.chargePricePerKwh,
                  perLocation: config.chargePricePerKwhByLocation,
                  plan: selected?.normalized(),
                  tariff: selected == nil && config.tariffEnabled && !config.tariffPeriods.isEmpty
                      ? TimeOfUseTariff(periods: config.tariffPeriods) : nil)
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
        if let override = perLocation[charge.locationName] {
            return charge.energyAddedKwh * override
        }
        if plan != nil || tariff != nil {
            let end = charge.endDate ?? charge.startDate.addingTimeInterval(Double(max(charge.durationMin, 1)) * 60)
            let interval = DateInterval(start: charge.startDate, end: max(end, charge.startDate.addingTimeInterval(60)))
            let price = plan?.averageBuyPrice(for: interval, defaultPrice: defaultPricePerKwh)
                ?? tariff?.averagePrice(for: interval, defaultPrice: defaultPricePerKwh)
                ?? defaultPricePerKwh
            return charge.energyAddedKwh * price
        }
        return charge.energyAddedKwh * defaultPricePerKwh
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

    /// Pivot monthly stats into calendar years for a year-over-year comparison.
    /// Returns the two most recent years that have any data, oldest first.
    static func yearOverYear(_ monthly: [MonthlyStat]) -> [(year: Int, months: [MonthlyStat])] {
        let cal = calendar
        let grouped = Dictionary(grouping: monthly) { cal.component(.year, from: $0.month) }
        return grouped.keys.sorted().suffix(2).map { (year: $0, months: (grouped[$0] ?? []).sorted { $0.month < $1.month }) }
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

    /// Distance and drive count per calendar day across the last `weeks` weeks
    /// (for a GitHub-style heatmap).
    static func calendarHeatmap(_ drives: [DriveRecord], weeks: Int = 18, now: Date = Date()) -> [CalendarDay] {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) else { return [] }
        var map: [Date: (km: Double, count: Int)] = [:]
        for d in drives {
            let day = cal.startOfDay(for: d.startDate)
            guard day >= start else { continue }
            var agg = map[day] ?? (0, 0)
            agg.km += d.distanceKm
            agg.count += 1
            map[day] = agg
        }
        var days: [CalendarDay] = []
        var cursor = start
        while cursor <= today {
            let agg = map[cursor]
            days.append(CalendarDay(day: cursor, distanceKm: agg?.km ?? 0, driveCount: agg?.count ?? 0))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    // State-of-charge timeline -------------------------------------------------

    /// Battery level over the last `days` days, reconstructed from drive and charge
    /// boundaries (see `SocSample`). Sorted chronologically; same-second duplicates keep
    /// the last value seen.
    static func socTimeline(drives: [DriveRecord], charges: [ChargeRecord], days: Int, now: Date = Date()) -> [SocSample] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return [] }
        var samples: [SocSample] = []

        for d in drives {
            if let soc = d.startBattery, d.startDate >= cutoff {
                samples.append(SocSample(date: d.startDate, soc: soc, kind: .drive))
            }
            if let soc = d.endBattery, let end = d.endDate, end >= cutoff, end <= now {
                samples.append(SocSample(date: end, soc: soc, kind: .drive))
            }
        }
        for c in charges {
            if let soc = c.startBattery, c.startDate >= cutoff {
                samples.append(SocSample(date: c.startDate, soc: soc, kind: .charge))
            }
            if let soc = c.endBattery, let end = c.endDate, end >= cutoff, end <= now {
                samples.append(SocSample(date: end, soc: soc, kind: .charge))
            }
        }

        samples.sort { $0.date < $1.date }
        // Collapse duplicate timestamps (a charge ending exactly when a drive starts).
        var result: [SocSample] = []
        for s in samples {
            if let last = result.last, abs(last.date.timeIntervalSince(s.date)) < 1 {
                result[result.count - 1] = s
            } else {
                result.append(s)
            }
        }
        return result
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
        // Sorted once so the "was it charged during this gap?" test below is a binary search
        // instead of a full scan per gap — that scan was O(drives × charges) and dominated
        // the whole Stats screen on multi-year histories.
        let chargeStarts = charges.map(\.startDate).sorted()
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
            if Self.containsDate(chargeStarts, after: aEnd, before: b.startDate) { continue }
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

    /// Is there any date in the ascending `sorted` strictly between `after` and `before`?
    /// Binary search for the first element greater than `after`, then one comparison.
    private static func containsDate(_ sorted: [Date], after: Date, before: Date) -> Bool {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] > after { high = mid } else { low = mid + 1 }
        }
        return low < sorted.count && sorted[low] < before
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

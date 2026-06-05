import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var range = StatsRange()
    @State private var refreshing = false
    @State private var exportSheet = false
    @State private var showSettings = false

    private var units: Units { Units(config: env.settings.config) }
    private var carID: Int { env.live.resolvedCarID ?? 1 }

    private var drives: [DriveRecord] { env.history.drives.filter { range.contains($0.startDate) } }
    private var charges: [ChargeRecord] { env.history.charges.filter { range.contains($0.startDate) } }
    private var pricePerKwh: Double { env.settings.config.chargePricePerKwh }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                content
            }
            .navigationTitle(L("Stats"))
            .toolbarTitleDisplayModeInline()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .leadingBar) { ConnectionStatusMenu() }
                ToolbarItem(placement: .principal) { ToolbarLogo() }
                #endif
                ToolbarItemGroup(placement: .trailingBar) {
                    Button { exportSheet = true } label: { Image(systemName: "square.and.arrow.up") }
                        .tint(Brand.crimson)
                    #if os(iOS)
                    SettingsGearButton(isPresented: $showSettings)
                    #endif
                    RefreshButton(isRefreshing: refreshing) { Task { await refresh() } }
                }
            }
            .sheet(isPresented: $exportSheet) {
                ExportSheet(drives: drives, charges: charges)
            }
            .settingsSheet(isPresented: $showSettings)
        }
        .task(id: carID) { await env.history.loadIfNeeded(carID: carID) }
    }

    @ViewBuilder
    private var content: some View {
        switch env.history.phase {
        case .idle, .loading:
            LoadingStateView(label: L("Crunching your stats…"))
        case .failed(let message):
            ErrorStateView(message: message) { Task { await refresh() } }
        case .empty(let message):
            EmptyStateView(systemImage: "chart.bar.xaxis", title: L("No stats yet"), message: message)
        case .loaded:
            if env.history.drives.isEmpty && env.history.charges.isEmpty {
                EmptyStateView(systemImage: "chart.bar.xaxis", title: L("No data to analyze yet"), message: nil)
            } else {
                loaded
            }
        }
    }

    private var loaded: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                RangeFilterBar(range: $range)
                    .padding(.top, 4)
                if drives.isEmpty && charges.isEmpty {
                    Text(L("No drives or charges in this period."))
                        .font(.subheadline).foregroundStyle(Brand.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                } else {
                    if let cmp = StatsEngine.monthOverMonth(drives: env.history.drives, charges: env.history.charges, pricePerKwh: pricePerKwh) {
                        ComparisonCard(comparison: cmp, units: units)
                    }
                    TrendsCard(monthly: monthly, units: units)
                    CostCard(cost: cost, units: units)
                    EcoCard(eco: eco, units: units)
                    if !tempPoints.isEmpty { TempConsumptionCard(points: tempPoints, bins: tempBins, units: units) }
                    UsageCard(weekdays: weekdays, hours: hours, units: units)
                    HeatmapCard(days: heatmap, units: units)
                    if let drain { PhantomDrainCard(drain: drain, units: units) }
                    if !chargingLocations.isEmpty { ChargingLocationsCard(locations: chargingLocations, units: units) }
                    RecordsCard(records: records, units: units)
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }

    // Derived analytics (recomputed when `range` or history changes).
    private var monthly: [MonthlyStat] { StatsEngine.monthly(drives: drives, charges: charges, pricePerKwh: pricePerKwh) }
    private var cost: CostSummary { StatsEngine.cost(drives: drives, charges: charges, pricePerKwh: pricePerKwh) }
    private var eco: EcoImpact { StatsEngine.eco(drives: drives, fuelLPer100km: env.settings.config.fuelConsumptionLPer100km) }
    private var tempPoints: [TempConsumptionPoint] { StatsEngine.tempConsumption(drives) }
    private var tempBins: [TempBin] { StatsEngine.tempBins(tempPoints) }
    private var weekdays: [WeekdayUsage] { StatsEngine.weekdayUsage(drives) }
    private var hours: [HourUsage] { StatsEngine.hourUsage(drives) }
    private var heatmap: [CalendarDay] { StatsEngine.calendarHeatmap(drives) }
    private var drain: PhantomDrain? { StatsEngine.phantomDrain(drives: drives, charges: charges) }
    private var chargingLocations: [ChargingLocation] { StatsEngine.chargingLocations(charges) }
    private var records: Superlatives { StatsEngine.superlatives(drives: drives, charges: charges) }

    private func refresh() async {
        refreshing = true
        await env.history.refresh(carID: carID)
        refreshing = false
    }
}

// MARK: - Comparison

private struct ComparisonCard: View {
    let comparison: PeriodComparison
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("This month \(comparison.label)"), systemImage: "calendar")
            TileGrid(columns: 2) {
                row(L("Distance"), units.distance(km: comparison.distanceKm.current, digits: 0), PeriodComparison.delta(comparison.distanceKm), invert: false)
                row(L("Energy"), units.energy(kwh: comparison.energyKwh.current, digits: 0), PeriodComparison.delta(comparison.energyKwh), invert: false)
                row(L("Cost"), units.money(comparison.cost.current), PeriodComparison.delta(comparison.cost), invert: true)
                row(L("Consumption"), units.consumption(whPerKm: comparison.consumptionWhPerKm.current > 0 ? comparison.consumptionWhPerKm.current : nil), PeriodComparison.delta(comparison.consumptionWhPerKm), invert: true)
            }
        }
        .card()
    }

    /// `invert` flips the good/bad coloring (lower cost & consumption is good).
    private func row(_ title: String, _ value: String, _ delta: Double?, invert: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Brand.textTertiary).lineLimit(1)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(Brand.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            if let delta, abs(delta) >= 0.5 {
                let good = invert ? delta < 0 : delta > 0
                HStack(spacing: 3) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right").font(.caption2.weight(.bold))
                    Text(String(format: "%+.0f%%", delta)).font(.caption2.weight(.semibold))
                }
                .foregroundStyle(good ? Brand.online : Brand.warning)
            } else {
                Text(L("≈ same")).font(.caption2).foregroundStyle(Brand.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Trends

private enum TrendMetric: String, CaseIterable, Identifiable {
    case distance, energy, cost, consumption
    var id: String { rawValue }
    var label: String {
        switch self {
        case .distance: L("Distance")
        case .energy: L("Energy")
        case .cost: L("Cost")
        case .consumption: L("Consumption")
        }
    }
}

private struct TrendsCard: View {
    let monthly: [MonthlyStat]
    let units: Units
    @State private var metric: TrendMetric = .distance

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Trends over time"), systemImage: "chart.bar.xaxis")
            Picker("", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if monthly.count < 2 {
                Text(L("Not enough history yet to show monthly trends."))
                    .font(.subheadline).foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(monthly) { m in
                    BarMark(x: .value("Month", m.month, unit: .month),
                            y: .value(metric.label, value(m)))
                        .foregroundStyle(Brand.crimson.gradient)
                        .cornerRadius(4)
                }
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel(format: .dateTime.month(.narrow)) } }
                .frame(height: 200)
                HStack {
                    Text(unitCaption).font(.caption2).foregroundStyle(Brand.textTertiary)
                    Spacer()
                    Text(totalCaption).font(.caption2.weight(.semibold)).foregroundStyle(Brand.textSecondary)
                }
            }
        }
        .card()
    }

    private func value(_ m: MonthlyStat) -> Double {
        switch metric {
        case .distance: units.distance == .imperial ? m.distanceKm / 1.609344 : m.distanceKm
        case .energy: m.energyChargedKwh
        case .cost: m.chargeCost
        case .consumption: m.avgConsumptionWhPerKm
        }
    }

    private var unitCaption: String {
        switch metric {
        case .distance: units.distanceUnit
        case .energy: "kWh"
        case .cost: units.currency
        case .consumption: units.distance == .imperial ? "Wh/mi" : "Wh/km"
        }
    }

    private var totalCaption: String {
        switch metric {
        case .distance: L("Total \(units.distance(km: monthly.reduce(0) { $0 + $1.distanceKm }, digits: 0))")
        case .energy: L("Total \(units.energy(kwh: monthly.reduce(0) { $0 + $1.energyChargedKwh }, digits: 0))")
        case .cost: L("Total \(units.money(monthly.reduce(0) { $0 + $1.chargeCost }))")
        case .consumption: ""
        }
    }
}

// MARK: - Cost

private struct CostCard: View {
    let cost: CostSummary
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(cost.costIsEstimated ? L("Cost (estimated)") : L("Cost"), systemImage: "creditcard")
            TileGrid(columns: 2) {
                StatTile(title: L("Total"), value: units.money(cost.totalCost), tint: Brand.crimson)
                if let per100 = cost.costPer100Km {
                    StatTile(title: L("Per 100 \(units.distanceUnit)"),
                             value: units.money(units.distance == .imperial ? per100 * 1.609344 : per100))
                }
                if let kwh = cost.avgPricePerKwh {
                    StatTile(title: L("Avg / kWh"), value: units.money(kwh))
                }
                if let monthly = cost.monthlyProjection {
                    StatTile(title: L("≈ Monthly"), value: units.money(monthly), systemImage: "calendar")
                }
                if let annual = cost.annualProjection {
                    StatTile(title: L("≈ Yearly"), value: units.money(annual), systemImage: "calendar")
                }
            }
            if cost.costIsEstimated {
                Text(L("Estimated from your €/kWh price — TeslaMate had no recorded cost."))
                    .font(.caption2).foregroundStyle(Brand.textTertiary)
            }
        }
        .card()
    }
}

// MARK: - Eco

private struct EcoCard: View {
    let eco: EcoImpact
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Environmental impact"), systemImage: "leaf.fill")
            TileGrid(columns: 3) {
                StatTile(title: L("CO₂ avoided"), value: co2, systemImage: "smoke", tint: Brand.online)
                StatTile(title: L("Petrol avoided"), value: String(format: "%.0f L", eco.litersAvoided), systemImage: "fuelpump")
                StatTile(title: L("Tree-years"), value: String(format: "%.0f", eco.treeYears), systemImage: "leaf.fill")
            }
            Text(L("Versus an equivalent combustion car over \(units.distance(km: eco.distanceKm, digits: 0))."))
                .font(.caption2).foregroundStyle(Brand.textTertiary)
        }
        .card()
    }

    private var co2: String {
        eco.co2AvoidedKg >= 1000
            ? String(format: "%.2f t", eco.co2AvoidedKg / 1000)
            : String(format: "%.0f kg", eco.co2AvoidedKg)
    }
}

// MARK: - Temperature vs consumption

private struct TempConsumptionCard: View {
    let points: [TempConsumptionPoint]
    let bins: [TempBin]
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Consumption vs temperature"), systemImage: "thermometer.snowflake")
            Chart {
                ForEach(points) { p in
                    PointMark(x: .value("Temp", tempX(p.outsideTempC)),
                              y: .value("Wh", consY(p.consumptionWhPerKm)))
                        .foregroundStyle(Brand.crimson.opacity(0.35))
                        .symbolSize(18)
                }
                ForEach(bins) { b in
                    LineMark(x: .value("Temp", tempX(Double(b.lowerC) + 2.5)),
                             y: .value("Wh", consY(b.avgConsumptionWhPerKm)))
                        .foregroundStyle(Brand.crimsonBright)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
            .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
            .frame(height: 200)
            Text(L("Each dot is a drive — colder weather usually pushes consumption up (x: \(tempUnit), y: \(consUnit))."))
                .font(.caption2).foregroundStyle(Brand.textTertiary)
        }
        .card()
    }

    private func tempX(_ c: Double) -> Double { units.temp == .fahrenheit ? c * 9 / 5 + 32 : c }
    private func consY(_ wh: Double) -> Double { units.distance == .imperial ? wh * 1.609344 : wh }
    private var tempUnit: String { units.temp == .fahrenheit ? "°F" : "°C" }
    private var consUnit: String { units.distance == .imperial ? "Wh/mi" : "Wh/km" }
}

// MARK: - Usage patterns

private struct UsageCard: View {
    let weekdays: [WeekdayUsage]
    let hours: [HourUsage]
    let units: Units

    private var weekdaySymbols: [String] { Calendar.current.shortWeekdaySymbols }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("When you drive"), systemImage: "clock.arrow.circlepath")
            Text(L("By weekday")).font(.caption).foregroundStyle(Brand.textTertiary)
            Chart(weekdays) { w in
                BarMark(x: .value("Day", weekdaySymbols[(w.weekday - 1) % 7]),
                        y: .value("Distance", units.distance == .imperial ? w.distanceKm / 1.609344 : w.distanceKm))
                    .foregroundStyle(Brand.crimson.gradient)
                    .cornerRadius(3)
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
            .frame(height: 130)

            Text(L("By hour of day")).font(.caption).foregroundStyle(Brand.textTertiary).padding(.top, 4)
            Chart(hours) { h in
                BarMark(x: .value("Hour", h.hour),
                        y: .value("Drives", h.driveCount))
                    .foregroundStyle(Brand.driving.gradient)
                    .cornerRadius(2)
            }
            .chartXScale(domain: 0...23)
            .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in AxisValueLabel { if let h = v.as(Int.self) { Text("\(h)h") } } } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
            .frame(height: 110)
        }
        .card()
    }
}

// MARK: - Calendar heatmap

private struct HeatmapCard: View {
    let days: [CalendarDay]
    let units: Units

    private var maxKm: Double { max(1, days.map(\.distanceKm).max() ?? 1) }
    private var weeks: [[CalendarDay]] { stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Activity"), systemImage: "calendar")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 3) {
                            ForEach(week) { day in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(color(for: day.distanceKm))
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 6) {
                Text(L("Less")).font(.caption2).foregroundStyle(Brand.textTertiary)
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Brand.crimson.opacity(0.15 + Double(i) * 0.2)).frame(width: 11, height: 11)
                }
                Text(L("More")).font(.caption2).foregroundStyle(Brand.textTertiary)
                Spacer()
            }
        }
        .card()
    }

    private func color(for km: Double) -> Color {
        guard km > 0 else { return Brand.elevatedSurface }
        let t = min(1, km / maxKm)
        return Brand.crimson.opacity(0.18 + t * 0.75)
    }
}

// MARK: - Phantom drain

private struct PhantomDrainCard: View {
    let drain: PhantomDrain
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Phantom drain"), systemImage: "moon.zzz")
            TileGrid(columns: 2) {
                StatTile(title: L("Per day"), value: String(format: "%.1f%%", drain.avgPercentPerDay), tint: Brand.warning)
                StatTile(title: L("Range / day"), value: units.distance(km: drain.avgRangeLossKmPerDay, digits: 1))
            }
            Text(L("Estimated standby loss while parked, from \(drain.idleSamples) idle periods. Real-world, not a defect."))
                .font(.caption2).foregroundStyle(Brand.textTertiary)
        }
        .card()
    }
}

// MARK: - Charging locations

private struct ChargingLocationsCard: View {
    let locations: [ChargingLocation]
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Where you charge"), systemImage: "mappin.circle")
            ForEach(locations.prefix(6)) { loc in
                HStack(spacing: 10) {
                    Image(systemName: loc.isFast ? "bolt.car.fill" : "house.fill")
                        .font(.subheadline).foregroundStyle(Brand.crimson).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.name).font(.subheadline.weight(.medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                        Text(L("\(loc.sessions) sessions · \(units.energy(kwh: loc.energyKwh, digits: 0))"))
                            .font(.caption2).foregroundStyle(Brand.textTertiary)
                    }
                    Spacer()
                    Text(loc.cost > 0 ? units.money(loc.cost) : units.power(kw: loc.avgPowerKw > 0 ? loc.avgPowerKw : nil))
                        .font(.caption.weight(.semibold)).foregroundStyle(Brand.textSecondary)
                }
                if loc.id != locations.prefix(6).last?.id { Divider().overlay(Brand.hairline) }
            }
        }
        .card()
    }
}

// MARK: - Records

private struct RecordsCard: View {
    let records: Superlatives
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Records"), systemImage: "trophy")
            if let d = records.longestDrive {
                record("road.lanes", L("Longest trip"), "\(units.distance(km: d.distanceKm)) · \(d.destinationName)")
            }
            if let d = records.mostEfficientDrive, let c = d.consumptionWhPerKm {
                record("leaf", L("Most efficient"), "\(units.consumption(whPerKm: c)) · \(d.destinationName)")
            }
            if let top = records.topSpeedKmh {
                record("speedometer", L("Top speed"), units.speed(kmh: top))
            }
            if let c = records.biggestCharge {
                record("bolt.fill", L("Biggest charge"), "\(units.energy(kwh: c.energyAddedKwh)) · \(c.locationName)")
            }
            if let c = records.fastestCharge, let p = c.avgPowerKw {
                record("bolt.car", L("Highest avg power"), "\(units.power(kw: p)) · \(c.locationName)")
            }
        }
        .card()
    }

    private func record(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(Brand.crimson).frame(width: 22)
            Text(title).font(.subheadline).foregroundStyle(Brand.textSecondary)
            Spacer(minLength: 10)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(Brand.textPrimary)
                .lineLimit(1).multilineTextAlignment(.trailing)
        }
    }
}

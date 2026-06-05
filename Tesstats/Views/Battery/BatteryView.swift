import SwiftUI
import Charts

struct BatteryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var timeRange: TimeRange = .all
    @State private var refreshing = false
    @State private var showSettings = false

    private var units: Units { Units(config: env.settings.config) }
    private var carID: Int { env.live.resolvedCarID ?? 1 }

    private var points: [BatteryHealthPoint] {
        env.history.battery.filter { timeRange.contains($0.date) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                content
            }
            .navigationTitle(L("Battery"))
            .toolbarTitleDisplayModeInline()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .leadingBar) { ConnectionStatusMenu() }
                ToolbarItem(placement: .principal) { ToolbarLogo() }
                #endif
                ToolbarItemGroup(placement: .trailingBar) {
                    #if os(iOS)
                    SettingsGearButton(isPresented: $showSettings)
                    #endif
                    RefreshButton(isRefreshing: refreshing) { Task { await refresh() } }
                }
            }
            .settingsSheet(isPresented: $showSettings)
        }
        .task(id: carID) { await env.history.loadIfNeeded(carID: carID) }
    }

    @ViewBuilder
    private var content: some View {
        switch env.history.phase {
        case .idle, .loading:
            LoadingStateView(label: L("Loading battery data…"))
        case .failed(let message):
            ErrorStateView(message: message) { Task { await refresh() } }
        case .empty(let message):
            EmptyStateView(systemImage: "battery.25percent", title: L("No battery data"), message: message)
        case .loaded:
            loaded
        }
    }

    private var loaded: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                if let state = env.live.currentState { liveHealthCard(state) }
                degradationCard
                efficiencyCard
                Text(L("Degradation is derived from charge data (rated range projected to 100% and measured kWh per SoC). An estimate, not a factory spec."))
                    .font(.caption2).foregroundStyle(Brand.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 4)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }

    private func liveHealthCard(_ state: VehicleState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Current"), systemImage: "heart.text.square")
            TileGrid(columns: 3) {
                StatTile(title: L("Charge"), value: "\(state.batteryLevel ?? 0)%", tint: Brand.crimson)
                StatTile(title: L("Usable"), value: state.usableBatteryLevel.map { "\($0)%" } ?? "—")
                StatTile(title: L("Range"), value: units.range(km: state.range(for: units.range)))
                if let cap = currentCapacity {
                    StatTile(title: L("Capacity now"), value: units.energy(kwh: cap, digits: 1), tint: Brand.crimson)
                }
                if let eff = env.history.carInfo?.efficiencyKwhPerKm, eff > 0 {
                    StatTile(title: L("Rated eff."), value: "\(Int(eff * 1000)) Wh/km")
                }
                StatTile(title: L("Health"),
                         value: state.healthy == true ? L("OK") : (state.healthy == false ? L("Check") : "—"),
                         tint: state.healthy == false ? Brand.danger : Brand.online)
            }
        }
        .card()
    }

    private var currentCapacity: Double? { env.history.battery.last?.usableCapacityKwh }
    private var originalCapacity: Double? { env.history.battery.first?.usableCapacityKwh }

    private var degradationPoints: [(date: Date, value: Double)] {
        points.map { point in
            let value = units.distance == .imperial ? point.maxRangeKm / 1.609344 : point.maxRangeKm
            return (point.date, value)
        }
    }

    private var degradationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(L("Degradation"), systemImage: "chart.line.downtrend.xyaxis")
            }
            SegmentedFilter(selection: $timeRange)

            if degradationPoints.count < 2 {
                Text(L("Not enough charge history yet to plot a degradation curve."))
                    .font(.subheadline).foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(spacing: 16) {
                    statBlock(L("Max range now"), units.range(km: env.history.battery.last?.maxRangeKm))
                    if let lost = degradationSummary {
                        statBlock(L("Lost"), String(format: "%.1f%%", lost))
                    }
                    if let cap = currentCapacity {
                        statBlock(L("Capacity"), units.energy(kwh: cap, digits: 1))
                    }
                }
                Chart(degradationPoints, id: \.date) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Range", point.value))
                        .foregroundStyle(LinearGradient(colors: [Brand.crimson.opacity(0.35), .clear],
                                                         startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.date), y: .value("Range", point.value))
                        .foregroundStyle(Brand.crimson)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.date), y: .value("Range", point.value))
                        .foregroundStyle(Brand.crimson)
                        .symbolSize(16)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
                .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 200)
            }
        }
        .card()
    }

    private var degradationSummary: Double? {
        guard let first = env.history.battery.first?.maxRangeKm,
              let last = env.history.battery.last?.maxRangeKm,
              first > 0 else { return nil }
        return max(0, (1 - last / first) * 100)
    }

    private var totalChargedKwh: Double { env.history.charges.reduce(0) { $0 + $1.energyAddedKwh } }
    private var chargeCycles: Double? {
        guard let cap = currentCapacity ?? originalCapacity, cap > 0, totalChargedKwh > 0 else { return nil }
        return totalChargedKwh / cap
    }

    private var efficiencyCard: some View {
        let eff = env.history.efficiency
        let info = env.history.carInfo
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Efficiency & totals"), systemImage: "leaf")
            TileGrid(columns: 3) {
                ConsumptionStat(title: L("Avg consumption"), whPerKm: eff.avgWhPerKm > 0 ? eff.avgWhPerKm : nil, units: units)
                StatTile(title: L("Distance"), value: units.distance(km: eff.totalDistanceKm, digits: 0))
                StatTile(title: L("Top speed"), value: units.speed(kmh: eff.maxSpeedKmh > 0 ? eff.maxSpeedKmh : nil))
                StatTile(title: L("Charge cycles"),
                         value: chargeCycles.map { String(format: "%.0f", $0) } ?? "—",
                         systemImage: "arrow.triangle.2.circlepath", tint: Brand.crimson)
                StatTile(title: L("Total charged"), value: units.energy(kwh: totalChargedKwh, digits: 0))
                if let orig = originalCapacity, let now = currentCapacity, orig > 0 {
                    StatTile(title: L("Capacity loss"), value: String(format: "%.1f%%", max(0, (1 - now / orig) * 100)))
                }
                StatTile(title: L("Total drives"), value: info?.totalDrives.map(String.init) ?? "\(eff.totalDrives)")
                if let charges = info?.totalCharges {
                    StatTile(title: L("Total charges"), value: "\(charges)")
                }
                if let updates = info?.totalUpdates {
                    StatTile(title: L("SW updates"), value: "\(updates)")
                }
            }
        }
        .card()
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Brand.textTertiary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(Brand.crimson)
        }
    }

    private func refresh() async {
        refreshing = true
        await env.history.refresh(carID: carID)
        refreshing = false
    }
}

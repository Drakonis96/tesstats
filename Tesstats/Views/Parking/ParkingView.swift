import SwiftUI
import Charts

struct ParkingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var range = StatsRange(preset: .month)
    @State private var refreshing = false
    @State private var showSettings = false

    private var units: Units { Units(config: env.settings.config) }
    private var carID: Int { env.live.resolvedCarID ?? 1 }
    private var allSessions: [ParkingSession] {
        ParkingSessionEngine.derive(
            drives: env.history.drives,
            charges: env.history.charges,
            currentState: env.live.currentState,
            pricePerKwh: env.settings.config.chargePricePerKwh,
            efficiencyKwhPerKm: env.history.carInfo?.efficiencyKwhPerKm
        )
    }
    private var sessions: [ParkingSession] { allSessions.filter { range.contains($0.startDate) } }
    private var groups: [DailyHistoryGroup<ParkingSession>] {
        DailyHistoryGrouper.group(sessions, date: \.startDate) { day in
            if Calendar.current.isDateInToday(day) { return L("Today") }
            if Calendar.current.isDateInYesterday(day) { return L("Yesterday") }
            return DateFormatter.localizedString(from: day, dateStyle: .medium, timeStyle: .none)
        } detail: { bucket in
            let energy = bucket.reduce(0) { $0 + $1.energyLostKwh }
            return L("\(bucket.count) idles · -\(String(format: "%.1f", energy)) kWh")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                content
            }
            .navigationTitle(L("Parking"))
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
            .navigationDestination(for: ParkingSession.self) { session in
                ParkingDetailView(session: session, units: units)
            }
            .settingsSheet(isPresented: $showSettings)
        }
        .task(id: carID) { await env.history.loadIfNeeded(carID: carID) }
    }

    @ViewBuilder
    private var content: some View {
        switch env.history.phase {
        case .idle, .loading:
            LoadingStateView(label: L("Deriving parking sessions…"))
        case .failed(let message):
            ErrorStateView(message: message) { Task { await refresh() } }
        case .empty(let message):
            EmptyStateView(systemImage: "parkingsign", title: L("No parking history"), message: message)
        case .loaded:
            loaded
        }
    }

    private var loaded: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                RangeFilterBar(range: $range)
                    .padding(.top, 4)
                HistoryMapHeader(
                    title: L("Parking"),
                    subtitle: L("Last \(range.summaryLabel) · \(sessions.count) idles · \(uniquePlaces) places"),
                    metric: energyMetric,
                    content: .parking(sessions)
                )
                summaryCard
                if let live = sessions.first(where: \.isLive) {
                    NavigationLink(value: live) { liveCard(live) }.buttonStyle(.plain)
                }
                ForEach(groups) { group in
                    HistoryDayHeader(title: group.title, detail: group.detail)
                    ForEach(group.items) { session in
                        NavigationLink(value: session) {
                            ParkingRow(session: session, units: units)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if sessions.isEmpty {
                    EmptyStateView(systemImage: "parkingsign", title: L("No parking sessions in this period"), message: nil)
                        .frame(height: 260)
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .refreshable { await refresh() }
        .scrollContentBackground(.hidden)
    }

    private var summaryCard: some View {
        let minutes = sessions.reduce(0) { $0 + $1.durationMinutes }
        let energy = sessions.reduce(0) { $0 + $1.energyLostKwh }
        let cost = sessions.reduce(0) { $0 + $1.cost }
        let rangeLost = sessions.reduce(0) { $0 + $1.rangeLostKm }
        return TileGrid(columns: 4) {
            StatTile(title: L("Time"), value: units.duration(minutes: minutes), systemImage: "clock", tint: Brand.driving)
            StatTile(title: L("Energy"), value: "-\(units.energy(kwh: energy, digits: 1))", systemImage: "bolt.fill", tint: Brand.warning)
            StatTile(title: L("Range"), value: "-\(units.distance(km: rangeLost, digits: 1))", systemImage: "road.lanes")
            StatTile(title: L("Cost"), value: units.money(cost), systemImage: "creditcard")
        }
        .card()
    }

    private func liveCard(_ session: ParkingSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Chip(text: L("Live now"), systemImage: "circle.fill", color: Brand.online)
                Text(session.locationName).font(.title3.weight(.bold)).foregroundStyle(Brand.textPrimary)
                Text(session.startBattery.map { "\($0)%" } ?? "—")
                    .font(.subheadline).foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            Text(units.duration(minutes: session.durationMinutes))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Brand.textPrimary)
            Image(systemName: "chevron.right").foregroundStyle(Brand.textTertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.online.opacity(0.16), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(Brand.online.opacity(0.45), lineWidth: 1))
    }

    private var uniquePlaces: Int { Set(sessions.map(\.locationName)).count }
    private var energyMetric: String { "-\(String(format: "%.1f", sessions.reduce(0) { $0 + $1.energyLostKwh })) kWh" }

    private func refresh() async {
        refreshing = true
        await env.history.refresh(carID: carID)
        refreshing = false
    }
}

struct HistoryDayHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(Brand.textPrimary)
            Spacer()
            Text(detail).font(.subheadline.weight(.medium)).foregroundStyle(Brand.textTertiary)
        }
        .padding(.top, 8)
    }
}

private struct ParkingRow: View {
    let session: ParkingSession
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.locationName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Text(units.duration(minutes: session.durationMinutes))
                    .font(.title.weight(.bold))
                    .foregroundStyle(Brand.textPrimary)
                ScoreRing(value: min(1, (session.whPerHour ?? 0) / 250), color: whColor)
            }
            Divider().overlay(Brand.hairline)
            HStack(spacing: 12) {
                metric("bolt.fill", "-\(units.energy(kwh: session.energyLostKwh, digits: 1))", Brand.warning)
                metric("creditcard", units.money(session.cost), Brand.warning)
                metric("road.lanes", "-\(units.distance(km: session.rangeLostKm, digits: 1))", Brand.textSecondary)
                metric("moon.zzz", whRate, Brand.textSecondary)
            }
        }
        .card()
    }

    private func metric(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.caption.weight(.medium)).foregroundStyle(color)
        }
    }

    private var whRate: String {
        session.whPerHour.map { "\(Int($0)) Wh/h" } ?? "—"
    }

    private var whColor: Color {
        guard let wh = session.whPerHour else { return Brand.textTertiary }
        return wh > 180 ? Brand.warning : Brand.driving
    }

    private var timeRange: String {
        let start = DateFormatter.localizedString(from: session.startDate, dateStyle: .none, timeStyle: .short)
        guard let end = session.endDate else { return "\(start) → \(L("now"))" }
        return "\(start) → \(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))"
    }
}

private struct ParkingDetailView: View {
    let session: ParkingSession
    let units: Units

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    header
                    metricGrid
                    chartCard
                    details
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
            }
        }
        .navigationTitle(L("Parking"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                Text(hoursPart).font(.system(size: 62, weight: .bold, design: .rounded))
                Text(minutesPart).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(Brand.textSecondary)
                Spacer()
                ScoreRing(value: min(1, (session.whPerHour ?? 0) / 250), color: Brand.driving)
            }
            Text(session.locationName).font(.title.weight(.bold)).foregroundStyle(Brand.textPrimary)
            Text(dateLine).font(.caption.weight(.semibold)).foregroundStyle(Brand.textTertiary).textCase(.uppercase)
        }
        .card()
    }

    private var metricGrid: some View {
        TileGrid(columns: 3) {
            StatTile(title: L("Energy used"), value: units.energy(kwh: session.energyLostKwh, digits: 1), systemImage: "bolt.fill", tint: Brand.driving)
            StatTile(title: L("Range lost"), value: units.distance(km: session.rangeLostKm, digits: 1), systemImage: "road.lanes", tint: Brand.driving)
            StatTile(title: L("Rate"), value: session.whPerHour.map { "\(Int($0)) Wh/h" } ?? "—", systemImage: "drop.fill", tint: Brand.driving)
            StatTile(title: L("Parked cost"), value: units.money(session.cost), systemImage: "creditcard", tint: Brand.warning)
            StatTile(title: L("Start"), value: session.startBattery.map { "\($0)%" } ?? "—")
            StatTile(title: L("End"), value: session.endBattery.map { "\($0)%" } ?? "—")
        }
        .card()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(L("Battery level"), systemImage: "battery.50percent", accent: Brand.driving)
                FullScreenChartButton(title: L("Battery level")) { batteryChart.frame(height: 320) }
            }
            batteryChart.frame(height: 170)
        }
        .card()
    }

    private var batteryChart: some View {
        let points = chartPoints
        return Chart(points, id: \.0) { p in
            AreaMark(x: .value("Time", p.0), y: .value("Battery", p.1))
                .foregroundStyle(Brand.driving.opacity(0.24))
            LineMark(x: .value("Time", p.0), y: .value("Battery", p.1))
                .foregroundStyle(Brand.driving)
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
    }

    private var details: some View {
        VStack(spacing: 12) {
            SectionHeader(L("Details"), systemImage: "list.bullet")
            KeyValueRow(label: L("Started"), value: units.shortDateTime(session.startDate))
            KeyValueRow(label: L("Ended"), value: session.endDate.map(units.shortDateTime) ?? L("Now"))
            KeyValueRow(label: L("Span"), value: units.duration(minutes: session.durationMinutes))
            if let delta = session.socDelta {
                KeyValueRow(label: L("SoC change"), value: "\(delta)%", valueColor: delta < 0 ? Brand.driving : Brand.textPrimary)
            }
        }
        .card()
    }

    private var chartPoints: [(Date, Double)] {
        let start = Double(session.startBattery ?? session.endBattery ?? 0)
        let end = Double(session.endBattery ?? session.startBattery ?? 0)
        return [(session.startDate, start), (session.endDate ?? Date(), end)]
    }

    private var hoursPart: String { "\(session.durationMinutes / 60)h" }
    private var minutesPart: String { " \(session.durationMinutes % 60)m" }
    private var dateLine: String {
        let start = units.shortDateTime(session.startDate)
        let end = session.endDate.map(units.shortDateTime) ?? L("Now")
        return "\(start) → \(end)"
    }
}

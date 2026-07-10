import SwiftUI

struct TripsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var search = ""
    @State private var range = StatsRange()
    @State private var visibleCount = 25
    @State private var refreshing = false
    @State private var showExport = false
    @State private var showSettings = false

    private let pageSize = 25
    private var units: Units { Units(config: env.settings.config) }
    private var carID: Int { env.live.resolvedCarID ?? 1 }

    private var filtered: [DriveRecord] {
        env.history.drives.filter { d in
            range.contains(d.startDate) &&
            (search.isEmpty
                || d.originName.localizedCaseInsensitiveContains(search)
                || d.destinationName.localizedCaseInsensitiveContains(search))
        }
    }
    private var visibleFiltered: [DriveRecord] { Array(filtered.prefix(visibleCount)) }
    private var groups: [DailyHistoryGroup<DriveRecord>] {
        DailyHistoryGrouper.group(visibleFiltered, date: \.startDate) { day in
            if Calendar.current.isDateInToday(day) { return L("Today") }
            if Calendar.current.isDateInYesterday(day) { return L("Yesterday") }
            return DateFormatter.localizedString(from: day, dateStyle: .medium, timeStyle: .none)
        } detail: { bucket in
            L("\(bucket.count) drives · \(units.distance(km: bucket.reduce(0) { $0 + $1.distanceKm }, digits: 1))")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                content
            }
            .navigationTitle(L("Trips"))
            .toolbarTitleDisplayModeInline()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .leadingBar) { ConnectionStatusMenu() }
                ToolbarItem(placement: .principal) { ToolbarLogo() }
                #endif
                ToolbarItemGroup(placement: .trailingBar) {
                    if env.history.usingCache {
                        Chip(text: L("Cached"), systemImage: "internaldrive", color: Brand.asleep)
                    }
                    if !filtered.isEmpty {
                        Button { showExport = true } label: { Image(systemName: "square.and.arrow.up") }
                            .tint(Brand.crimson)
                    }
                    #if os(iOS)
                    SettingsGearButton(isPresented: $showSettings)
                    #endif
                    RefreshButton(isRefreshing: refreshing) { Task { await refresh() } }
                }
            }
            .navigationDestination(for: DriveRecord.self) { drive in
                TripDetailView(drive: drive, units: units)
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(drives: filtered, charges: [])
            }
            .settingsSheet(isPresented: $showSettings)
        }
        .task(id: carID) { await env.history.loadIfNeeded(carID: carID) }
        .onChange(of: search) { _, _ in visibleCount = pageSize }
        .onChange(of: range) { _, _ in visibleCount = pageSize }
    }

    @ViewBuilder
    private var content: some View {
        switch env.history.phase {
        case .idle, .loading:
            LoadingStateView(label: L("Loading trips…"))
        case .failed(let message):
            ErrorStateView(message: message) { Task { await refresh() } }
        case .empty(let message):
            EmptyStateView(systemImage: "map", title: L("No trips"), message: message)
        case .loaded:
            if env.history.drives.isEmpty {
                EmptyStateView(systemImage: "map", title: L("No drives recorded yet"), message: nil)
            } else {
                list
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            SearchField(placeholder: L("Search origin or destination"), text: $search)
            RangeFilterBar(range: $range)
            HStack {
                Text(L("\(filtered.count) trips · \(units.distance(km: filtered.reduce(0) { $0 + $1.distanceKm }, digits: 0))"))
                    .font(.caption).foregroundStyle(Brand.textTertiary)
                Spacer()
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 6)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                filterBar
                HistoryMapHeader(
                    title: L("Trips"),
                    subtitle: "\(range.summaryLabel) · \(filtered.count) \(L("drives"))",
                    metric: units.distance(km: filtered.reduce(0) { $0 + $1.distanceKm }, digits: 0),
                    content: .drives(filtered)
                )
                tripSummaryCard
                LazyVStack(spacing: 10) {
                    ForEach(groups) { group in
                        HistoryDayHeader(title: group.title, detail: group.detail)
                        ForEach(group.items) { drive in
                            NavigationLink(value: drive) {
                                DriveRow(drive: drive, units: units, cost: tripCost(drive))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if filtered.count > visibleCount {
                        LoadMoreButton(remaining: filtered.count - visibleCount) {
                            withAnimation { visibleCount += pageSize }
                        }
                    }
                    if filtered.isEmpty {
                        Text(L("No trips match your filters."))
                            .font(.subheadline).foregroundStyle(Brand.textSecondary)
                            .padding(.top, 40)
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 8)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }

    private func refresh() async {
        refreshing = true
        await env.history.refresh(carID: carID)
        refreshing = false
    }

    private var tripSummaryCard: some View {
        let distance = filtered.reduce(0) { $0 + $1.distanceKm }
        let energy = filtered.reduce(0) { $0 + TripCostEngine.energyKwh(for: $1) }
        let efficiency = distance > 0 ? energy * 1000 / distance : nil
        return HStack(spacing: 14) {
            StatTile(title: L("Energy"), value: units.energy(kwh: energy, digits: 1), systemImage: "bolt.fill", tint: Brand.online)
            StatTile(title: L("Efficiency"), value: efficiency.map { "\(Int($0)) Wh/km" } ?? "—", systemImage: "leaf.fill", tint: Brand.driving)
            StatTile(title: L("Trips"), value: "\(filtered.count)", systemImage: "road.lanes")
        }
        .card()
    }

    private func tripCost(_ drive: DriveRecord) -> TripCost? {
        TripCostEngine.cost(for: drive,
                            pricePerKwh: env.settings.config.chargePricePerKwh,
                            fuelPricePerLiter: env.settings.config.fuelPricePerLiter,
                            fuelConsumptionLPer100km: env.settings.config.fuelConsumptionLPer100km)
    }
}

struct DriveRow: View {
    let drive: DriveRecord
    let units: Units
    var cost: TripCost?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(drive.originName, systemImage: "circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.online)
                            .lineLimit(1)
                        Label(drive.destinationName, systemImage: "circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.danger)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(units.distance(km: drive.distanceKm))
                            .font(.title.weight(.bold))
                            .foregroundStyle(Brand.textPrimary)
                        Text(timeRange)
                            .font(.caption)
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                HStack(spacing: 12) {
                    metric("clock", units.duration(minutes: drive.durationMin), Brand.textSecondary)
                    metric("leaf.fill", units.consumption(whPerKm: drive.consumptionWhPerKm), Brand.driving)
                    if let cost {
                        metric("creditcard", units.money(cost.electricCost), Brand.warning)
                    }
                    Spacer()
                    if drive.path.count >= 2 {
                        ScoreRing(value: driveScore, color: Brand.driving, caption: L("Efficiency"))
                    }
                }
            }
            if drive.path.count >= 2 {
                TinyRoutePreview(path: drive.path)
                    .frame(width: 95)
                    .opacity(0.75)
            }
        }
        .card(padding: 14)
    }

    private var driveScore: Double {
        guard let wh = drive.consumptionWhPerKm else { return 0.75 }
        return max(0.2, min(1, 1 - max(0, wh - 120) / 180))
    }

    private var timeRange: String {
        let start = DateFormatter.localizedString(from: drive.startDate, dateStyle: .none, timeStyle: .short)
        guard let end = drive.endDate else { return start }
        return "\(start) → \(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))"
    }

    private func metric(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(value).font(.caption).foregroundStyle(color)
        }
    }
}

import SwiftUI

struct ChargesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var search = ""
    @State private var typeFilter: ChargeTypeFilter = .all
    @State private var range = StatsRange()
    @State private var visibleCount = 25
    @State private var refreshing = false
    @State private var showExport = false
    @State private var showSettings = false

    private let pageSize = 25
    private var units: Units { Units(config: env.settings.config) }
    private var carID: Int { env.live.resolvedCarID ?? 1 }

    private var filtered: [ChargeRecord] {
        env.history.charges.filter { c in
            typeFilter.matches(c) && range.contains(c.startDate) &&
            (search.isEmpty || c.locationName.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                content
            }
            .navigationTitle(L("Charging"))
            .toolbarTitleDisplayModeInline()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .leadingBar) { ConnectionStatusMenu() }
                ToolbarItem(placement: .principal) { ToolbarLogo() }
                #endif
                ToolbarItemGroup(placement: .trailingBar) {
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
            .navigationDestination(for: ChargeRecord.self) { charge in
                ChargeDetailView(charge: charge, units: units)
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(drives: [], charges: filtered)
            }
            .settingsSheet(isPresented: $showSettings)
        }
        .task(id: carID) { await env.history.loadIfNeeded(carID: carID) }
        .onChange(of: search) { _, _ in visibleCount = pageSize }
        .onChange(of: typeFilter) { _, _ in visibleCount = pageSize }
        .onChange(of: range) { _, _ in visibleCount = pageSize }
    }

    @ViewBuilder
    private var content: some View {
        switch env.history.phase {
        case .idle, .loading:
            LoadingStateView(label: L("Loading charges…"))
        case .failed(let message):
            ErrorStateView(message: message) { Task { await refresh() } }
        case .empty(let message):
            EmptyStateView(systemImage: "bolt.slash", title: L("No charges"), message: message)
        case .loaded:
            if env.history.charges.isEmpty {
                EmptyStateView(systemImage: "bolt.slash", title: L("No charging sessions yet"), message: nil)
            } else {
                VStack(spacing: 10) {
                    filterBar
                    list
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            SearchField(placeholder: L("Search location"), text: $search)
            SegmentedFilter(selection: $typeFilter)
            RangeFilterBar(range: $range)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 6)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                ChargeAggregatesCard(aggregates: ChargeAggregates.from(filtered),
                                     electricityCost: electricityCost,
                                     costIsEstimated: costIsEstimated,
                                     fuelComparison: fuelComparison, units: units)
                LazyVStack(spacing: 10) {
                    ForEach(filtered.prefix(visibleCount)) { charge in
                        NavigationLink(value: charge) {
                            ChargeRow(charge: charge, units: units)
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.count > visibleCount {
                        LoadMoreButton(remaining: filtered.count - visibleCount) {
                            withAnimation { visibleCount += pageSize }
                        }
                    }
                    if filtered.isEmpty {
                        Text(L("No charges match your filters."))
                            .font(.subheadline).foregroundStyle(Brand.textSecondary).padding(.top, 30)
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 8)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }

    private var electricityCost: Double {
        let agg = ChargeAggregates.from(filtered)
        // Prefer TeslaMate's recorded cost; otherwise estimate from the configured €/kWh.
        return agg.totalCost > 0.01 ? agg.totalCost : agg.totalEnergyKwh * env.settings.config.chargePricePerKwh
    }

    private var costIsEstimated: Bool {
        ChargeAggregates.from(filtered).totalCost <= 0.01
    }

    private var fuelComparison: (evCost: Double, fuelCost: Double)? {
        let agg = ChargeAggregates.from(filtered)
        let eff = env.history.efficiency.avgWhPerKm
        guard eff > 0, agg.totalEnergyKwh > 0 else { return nil }
        // Distance those kWh would have covered, then the petrol cost for that distance.
        let km = (agg.totalEnergyKwh * 1000) / eff
        let liters = km / 100 * env.settings.config.fuelConsumptionLPer100km
        let fuelCost = liters * env.settings.config.fuelPricePerLiter
        return (electricityCost, fuelCost)
    }

    private func refresh() async {
        refreshing = true
        await env.history.refresh(carID: carID)
        refreshing = false
    }
}

struct ChargeAggregatesCard: View {
    let aggregates: ChargeAggregates
    var electricityCost: Double = 0
    var costIsEstimated: Bool = false
    let fuelComparison: (evCost: Double, fuelCost: Double)?
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Totals"), systemImage: "sum")
            TileGrid(columns: 2) {
                StatTile(title: L("Energy"), value: units.energy(kwh: aggregates.totalEnergyKwh, digits: 0), systemImage: "bolt.fill", tint: Brand.crimson)
                StatTile(title: costIsEstimated ? L("Cost (est.)") : L("Cost"),
                         value: units.money(electricityCost), systemImage: "creditcard")
                StatTile(title: L("Sessions"), value: "\(aggregates.sessionCount)", systemImage: "number")
                StatTile(title: L("AC / DC"),
                         value: "\(Int(aggregates.homeEnergyKwh)) / \(Int(aggregates.publicEnergyKwh)) kWh",
                         systemImage: "bolt.batteryblock")
            }
            if let cmp = fuelComparison {
                Divider().overlay(Brand.hairline)
                let saved = cmp.fuelCost - cmp.evCost
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L("Electricity"), systemImage: "bolt").font(.caption).foregroundStyle(Brand.textSecondary)
                        Spacer()
                        Text(units.money(cmp.evCost)).font(.caption.weight(.medium)).foregroundStyle(Brand.textPrimary)
                    }
                    HStack {
                        Label(L("Equivalent petrol"), systemImage: "fuelpump").font(.caption).foregroundStyle(Brand.textSecondary)
                        Spacer()
                        Text(units.money(cmp.fuelCost)).font(.caption.weight(.medium)).foregroundStyle(Brand.textPrimary)
                    }
                    HStack {
                        Text(saved >= 0 ? L("You saved") : L("Extra cost"))
                            .font(.caption.weight(.semibold)).foregroundStyle(saved >= 0 ? Brand.online : Brand.warning)
                        Spacer()
                        Text(units.money(abs(saved)))
                            .font(.caption.weight(.bold)).foregroundStyle(saved >= 0 ? Brand.online : Brand.warning)
                    }
                }
            }
        }
        .card()
    }
}

struct ChargeRow: View {
    let charge: ChargeRecord
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: charge.isFastCharger ? "bolt.car" : "house")
                    .font(.subheadline).foregroundStyle(Brand.crimson)
                Text(charge.locationName).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Spacer()
                Text(units.relative(charge.startDate)).font(.caption2).foregroundStyle(Brand.textTertiary)
            }
            HStack(spacing: 14) {
                metric("bolt.fill", units.energy(kwh: charge.energyAddedKwh))
                metric("battery.50percent", "\(charge.startBattery.map { "\($0)" } ?? "—")→\(charge.endBattery.map { "\($0)%" } ?? "—")")
                metric("creditcard", units.money(charge.cost))
                Spacer()
                if charge.isFastCharger { Chip(text: "DC", color: Brand.crimson) }
            }
        }
        .card(padding: 14)
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Brand.textTertiary)
            Text(value).font(.caption).foregroundStyle(Brand.textSecondary)
        }
    }
}

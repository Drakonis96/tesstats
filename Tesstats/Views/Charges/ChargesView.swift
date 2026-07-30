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
    @State private var editingPrice: ChargeRecord?
    @State private var priceText = ""

    private let pageSize = 25
    private var units: Units { Units(config: env.settings.config) }
    private var carID: Int { env.live.resolvedCarID ?? 1 }

    private var filtered: [ChargeRecord] {
        env.history.charges.filter { c in
            typeFilter.matches(c) && range.contains(c.startDate) &&
            (search.isEmpty || c.locationName.localizedCaseInsensitiveContains(search))
        }
    }
    private var visibleFiltered: [ChargeRecord] { Array(filtered.prefix(visibleCount)) }
    private var groups: [DailyHistoryGroup<ChargeRecord>] {
        DailyHistoryGrouper.group(visibleFiltered, date: \.startDate) { day in
            if Calendar.current.isDateInToday(day) { return L("Today") }
            if Calendar.current.isDateInYesterday(day) { return L("Yesterday") }
            return units.shortDate(day)
        } detail: { bucket in
            let energy = bucket.reduce(0) { $0 + $1.energyAddedKwh }
            let cost = bucket.reduce(0) { $0 + effectiveCost($1) }
            return L("\(bucket.count) sessions · +\(String(format: "%.1f", energy)) kWh · \(units.money(cost))")
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
            .alert(L("Price per kWh"), isPresented: editingBinding, presenting: editingPrice) { charge in
                TextField("0.20", text: $priceText)
                    .keyboardTypeDecimal()
                Button(L("Save")) { savePrice(for: charge) }
                Button(L("Cancel"), role: .cancel) {}
            } message: { charge in
                Text(L("Set the price for \(charge.locationName). It will be reused for future sessions at this location."))
            }
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
                HistoryMapHeader(
                    title: L("Charging"),
                    subtitle: "\(range.summaryLabel) · \(filtered.count) \(L("sessions"))",
                    metric: "+\(String(format: "%.0f", filtered.reduce(0) { $0 + $1.energyAddedKwh })) kWh",
                    content: .charges(filtered)
                )
                quickLinks
                ChargeAggregatesCard(aggregates: ChargeAggregates.from(filtered),
                                     electricityCost: electricityCost,
                                     costIsEstimated: costIsEstimated,
                                     fuelComparison: fuelComparison, units: units)
                LazyVStack(spacing: 10) {
                    ForEach(groups) { group in
                        HistoryDayHeader(title: group.title, detail: group.detail)
                        ForEach(group.items) { charge in
                            NavigationLink(value: charge) {
                                ChargeRow(charge: charge, units: units, effectiveCost: effectiveCost(charge)) {
                                    beginEditing(charge)
                                }
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

    private var quickLinks: some View {
        NavigationLink {
            ChargingLocationsModuleView(locations: chargingLocations, units: units)
        } label: {
            Label(L("Costs & places"), systemImage: "eurosign")
                .frame(maxWidth: .infinity)
        }
        .glassButtonStyle()
    }

    private var electricityCost: Double {
        // Sum each session's effective cost — recorded where present, otherwise the location's
        // custom price, the time-of-use tariff, or the global default.
        let pricing = ChargePricing(config: env.settings.config)
        return filtered.reduce(0) { $0 + pricing.cost(for: $1) }
    }

    private var chargingLocations: [ChargingLocation] {
        StatsEngine.chargingLocations(filtered, pricing: ChargePricing(config: env.settings.config))
    }

    private func effectiveCost(_ charge: ChargeRecord) -> Double {
        ChargePricing(config: env.settings.config).cost(for: charge)
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

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingPrice != nil }, set: { if !$0 { editingPrice = nil } })
    }

    private func beginEditing(_ charge: ChargeRecord) {
        editingPrice = charge
        priceText = env.settings.config.chargePricePerKwhByLocation[charge.locationName].map { String(format: "%g", $0) } ?? ""
    }

    private func savePrice(for charge: ChargeRecord) {
        let normalized = priceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(normalized), value > 0 {
            env.settings.config.chargePricePerKwhByLocation[charge.locationName] = value
            env.settings.save()
        }
        editingPrice = nil
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
                if let eff = aggregates.chargingEfficiency {
                    StatTile(title: L("Charging efficiency"), value: String(format: "%.0f%%", eff * 100),
                             systemImage: "bolt.badge.checkmark", tint: Brand.online)
                }
                if let loss = aggregates.lossKwh {
                    StatTile(title: L("Charging losses"), value: units.energy(kwh: loss, digits: 1),
                             systemImage: "arrow.down.right")
                }
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
    let effectiveCost: Double
    var addPrice: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: charge.isFastCharger ? "bolt.car" : "house")
                    .font(.subheadline).foregroundStyle(Brand.crimson)
                Text(charge.locationName).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Spacer()
                Text(units.relative(charge.startDate)).font(.caption2).foregroundStyle(Brand.textTertiary)
            }
            HStack(spacing: 10) {
                Text("+\(units.energy(kwh: charge.energyAddedKwh))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(charge.isFastCharger ? Brand.crimson : Brand.online)
                Spacer()
                Text(timeRange)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.textSecondary)
            }
            ProgressView(value: Double(charge.endBattery ?? 0), total: 100)
                .tint(Brand.online)
            HStack(spacing: 14) {
                metric("battery.50percent", "\(charge.startBattery.map { "\($0)" } ?? "—")→\(charge.endBattery.map { "\($0)%" } ?? "—")")
                metric("clock", units.duration(minutes: charge.durationMin))
                metric("creditcard", units.money(effectiveCost))
                Spacer()
                if charge.isFastCharger { Chip(text: "DC", color: Brand.crimson) }
                if charge.cost == nil {
                    Button {
                        addPrice()
                    } label: {
                        Label(L("Add price"), systemImage: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.driving)
                }
            }
        }
        .card(padding: 14)
    }

    private var timeRange: String {
        let start = units.time(charge.startDate)
        guard let end = charge.endDate else { return start }
        return "\(start) → \(units.time(end))"
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Brand.textTertiary)
            Text(value).font(.caption).foregroundStyle(Brand.textSecondary)
        }
    }
}

private struct ChargingLocationsModuleView: View {
    let locations: [ChargingLocation]
    let units: Units

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(locations) { loc in
                        HStack {
                            Image(systemName: loc.isFast ? "bolt.car.fill" : "house.fill")
                                .foregroundStyle(Brand.crimson)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(loc.name).font(.headline).foregroundStyle(Brand.textPrimary)
                                Text(L("\(loc.sessions) sessions · \(units.energy(kwh: loc.energyKwh, digits: 0))"))
                                    .font(.caption).foregroundStyle(Brand.textTertiary)
                            }
                            Spacer()
                            Text(loc.cost > 0 ? units.money(loc.cost) : units.power(kw: loc.avgPowerKw > 0 ? loc.avgPowerKw : nil))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        .card()
                    }
                    if locations.isEmpty {
                        EmptyStateView(systemImage: "mappin.circle", title: L("No charging places"), message: nil)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(L("Costs & places"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
    }
}

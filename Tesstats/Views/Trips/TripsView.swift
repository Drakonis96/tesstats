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
                VStack(spacing: 10) {
                    filterBar
                    list
                }
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
            LazyVStack(spacing: 10) {
                ForEach(filtered.prefix(visibleCount)) { drive in
                    NavigationLink(value: drive) {
                        DriveRow(drive: drive, units: units)
                    }
                    .buttonStyle(.plain)
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
}

struct DriveRow: View {
    let drive: DriveRecord
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(drive.originName).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Brand.crimson)
                Text(drive.destinationName).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Spacer()
            }
            HStack(spacing: 14) {
                metric("road.lanes", units.distance(km: drive.distanceKm))
                metric("clock", units.duration(minutes: drive.durationMin))
                metric("bolt", units.consumption(whPerKm: drive.consumptionWhPerKm))
                Spacer()
                Text(units.relative(drive.startDate)).font(.caption2).foregroundStyle(Brand.textTertiary)
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

import SwiftUI

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var refreshing = false
    @State private var showSettings = false

    private var units: Units { Units(config: env.settings.config) }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                content
            }
            .navigationTitle("")
            .toolbarTitleDisplayModeInline()
            .toolbar { toolbarContent }
            .settingsSheet(isPresented: $showSettings)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let state = env.live.currentState {
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    #if os(iOS)
                    LogoMark(width: 290)
                        .shadow(color: Brand.crimson.opacity(0.3), radius: 14)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    #endif
                    HeaderSummaryCard(state: state, status: env.live.status, units: units)
                    ForEach(DashboardCard.resolved(env.settings.config.dashboardCardOrder)) { card in
                        cardView(card, state: state)
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
        } else {
            waitingState
        }
    }

    @ViewBuilder
    private var waitingState: some View {
        switch env.live.status {
        case .connecting:
            LoadingStateView(label: L("Connecting to TeslaMate…"))
        case .failed(let message):
            ErrorStateView(message: message) { env.live.restart() }
        case .notConfigured:
            EmptyStateView(systemImage: "server.rack",
                           title: L("Not connected"),
                           message: L("Set up your TeslaMate server in Settings, or try demo mode."),
                           actionTitle: L("Enable demo mode")) { env.enableDemoMode() }
        default:
            EmptyStateView(systemImage: "antenna.radiowaves.left.and.right",
                           title: L("Waiting for data"),
                           message: L("Connected — waiting for the first MQTT messages from your car."))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .leadingBar) { ConnectionStatusMenu() }
        #endif
        ToolbarItemGroup(placement: .trailingBar) {
            #if os(iOS)
            SettingsGearButton(isPresented: $showSettings)
            #endif
            RefreshButton(isRefreshing: refreshing) { Task { await refresh() } }
        }
    }

    @ViewBuilder
    private func cardView(_ card: DashboardCard, state: VehicleState) -> some View {
        switch card {
        case .battery: BatterySummaryCard(state: state, units: units)
        case .charging: if state.isCharging { ChargingCard(state: state, units: units) }
        case .driving: if state.isDriving { DrivingCard(state: state, units: units) }
        case .sentry: if state.sentryBannerActive { SentryInferredCard(state: state, units: units) }
        case .climate: ClimateCard(state: state, units: units)
        case .security: SecurityCard(state: state)
        case .tpms: TPMSCard(state: state, units: units)
        case .location: LocationCard(state: state, units: units)
        case .route: if state.activeRouteDestination != nil { RouteCard(state: state, units: units) }
        case .vehicle: VehicleInfoCard(info: env.history.carInfo, state: state, units: units)
        case .software: SoftwareCard(state: state)
        }
    }

    private func refresh() async {
        refreshing = true
        env.live.restart()
        if let id = env.live.resolvedCarID { await env.history.refresh(carID: id) }
        try? await Task.sleep(for: .seconds(1.0))
        refreshing = false
    }
}

enum DashboardCard: String, CaseIterable, Identifiable, Codable {
    case battery, charging, driving, sentry, climate, security, tpms, location, route, vehicle, software
    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: L("Battery")
        case .charging: L("Charging")
        case .driving: L("Driving")
        case .sentry: L("Sentry")
        case .climate: L("Climate")
        case .security: L("Security")
        case .tpms: L("Tire pressure")
        case .location: L("Location")
        case .route: L("Active route")
        case .vehicle: L("Vehicle")
        case .software: L("Software")
        }
    }
    var icon: String {
        switch self {
        case .battery: "battery.100percent"
        case .charging: "bolt.fill"
        case .driving: "steeringwheel"
        case .sentry: "video.fill"
        case .climate: "thermometer.medium"
        case .security: "lock.shield"
        case .tpms: "gauge.with.dots.needle.bottom.50percent"
        case .location: "mappin.and.ellipse"
        case .route: "arrow.triangle.turn.up.right.diamond"
        case .vehicle: "car.fill"
        case .software: "cpu"
        }
    }

    /// Resolve a saved order into a complete, valid card list (appends any new cards).
    static func resolved(_ raw: [String]) -> [DashboardCard] {
        let saved = raw.compactMap { DashboardCard(rawValue: $0) }
        guard !saved.isEmpty else { return allCases }
        let missing = allCases.filter { !saved.contains($0) }
        return saved + missing
    }
}

extension View {
    /// Inline toolbar title on iOS (so the centered logo sits in the bar); no-op elsewhere.
    @ViewBuilder
    func toolbarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

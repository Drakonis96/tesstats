import SwiftUI

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var refreshing = false
    @State private var showSettings = false
    @State private var showInbox = false
    @State private var tutorialStep = 0
    @State private var showTutorial = false
    @AppStorage("tesstats.dashboard.tutorial.completed") private var tutorialCompleted = false

    private var units: Units { Units(config: env.settings.config) }
    private var carID: Int { env.live.resolvedCarID ?? 1 }
    private var insights: DashboardInsights {
        DashboardInsightEngine.insights(drives: env.history.drives, charges: env.history.charges)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DemoDataBanner(isDemo: env.settings.config.demoMode) { showSettings = true }
                ZStack {
                    Brand.background.ignoresSafeArea()
                    content
                    if showTutorial { tutorialOverlay }
                }
            }
            .navigationTitle("")
            .toolbarTitleDisplayModeInline()
            .toolbar { toolbarContent }
            .settingsSheet(isPresented: $showSettings)
            .sheet(isPresented: $showInbox) {
                NotificationInboxView()   // brings its own NavigationStack
            }
        }
        .task(id: carID) { await env.history.loadIfNeeded(carID: carID) }
    }

    @ViewBuilder
    private var content: some View {
        if let state = env.live.currentState {
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    HeroMapCard(state: state, units: units)
                        .accessibilityIdentifier("dashboard-map-hero")
                    dashboardQuickStats(state)
                    if let last = insights.lastDrive { LastDriveDashboardCard(drive: last, units: units) }
                    ActivityTimelineView(segments: insights.activity48h)
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
            .onAppear {
                if !tutorialCompleted && ProcessInfo.processInfo.environment["TESSTATS_SKIP_TUTORIAL"] != "1" {
                    showTutorial = true
                }
            }
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
        ToolbarItem(placement: .principal) { ToolbarLogo() }
        #endif
        ToolbarItemGroup(placement: .trailingBar) {
            #if os(iOS)
            SettingsGearButton(isPresented: $showSettings)
            #endif
            Button {
                showInbox = true
            } label: {
                Image(systemName: "bell")
            }
            .tint(Brand.crimson)
            .accessibilityLabel(L("Notifications"))
            RefreshButton(isRefreshing: refreshing) { Task { await refresh() } }
        }
    }

    private func dashboardQuickStats(_ state: VehicleState) -> some View {
        HStack(spacing: 12) {
            StatTile(title: L("Efficiency 30d"),
                     value: insights.efficiency30dWhPerKm.map { "\(Int($0)) Wh/km" } ?? "—",
                     systemImage: "leaf.fill", tint: Brand.driving)
            StatTile(title: L("Range"),
                     value: units.range(km: state.range(for: units.range)),
                     systemImage: "road.lanes")
            StatTile(title: L("Odometer"),
                     value: units.distance(km: state.odometer, digits: 0),
                     systemImage: "gauge")
        }
        .card()
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

    private var tutorialOverlay: some View {
        let steps = tutorialSteps
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: steps[tutorialStep].icon)
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Brand.crimson.opacity(0.35), in: Circle())
                    Spacer()
                    Text("\(tutorialStep + 1) / \(steps.count)")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Text(steps[tutorialStep].title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(steps[tutorialStep].body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                HStack {
                    Button(L("Skip tutorial")) { finishTutorial() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    Spacer()
                    Button(tutorialStep == steps.count - 1 ? L("Done") : L("Next")) {
                        if tutorialStep == steps.count - 1 {
                            finishTutorial()
                        } else {
                            withAnimation(.snappy) { tutorialStep += 1 }
                        }
                    }
                    .font(.headline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.crimson)
                }
            }
            .padding(24)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Brand.hairline, lineWidth: 1))
            .padding(28)
        }
    }

    private func finishTutorial() {
        tutorialCompleted = true
        withAnimation(.snappy) { showTutorial = false }
    }

    private var tutorialSteps: [(title: String, body: String, icon: String)] {
        [
            (L("This is your dashboard"), L("Battery, range and location now start from a live map-first overview."), "hand.wave.fill"),
            (L("Recent activity"), L("The 48-hour timeline highlights driving and charging without sending commands to the car."), "clock.arrow.circlepath"),
            (L("Read-only insights"), L("Trips, charges, parking and notifications are derived from TeslaMate data."), "eye.fill")
        ]
    }
}

private struct LastDriveDashboardCard: View {
    let drive: DriveRecord
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Last trip"), systemImage: "road.lanes")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(drive.originName).font(.headline.weight(.bold)).lineLimit(1)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(Brand.crimson)
                        Text(drive.destinationName).font(.headline.weight(.bold)).lineLimit(1)
                    }
                    Text("\(units.distance(km: drive.distanceKm)) · \(units.duration(minutes: drive.durationMin))")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                TinyRoutePreview(path: drive.path)
            }
        }
        .card()
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

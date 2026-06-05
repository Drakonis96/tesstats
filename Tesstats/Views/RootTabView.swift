import SwiftUI

/// Five-tab root. On iOS 26 the `TabView` automatically renders the Liquid Glass tab bar;
/// on iPad/macOS it adapts to a sidebar while preserving the same semantics.
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: AppTab

    init() {
        let raw = ProcessInfo.processInfo.environment["TESSTATS_TAB"] ?? ""
        _selection = State(initialValue: AppTab(rawValue: raw) ?? .summary)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(L("Summary"), systemImage: "gauge.with.dots.needle.67percent", value: AppTab.summary) {
                DashboardView()
            }
            Tab(L("Trips"), systemImage: "map", value: AppTab.trips) {
                TripsView()
            }
            Tab(L("Charging"), systemImage: "bolt.fill", value: AppTab.charging) {
                ChargesView()
            }
            Tab(L("Battery"), systemImage: "battery.100percent", value: AppTab.battery) {
                BatteryView()
            }
            Tab(L("Stats"), systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                StatsView()
            }
        }
        .tint(Brand.crimson)
    }
}

enum AppTab: String, Hashable, CaseIterable {
    case summary, trips, charging, battery, stats, settings

    var title: String {
        switch self {
        case .summary: L("Summary")
        case .trips: L("Trips")
        case .charging: L("Charging")
        case .battery: L("Battery")
        case .stats: L("Stats")
        case .settings: L("Settings")
        }
    }
    var icon: String {
        switch self {
        case .summary: "gauge.with.dots.needle.67percent"
        case .trips: "map"
        case .charging: "bolt.fill"
        case .battery: "battery.100percent"
        case .stats: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

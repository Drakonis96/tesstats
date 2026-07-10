import SwiftUI
import MapKit

struct MoreHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        moduleSection(L("Areas"), color: Brand.driving, rows: areaRows)
                        moduleSection(L("Vehicle"), color: Brand.online, rows: vehicleRows)
                        moduleSection(L("Explore"), color: Color(hex: 0x9B5CFF), rows: exploreRows)
                        Color.clear.frame(height: 8)
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, 16)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L("More"))
            .toolbarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    SettingsGearButton(isPresented: $showSettings)
                }
            }
            .settingsSheet(isPresented: $showSettings)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(env.live.currentState?.displayName ?? env.history.carInfo?.name ?? L("Tesla"))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            if !headerSubtitle.isEmpty {
                Text(headerSubtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.textTertiary)
            }
        }
        .padding(.vertical, 10)
    }

    /// Model + trim when known (e.g. "Model 3 Long Range"), otherwise nothing.
    private var headerSubtitle: String {
        let info = env.history.carInfo
        guard let raw = env.live.currentState?.model ?? info?.model, !raw.isEmpty else { return "" }
        // TeslaMate reports the bare designation ("3", "Y"); older APIs may send "Model 3".
        let model = raw.count <= 2 ? "Model \(raw)" : raw
        return [model, info?.trimBadging].compactMap { $0 }.joined(separator: " ")
    }

    private func moduleSection(_ title: String, color: Color, rows: [MoreRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.bold)).foregroundStyle(Brand.textTertiary).tracking(3).textCase(.uppercase)
            }
            .padding(.bottom, 12)
            ForEach(rows) { row in
                NavigationLink {
                    row.destination
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: row.icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(color)
                            .frame(width: 34)
                        Text(row.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Brand.textPrimary)
                        Spacer()
                        if row.badge != nil {
                            Chip(text: row.badge ?? "", color: Brand.warning)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Brand.textTertiary)
                        }
                    }
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(Brand.hairline)
            }
        }
    }

    private var areaRows: [MoreRow] {
        [
            MoreRow(title: L("Statistics"), icon: "chart.line.uptrend.xyaxis") { StatsView() },
            MoreRow(title: L("Notifications"), icon: "bell.fill") { NotificationInboxView() },
            MoreRow(title: L("Parking"), icon: "parkingsign") { ParkingView() }
        ]
    }

    private var vehicleRows: [MoreRow] {
        [
            MoreRow(title: L("Battery health"), icon: "bolt.batteryblock") { BatteryView() },
            MoreRow(title: L("Tires"), icon: "gauge.with.dots.needle.bottom.50percent") { TireModuleView() },
            MoreRow(title: L("Mileage tracking"), icon: "speedometer") { MileageModuleView() },
            MoreRow(title: L("Specs & warranty"), icon: "checkmark.shield") { VehicleSpecsView() }
        ]
    }

    private var exploreRows: [MoreRow] {
        [
            MoreRow(title: L("Weather"), icon: "cloud.sun") { WeatherModuleView() },
            MoreRow(title: L("Supercharger map"), icon: "mappin.circle") { SuperchargerMapView() }
        ]
    }
}

private struct MoreRow: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var badge: String?
    var destination: AnyView

    init<Content: View>(title: String, icon: String, badge: String? = nil, @ViewBuilder destination: () -> Content) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.destination = AnyView(destination())
    }
}

private struct TireModuleView: View {
    @Environment(AppEnvironment.self) private var env
    private var units: Units { Units(config: env.settings.config) }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: Metrics.cardSpacing) {
                if let state = env.live.currentState {
                    TPMSCard(state: state, units: units)
                } else {
                    EmptyStateView(systemImage: "gauge.with.dots.needle.bottom.50percent", title: L("No tire data"), message: L("TPMS readings arrive when the car is awake."))
                }
            }
            .padding()
        }
        .navigationTitle(L("Tires"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
    }
}

private struct MileageModuleView: View {
    @Environment(AppEnvironment.self) private var env
    private var units: Units { Units(config: env.settings.config) }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: Metrics.cardSpacing) {
                TileGrid(columns: 2) {
                    StatTile(title: L("Odometer"), value: units.distance(km: env.live.currentState?.odometer, digits: 0), systemImage: "gauge", tint: Brand.driving)
                    StatTile(title: L("Trips"), value: "\(env.history.drives.count)", systemImage: "road.lanes")
                    StatTile(title: L("Total distance"), value: units.distance(km: env.history.drives.reduce(0) { $0 + $1.distanceKm }, digits: 0), systemImage: "map")
                    StatTile(title: L("Avg / trip"), value: units.distance(km: averageTrip, digits: 1), systemImage: "arrow.left.and.right")
                }
                .card()
                Spacer()
            }
            .padding()
        }
        .navigationTitle(L("Mileage"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
    }

    private var averageTrip: Double? {
        guard !env.history.drives.isEmpty else { return nil }
        return env.history.drives.reduce(0) { $0 + $1.distanceKm } / Double(env.history.drives.count)
    }
}

private struct VehicleSpecsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 12) {
                if let info = env.history.carInfo {
                    KeyValueRow(label: L("Model"), value: [info.model, info.trimBadging].compactMap { $0 }.joined(separator: " "))
                    KeyValueRow(label: "VIN", value: info.vin ?? "—")
                    KeyValueRow(label: L("Color"), value: info.exteriorColor ?? "—")
                    KeyValueRow(label: L("Wheels"), value: info.wheelType ?? "—")
                    KeyValueRow(label: L("Warranty"), value: L("Not available from TeslaMate"))
                } else {
                    EmptyStateView(systemImage: "checkmark.shield", title: L("No vehicle specs"), message: L("Connect TeslaMateApi to show vehicle details."))
                }
            }
            .card()
            .padding()
        }
        .navigationTitle(L("Specs & warranty"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
    }
}

private struct WeatherModuleView: View {
    @Environment(AppEnvironment.self) private var env
    private var units: Units { Units(config: env.settings.config) }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            TileGrid(columns: 2) {
                StatTile(title: L("Outside"), value: units.temperature(c: env.live.currentState?.outsideTemp), systemImage: "cloud.sun", tint: Brand.driving)
                StatTile(title: L("Cabin"), value: units.temperature(c: env.live.currentState?.insideTemp), systemImage: "car", tint: Brand.warning)
            }
            .card()
            .padding()
        }
        .navigationTitle(L("Weather"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
    }
}

private struct SuperchargerMapView: View {
    @Environment(AppEnvironment.self) private var env
    private var fastCharges: [ChargeRecord] { env.history.charges.filter(\.isFastCharger) }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            if fastCharges.compactMap(\.coord).isEmpty {
                EmptyStateView(systemImage: "mappin.circle", title: L("No Supercharger locations"), message: L("Fast charging places appear here after TeslaMate records them."))
            } else {
                HistoryMapHeader(title: L("Superchargers"), subtitle: L("\(fastCharges.count) fast sessions"), metric: L("Map"), content: .charges(fastCharges))
                    .padding()
            }
        }
        .navigationTitle(L("Superchargers"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
    }
}

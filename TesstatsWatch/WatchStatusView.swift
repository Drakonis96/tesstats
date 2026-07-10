import SwiftUI

/// The single watch screen: battery gauge, range and state, plus charging progress
/// while a session is active. Strictly read-only, like the rest of Tesstats.
struct WatchStatusView: View {
    @Environment(WatchSnapshotStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let snap = store.snapshot {
                    content(snap)
                } else {
                    waiting
                }
            }
            .navigationTitle("Tesstats")
        }
    }

    private var waiting: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Tesstats on your iPhone to sync.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func content(_ snap: WidgetSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                gauge(snap)
                HStack {
                    label(String(localized: "Range"), value: snap.rangeString())
                    Spacer()
                    stateChip(snap)
                }
                if snap.isCharging { chargingSection(snap) }
                if let title = snap.lastTripTitle {
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last trip").font(.caption2).foregroundStyle(.secondary)
                        Text(title).font(.footnote.weight(.medium)).lineLimit(2)
                        if let km = snap.lastTripDistanceKm {
                            Text(snap.distanceString(km)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if snap.lastUpdated > .distantPast {
                    Text("Updated \(snap.lastUpdated, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func gauge(_ snap: WidgetSnapshot) -> some View {
        Gauge(value: Double(snap.batteryLevel), in: 0...100) {
            Text("Battery")
        } currentValueLabel: {
            Text("\(snap.batteryLevel)%")
                .font(.system(.title3, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(batteryTint(snap))
        .scaleEffect(1.4)
        .frame(height: 84)
        .accessibilityLabel(Text("Battery \(snap.batteryLevel)%"))
    }

    private func batteryTint(_ snap: WidgetSnapshot) -> Color {
        if snap.isCharging { return .green }
        if snap.batteryLevel <= 20 { return .red }
        return Color(red: 0.86, green: 0.08, blue: 0.24)   // brand crimson
    }

    private func chargingSection(_ snap: WidgetSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(snap.powerString, systemImage: "bolt.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                if let limit = snap.chargeLimitSoc {
                    Text("→ \(limit)%").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let eta = snap.timeToFullHours, eta > 0 {
                HStack {
                    Text("Time to limit").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(WidgetSnapshot.timeString(hours: eta)).font(.caption2.weight(.semibold))
                }
            }
        }
        .padding(8)
        .background(.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    private func label(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold))
        }
    }

    private func stateChip(_ snap: WidgetSnapshot) -> some View {
        Text(stateLabel(snap.stateRaw))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }

    private func stateLabel(_ raw: String) -> String {
        switch raw {
        case "online": String(localized: "Online")
        case "asleep": String(localized: "Asleep")
        case "suspended": String(localized: "Asleep")
        case "charging": String(localized: "Charging")
        case "driving": String(localized: "Driving")
        case "offline": String(localized: "Offline")
        case "updating": String(localized: "Updating")
        default: raw.capitalized
        }
    }
}

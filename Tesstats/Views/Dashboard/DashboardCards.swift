import SwiftUI
import MapKit

// MARK: - Layout helper

struct TileGrid<Content: View>: View {
    var columns: Int = 3
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: columns),
            alignment: .leading, spacing: 16) {
            content
        }
    }
}

// MARK: - Header

struct HeaderSummaryCard: View {
    let state: VehicleState
    let status: ConnectionStatus
    let units: Units

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(state.displayName ?? "Tesla")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Brand.textPrimary)
                Text(state.modelLine.isEmpty ? "Tesla" : state.modelLine)
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                HStack(spacing: 8) {
                    if let st = state.state {
                        Chip(text: st.label, systemImage: st.symbol, color: st.color, filled: true)
                    }
                    if let since = state.since {
                        Text(units.relative(since)).font(.caption).foregroundStyle(Brand.textTertiary)
                    }
                }
            }
            Spacer()
            if let healthy = state.healthy {
                VStack(spacing: 3) {
                    Image(systemName: healthy ? "heart.fill" : "heart.slash")
                        .foregroundStyle(healthy ? Brand.online : Brand.danger)
                    Text(healthy ? L("Healthy") : L("Check"))
                        .font(.caption2).foregroundStyle(Brand.textTertiary)
                }
            }
        }
        .card()
    }
}

struct VehicleInfoCard: View {
    let info: CarInfo?
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Vehicle"), systemImage: "car.fill")
            TileGrid(columns: 3) {
                if let eff = info?.efficiencyKwhPerKm, eff > 0 {
                    StatTile(title: L("Efficiency"), value: "\(Int(eff * 1000)) Wh/km", tint: Brand.crimson)
                }
                if let color = info?.exteriorColor ?? state.exteriorColor {
                    StatTile(title: L("Color"), value: prettyColor(color))
                }
                if let wheels = info?.wheelType ?? state.wheelType {
                    StatTile(title: L("Wheels"), value: wheels)
                }
                if let drives = info?.totalDrives {
                    StatTile(title: L("Total drives"), value: "\(drives)", systemImage: "road.lanes")
                }
                if let charges = info?.totalCharges {
                    StatTile(title: L("Total charges"), value: "\(charges)", systemImage: "bolt")
                }
                if let updates = info?.totalUpdates {
                    StatTile(title: L("Updates"), value: "\(updates)", systemImage: "arrow.down.circle")
                }
            }
            if let vin = info?.vin, !vin.isEmpty {
                Divider().overlay(Brand.hairline)
                KeyValueRow(label: "VIN", value: vin, systemImage: "number")
            }
        }
        .card()
    }

    private func prettyColor(_ raw: String) -> String {
        // TeslaMate color codes → readable (best-effort).
        let map = ["DeepBlue": L("Deep Blue"), "StealthGrey": L("Stealth Grey"),
                   "PearlWhite": L("Pearl White"), "SolidBlack": L("Black"),
                   "RedMulticoat": L("Red"), "MidnightSilver": L("Midnight Silver"),
                   "SilverMetallic": L("Silver")]
        return map[raw] ?? raw
    }
}

// MARK: - Battery

struct BatterySummaryCard: View {
    let state: VehicleState
    let units: Units

    private var level: Int { state.batteryLevel ?? state.usableBatteryLevel ?? 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            BatteryRing(
                level: level,
                usableLevel: state.usableBatteryLevel,
                charging: state.isCharging,
                limitSoc: state.chargeLimitSoc,
                centerTitle: "\(level)%",
                centerSubtitle: units.range(km: state.range(for: units.range)),
                size: 168)

            VStack(alignment: .leading, spacing: 14) {
                miniStat(L("Range"), units.range(km: state.range(for: units.range)), "road.lanes")
                if let usable = state.usableBatteryLevel {
                    miniStat(L("Usable"), "\(usable)%", "bolt.badge.checkmark")
                }
                if let limit = state.chargeLimitSoc {
                    miniStat(L("Charge limit"), "\(limit)%", "target")
                }
                if let odo = state.odometer {
                    miniStat(L("Odometer"), units.distance(km: odo, digits: 0), "gauge")
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func miniStat(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(Brand.crimson).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(Brand.textTertiary)
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary)
            }
        }
    }
}

// MARK: - Charging

struct ChargingCard: View {
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Charging"), systemImage: "bolt.fill")
            TileGrid(columns: 3) {
                StatTile(title: L("Power"), value: units.power(kw: state.chargerPower), tint: Brand.crimson)
                StatTile(title: L("Voltage"), value: units.volts(state.chargerVoltage))
                StatTile(title: L("Current"), value: units.amps(state.chargerActualCurrent))
                StatTile(title: L("Added"), value: units.energy(kwh: state.chargeEnergyAdded))
                StatTile(title: L("Phases"), value: state.chargerPhases.map(String.init) ?? "—")
                StatTile(title: L("Time to full"), value: units.duration(hours: state.timeToFullCharge))
            }
            Divider().overlay(Brand.hairline)
            VStack(spacing: 10) {
                if let cs = state.chargingState {
                    KeyValueRow(label: L("State"), value: cs.label, valueColor: Brand.crimson, systemImage: "bolt.circle")
                }
                KeyValueRow(label: L("Plugged in"), value: boolText(state.pluggedIn), systemImage: "powerplug")
                KeyValueRow(label: L("Charge port"), value: state.chargePortDoorOpen == true ? L("Open") : L("Closed"), systemImage: "door.left.hand.open")
                if let sched = state.scheduledChargingStartTime {
                    KeyValueRow(label: L("Scheduled start"), value: units.shortDateTime(sched), systemImage: "clock")
                }
            }
        }
        .card()
    }

    private func boolText(_ b: Bool?) -> String {
        b == true ? L("Yes") : (b == false ? L("No") : "—")
    }
}

// MARK: - Driving

struct DrivingCard: View {
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Driving"), systemImage: "steeringwheel")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(units.speed(kmh: state.speed).replacingOccurrences(of: " \(units.speedUnit)", with: ""))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .contentTransition(.numericText())
                Text(units.speedUnit).font(.headline).foregroundStyle(Brand.textTertiary)
                Spacer()
                if let heading = state.heading {
                    Image(systemName: "location.north.fill")
                        .font(.title2)
                        .foregroundStyle(Brand.crimson)
                        .rotationEffect(.degrees(Double(heading)))
                }
            }
            TileGrid(columns: 3) {
                StatTile(title: L("Power"), value: units.power(kw: state.power), tint: Brand.crimson)
                StatTile(title: L("Gear"), value: state.shiftState?.label ?? "—")
                StatTile(title: L("Elevation"), value: state.elevation.map { "\($0) m" } ?? "—")
            }
        }
        .card()
    }
}

// MARK: - Sentry (inferred)

struct SentryInferredCard: View {
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "video.badge.waveform").foregroundStyle(Brand.crimson)
                Text(L("Possible Sentry event")).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary)
                Spacer()
                Chip(text: L("Inferred"), color: Brand.warning)
            }
            Text(L("The car is showing the Sentry banner (center display state 7) near \(state.geofence ?? L("its location")). This is inferred — any clip is on the car's USB and isn't available via TeslaMate."))
                .font(.caption).foregroundStyle(Brand.textSecondary)
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(Brand.crimson.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Climate

struct ClimateCard: View {
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Climate"), systemImage: "thermometer.medium")
            TileGrid(columns: 3) {
                StatTile(title: L("Inside"), value: units.temperature(c: state.insideTemp), systemImage: "car.side")
                StatTile(title: L("Outside"), value: units.temperature(c: state.outsideTemp), systemImage: "cloud.sun")
                StatTile(title: L("A/C"), value: onOff(state.isClimateOn),
                         systemImage: "fan", tint: state.isClimateOn == true ? Brand.crimson : Brand.textPrimary)
            }
            if state.isPreconditioning == true || state.climateKeeperMode != nil {
                HStack(spacing: 8) {
                    if state.isPreconditioning == true { Chip(text: L("Preconditioning"), systemImage: "snowflake") }
                    if let mode = state.climateKeeperMode, mode != "off", !mode.isEmpty {
                        Chip(text: mode.capitalized, systemImage: "shield", color: Brand.driving)
                    }
                }
            }
        }
        .card()
    }

    private func onOff(_ b: Bool?) -> String {
        b == true ? L("On") : (b == false ? L("Off") : "—")
    }
}

// MARK: - Security

struct SecurityCard: View {
    let state: VehicleState

    private var openings: [(String, Bool)] {
        [
            (L("Frunk"), state.frunkOpen == true),
            (L("Trunk"), state.trunkOpen == true),
            (L("Windows"), state.windowsOpen == true),
            (L("Driver front"), state.driverFrontDoorOpen == true),
            (L("Driver rear"), state.driverRearDoorOpen == true),
            (L("Passenger front"), state.passengerFrontDoorOpen == true),
            (L("Passenger rear"), state.passengerRearDoorOpen == true)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Security"), systemImage: "lock.shield")
            HStack(spacing: 10) {
                statusBadge(icon: state.locked == false ? "lock.open.fill" : "lock.fill",
                            text: state.locked == false ? L("Unlocked") : L("Locked"),
                            color: state.locked == false ? Brand.warning : Brand.online)
                if state.sentryMode == true {
                    statusBadge(icon: "video.fill", text: L("Sentry on"), color: Brand.crimson)
                }
                if state.isUserPresent == true {
                    statusBadge(icon: "person.fill", text: L("Occupied"), color: Brand.driving)
                }
                Spacer()
            }
            let open = openings.filter { $0.1 }
            if open.isEmpty {
                Label(L("Everything closed"), systemImage: "checkmark.seal")
                    .font(.subheadline).foregroundStyle(Brand.online)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(open, id: \.0) { item in
                            Chip(text: item.0, systemImage: "exclamationmark.triangle.fill", color: Brand.warning)
                        }
                    }
                }
            }
        }
        .card()
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(text).font(.caption2).foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Brand.elevatedSurface, in: RoundedRectangle(cornerRadius: Metrics.tightRadius))
    }
}

// MARK: - TPMS

struct TPMSCard: View {
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Tire pressure"), systemImage: "gauge.with.dots.needle.bottom.50percent")
            HStack(spacing: 12) {
                tire(L("FL"), state.tpmsPressureFL)
                tire(L("FR"), state.tpmsPressureFR)
                tire(L("RL"), state.tpmsPressureRL)
                tire(L("RR"), state.tpmsPressureRR)
            }
        }
        .card()
    }

    private func tire(_ label: String, _ bar: Double?) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(Brand.textTertiary)
            Text(units.pressure(bar: bar)).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Brand.elevatedSurface, in: RoundedRectangle(cornerRadius: Metrics.tightRadius))
    }
}

// MARK: - Location

struct LocationCard: View {
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(L("Location"), systemImage: "mappin.and.ellipse")
                if let geofence = state.geofence, !geofence.isEmpty {
                    Chip(text: geofence, systemImage: "mappin", color: Brand.crimson)
                }
            }
            if let coord = state.coordinate {
                MiniMap(coordinate: coord)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.tightRadius))
            } else {
                EmptyStateView(systemImage: "mappin.slash", title: L("No position"), message: nil)
                    .frame(height: 120)
            }
        }
        .card()
    }
}

struct MiniMap: View {
    let coordinate: Coordinate
    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate.clLocationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
            Annotation("", coordinate: coordinate.clLocationCoordinate) {
                ZStack {
                    Circle().fill(Brand.crimson.opacity(0.25)).frame(width: 34, height: 34)
                    Circle().fill(Brand.crimson).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

// MARK: - Active route

struct RouteCard: View {
    let state: VehicleState
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Active route"), systemImage: "arrow.triangle.turn.up.right.diamond")
            Text(state.activeRouteDestination ?? "—")
                .font(.headline).foregroundStyle(Brand.textPrimary).lineLimit(2)
            TileGrid(columns: 3) {
                StatTile(title: L("Distance"),
                         value: units.distance(km: state.activeRouteMilesToArrival.map { $0 * 1.609344 }, digits: 1))
                StatTile(title: L("Traffic delay"),
                         value: state.activeRouteTrafficMinutesDelay.map { "\(Int($0)) min" } ?? "—",
                         tint: (state.activeRouteTrafficMinutesDelay ?? 0) > 0 ? Brand.warning : Brand.textPrimary)
                StatTile(title: L("Battery at arrival"),
                         value: state.activeRouteEnergyAtArrival.map { "\($0)%" } ?? "—", tint: Brand.crimson)
            }
        }
        .card()
    }
}

// MARK: - Software

struct SoftwareCard: View {
    let state: VehicleState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Software"), systemImage: "cpu")
            KeyValueRow(label: L("Installed"), value: state.version ?? "—", systemImage: "checkmark.seal")
            if state.updateAvailable == true {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Brand.crimson)
                    Text(L("Update available\(state.updateVersion.map { ": \($0)" } ?? "")"))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Brand.crimson)
                    Spacer()
                }
            } else {
                Label(L("Up to date"), systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(Brand.online)
            }
        }
        .card()
    }
}

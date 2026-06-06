import SwiftUI
import MapKit
import Charts
import CoreLocation

struct TripDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let drive: DriveRecord
    let units: Units

    /// The drive's real recorded GPS positions (from TeslaMateApi's drive-details endpoint,
    /// or the demo record's own path). The route is drawn straight from these — no geocoding.
    @State private var path: [Coordinate] = []
    @State private var elevation: [Double] = []
    @State private var routeState: RouteState = .loading

    enum RouteState { case loading, ready, unavailable }

    /// Prefer the elevation fetched alongside the trace; fall back to whatever the record carries.
    private var elevationProfile: [Double] { elevation.isEmpty ? drive.elevationProfile : elevation }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    routeCard
                    statsCard
                    if elevationProfile.count > 1 { elevationCard }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L("Trip"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
        .toolbar {
            if let url = ExportService.driveGPXFile(drive) {
                ToolbarItem(placement: .trailingBar) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .tint(Brand.crimson)
                }
            }
        }
        .task { await loadTrace() }
    }

    // MARK: - Route map

    @ViewBuilder
    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(drive.originName).font(.headline).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(Brand.crimson)
                Text(drive.destinationName).font(.headline).foregroundStyle(Brand.textPrimary).lineLimit(1)
            }
            Text(units.shortDateTime(drive.startDate)).font(.caption).foregroundStyle(Brand.textTertiary)

            switch routeState {
            case .loading:
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.tightRadius).fill(Brand.elevatedSurface)
                    ProgressView().tint(Brand.crimson)
                }
                .frame(height: 240)
            case .ready:
                routeMap
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.tightRadius))
                Text(L("Route drawn from the trip's recorded GPS positions."))
                    .font(.caption2).foregroundStyle(Brand.textTertiary)
            case .unavailable:
                EmptyStateView(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                               title: L("Map unavailable"),
                               message: L("No recorded GPS positions for this trip."))
                    .frame(height: 130)
            }
        }
        .card()
    }

    @ViewBuilder
    private var routeMap: some View {
        Map(initialPosition: .region(MKCoordinateRegion(fitting: path))) {
            MapPolyline(coordinates: path.map(\.clLocationCoordinate))
                .stroke(Brand.crimson, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            if let s = path.first {
                Annotation(L("Start"), coordinate: s.clLocationCoordinate) { endpointDot(Brand.online) }
            }
            if let e = path.last {
                Annotation(L("End"), coordinate: e.clLocationCoordinate) { endpointDot(Brand.crimson) }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func endpointDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
    }

    /// Draw the route from the drive's real recorded GPS positions. Demo records already carry
    /// their own path; live records fetch the per-point trace from TeslaMateApi on demand. No
    /// text geocoding is involved, so an ambiguous city name can never resolve to the wrong place.
    private func loadTrace() async {
        if drive.path.count >= 2 {
            path = drive.path
            elevation = drive.elevationProfile
            routeState = .ready
            return
        }
        let carID = env.live.resolvedCarID ?? 1
        if let trace = await env.history.driveTrace(carID: carID, driveID: drive.id), trace.isUsable {
            path = trace.path
            elevation = trace.elevationProfile
            routeState = .ready
        } else {
            routeState = .unavailable
        }
    }

    // MARK: - Stats

    private var energyUsedKwh: Double? {
        guard let c = drive.consumptionWhPerKm, c > 0, drive.distanceKm > 0 else { return nil }
        return c * drive.distanceKm / 1000.0
    }

    private var rangeUsedKm: Double? {
        guard let s = drive.startRangeKm, let e = drive.endRangeKm else { return nil }
        return max(0, s - e)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Summary"), systemImage: "list.bullet.clipboard")
            TileGrid(columns: 3) {
                StatTile(title: L("Distance"), value: units.distance(km: drive.distanceKm), tint: Brand.crimson)
                StatTile(title: L("Duration"), value: units.duration(minutes: drive.durationMin))
                ConsumptionStat(title: L("Consumption"), whPerKm: drive.consumptionWhPerKm, units: units)
                StatTile(title: L("Avg speed"), value: units.speed(kmh: drive.avgSpeedKmh))
                StatTile(title: L("Max speed"), value: units.speed(kmh: drive.maxSpeedKmh))
                StatTile(title: L("Max power"), value: units.power(kw: drive.maxPowerKw))
                StatTile(title: L("Energy used"), value: units.energy(kwh: energyUsedKwh))
                StatTile(title: L("Range used"), value: units.range(km: rangeUsedKm))
                StatTile(title: L("Elev. gain"), value: elevationGain)
            }
            Divider().overlay(Brand.hairline)
            VStack(spacing: 10) {
                KeyValueRow(label: L("Battery"),
                            value: "\(drive.startBattery.map { "\($0)%" } ?? "—") → \(drive.endBattery.map { "\($0)%" } ?? "—")",
                            systemImage: "battery.50percent")
                KeyValueRow(label: L("Temperature"),
                            value: "\(units.temperature(c: drive.insideTempAvg)) · \(units.temperature(c: drive.outsideTempAvg))",
                            systemImage: "thermometer.medium")
                KeyValueRow(label: L("When"), value: units.shortDateTime(drive.startDate), systemImage: "calendar")
            }
        }
        .card()
    }

    private var elevationGain: String {
        let profile = elevationProfile
        guard profile.count > 1 else { return "—" }
        var gain = 0.0
        for i in 1..<profile.count {
            let d = profile[i] - profile[i - 1]
            if d > 0 { gain += d }
        }
        return "\(Int(gain)) m"
    }

    private var elevationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Elevation"), systemImage: "mountain.2")
            Chart(Array(elevationProfile.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("Point", index), y: .value("m", value))
                    .foregroundStyle(LinearGradient(colors: [Brand.crimson.opacity(0.4), .clear],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Point", index), y: .value("m", value))
                    .foregroundStyle(Brand.crimson)
                    .interpolationMethod(.catmullRom)
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
            .chartXAxis(.hidden)
            .frame(height: 150)
        }
        .card()
    }
}

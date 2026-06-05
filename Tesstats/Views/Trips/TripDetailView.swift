import SwiftUI
import MapKit
import Charts
import CoreLocation

struct TripDetailView: View {
    let drive: DriveRecord
    let units: Units

    @State private var route: MKRoute?
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    @State private var routeState: RouteState = .loading

    enum RouteState { case loading, ready, unavailable }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    routeCard
                    statsCard
                    if drive.elevationProfile.count > 1 { elevationCard }
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
        .task { await loadRoute() }
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
                Text(L("Route reconstructed from the trip's addresses (TeslaMateApi doesn't expose the raw GPS trace)."))
                    .font(.caption2).foregroundStyle(Brand.textTertiary)
            case .unavailable:
                EmptyStateView(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                               title: L("Map unavailable"),
                               message: L("Couldn't locate these addresses on the map."))
                    .frame(height: 130)
            }
        }
        .card()
    }

    @ViewBuilder
    private var routeMap: some View {
        let coords = [startCoord, endCoord].compactMap { $0 }
        Map(initialPosition: .region(region(for: coords))) {
            if let route {
                MapPolyline(route.polyline)
                    .stroke(Brand.crimson, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            } else if coords.count == 2 {
                MapPolyline(coordinates: coords)
                    .stroke(Brand.crimson.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
            }
            if let s = startCoord {
                Annotation(L("Start"), coordinate: s) { endpointDot(Brand.online) }
            }
            if let e = endCoord {
                Annotation(L("End"), coordinate: e) { endpointDot(Brand.crimson) }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func endpointDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        MKCoordinateRegion(fitting: coords.map { $0.coordinate })
    }

    private func loadRoute() async {
        guard let startName = drive.startAddress, let endName = drive.endAddress else {
            routeState = .unavailable; return
        }
        let placemarksStart = try? await CLGeocoder().geocodeAddressString(startName)
        let placemarksEnd = try? await CLGeocoder().geocodeAddressString(endName)
        guard let s = placemarksStart?.first?.location?.coordinate,
              let e = placemarksEnd?.first?.location?.coordinate else {
            routeState = .unavailable; return
        }
        startCoord = s
        endCoord = e

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: s))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: e))
        request.transportType = .automobile
        if let response = try? await MKDirections(request: request).calculate() {
            route = response.routes.first
        }
        routeState = .ready
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
        guard drive.elevationProfile.count > 1 else { return "—" }
        var gain = 0.0
        for i in 1..<drive.elevationProfile.count {
            let d = drive.elevationProfile[i] - drive.elevationProfile[i - 1]
            if d > 0 { gain += d }
        }
        return "\(Int(gain)) m"
    }

    private var elevationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Elevation"), systemImage: "mountain.2")
            Chart(Array(drive.elevationProfile.enumerated()), id: \.offset) { index, value in
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

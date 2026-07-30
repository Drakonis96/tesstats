import MapKit

extension MKCoordinateRegion {
    /// A region that comfortably fits all the given coordinates.
    init(fitting coordinates: [Coordinate]) {
        guard let first = coordinates.first else {
            self.init(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                      span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
            return
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.01))
        self.init(center: center, span: span)
    }
}

import SwiftUI

/// A map that keeps following the car.
///
/// `Map(initialPosition:)` applies its camera only on the first render, so a card built with it
/// keeps showing wherever the car was when the screen first appeared: the annotation moves with
/// the live position but the visible region never does, and the marker silently drifts
/// off-screen. Parking somewhere new then reads as "still at the previous place".
struct FollowingMap<Marker: View>: View {
    let coordinate: Coordinate
    /// Latitude/longitude delta of the visible region.
    var span: CLLocationDegrees
    @ViewBuilder var marker: () -> Marker

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) {
            Annotation("", coordinate: coordinate.clLocationCoordinate) { marker() }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onAppear { camera = region }
        .onChange(of: coordinate) { _, _ in
            withAnimation(.easeInOut(duration: 0.6)) { camera = region }
        }
    }

    private var region: MapCameraPosition {
        .region(MKCoordinateRegion(center: coordinate.clLocationCoordinate,
                                   span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
    }
}

/// A map that refits its camera whenever the coordinates it displays change.
///
/// Same trap as `FollowingMap`: with `Map(initialPosition:)` the region is set once, so
/// changing the date-range filter (or a trip's route arriving from the API after the screen
/// is already on-screen) redrew the overlays outside the visible region.
struct FittingMap<Content: MapContent>: View {
    let coordinates: [Coordinate]
    @MapContentBuilder var content: () -> Content

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) { content() }
            .onAppear { camera = region }
            .onChange(of: coordinates) { _, _ in
                withAnimation(.easeInOut(duration: 0.6)) { camera = region }
            }
    }

    private var region: MapCameraPosition { .region(MKCoordinateRegion(fitting: coordinates)) }
}

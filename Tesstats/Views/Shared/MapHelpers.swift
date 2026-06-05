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

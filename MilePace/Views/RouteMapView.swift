import SwiftUI
import MapKit
import CoreLocation

/// A saved route on a flat, muted map: the path in signal blue and a square at the start. Needs at
/// least two points; callers check before showing it.
struct RouteMapView: View {
    private struct Pin: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
    }

    private let coordinates: [CLLocationCoordinate2D]
    private let startPins: [Pin]

    init(points: [GeoPoint]) {
        let mapped = points.map { point in
            CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        }
        self.coordinates = mapped
        if let first = mapped.first {
            self.startPins = [Pin(id: 0, coordinate: first)]
        } else {
            self.startPins = []
        }
    }

    var body: some View {
        mapView
            .frame(height: 260)
            .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule))
    }

    private var mapView: some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.signal, lineWidth: 5)
            ForEach(startPins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    startMarker
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    /// Start: a 10 pt foreground square with a 1 pt background border (as on the run map).
    private var startMarker: some View {
        Rectangle()
            .fill(Theme.fg)
            .frame(width: 10, height: 10)
            .overlay(Rectangle().strokeBorder(Theme.bg, lineWidth: 1))
    }
}

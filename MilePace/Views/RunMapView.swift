import SwiftUI
import MapKit
import CoreLocation

/// Route map colored by pace relative to the run average, with start, finish and mile markers.
/// Faster is signal blue, steady is the foreground color and slower is dim.
struct RunMapView: View {
    private struct MileMarker: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
    }

    private let segments: [ColoredSegment]
    private let markers: [MileMarker]
    private let start: CLLocationCoordinate2D
    private let end: CLLocationCoordinate2D

    /// Needs at least two points; callers check before showing the map.
    init(route: [RoutePoint], averagePace: Double) {
        self.segments = RouteSegments.colored(route, averagePace: averagePace)
        self.markers = RouteSegments.mileMarkers(route).map { item in
            MileMarker(id: item.mile,
                       coordinate: CLLocationCoordinate2D(latitude: item.point.lat, longitude: item.point.lon))
        }
        let first = route.first
        let last = route.last
        self.start = CLLocationCoordinate2D(latitude: first?.lat ?? 0, longitude: first?.lon ?? 0)
        self.end = CLLocationCoordinate2D(latitude: last?.lat ?? 0, longitude: last?.lon ?? 0)
    }

    private func color(_ band: PaceBand) -> Color {
        switch band {
        case .faster: return Theme.signal
        case .steady: return Theme.fg
        case .slower: return Theme.dim
        }
    }

    private func coordinates(_ segment: ColoredSegment) -> [CLLocationCoordinate2D] {
        return segment.points.map { point in
            CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            mapView
                .frame(height: 260)
                .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule))
            legend
        }
    }

    private var mapView: some View {
        Map(initialPosition: .automatic) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: coordinates(segment))
                    .stroke(color(segment.band), lineWidth: 5)
            }
            Annotation("", coordinate: start) {
                square(Theme.fg)
            }
            Annotation("", coordinate: end) {
                square(Theme.signal)
            }
            ForEach(markers) { marker in
                Annotation("", coordinate: marker.coordinate) {
                    mileLabel(marker.id)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    /// Start and finish markers: tiny squares.
    private func square(_ fill: Color) -> some View {
        Rectangle()
            .fill(fill)
            .frame(width: 10, height: 10)
            .overlay(Rectangle().strokeBorder(Theme.bg, lineWidth: 1))
    }

    /// Mile markers: micro text in an inverted box.
    private func mileLabel(_ mile: Int) -> some View {
        Text("\(mile)")
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.bg)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.fg)
    }

    private var legend: some View {
        HStack(spacing: Theme.s3) {
            legendItem("faster", fill: Theme.signal)
            legendItem("steady", fill: Theme.fg)
            legendItem("slower", fill: Theme.dim)
            Text("than avg")
                .foregroundStyle(Theme.dim)
        }
        .font(Theme.mono(.micro))
    }

    private func legendItem(_ title: String, fill: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(fill)
                .frame(width: 12, height: 4)
            Text(title)
                .foregroundStyle(Theme.fg)
        }
    }
}

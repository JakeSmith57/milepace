import SwiftUI
import MapKit
import CoreLocation

/// Route map colored by pace relative to the run average, with start, finish and mile markers.
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
        case .faster: return .green
        case .steady: return .orange
        case .slower: return .blue
        }
    }

    private func coordinates(_ segment: ColoredSegment) -> [CLLocationCoordinate2D] {
        return segment.points.map { point in
            CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .automatic) {
                ForEach(segments) { segment in
                    MapPolyline(coordinates: coordinates(segment))
                        .stroke(color(segment.band), lineWidth: 5)
                }
                Marker("Start", systemImage: "flag", coordinate: start)
                    .tint(.green)
                Marker("Finish", systemImage: "flag.checkered", coordinate: end)
                    .tint(.red)
                ForEach(markers) { marker in
                    Annotation("", coordinate: marker.coordinate) {
                        Text("\(marker.id)")
                            .font(.caption2.bold())
                            .padding(4)
                            .background(.orange, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                legendItem("Faster", color: .green)
                legendItem("Steady", color: .orange)
                legendItem("Slower", color: .blue)
                Text("than average")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 16, height: 5)
            Text(title)
        }
    }
}

import SwiftUI
import MapKit
import CoreLocation

/// The map half of the active run screen: the route so far, the start, mile markers and you.
/// Follows your location until you pan or zoom, then offers `[ follow ]` to snap back.
struct LiveRunMapView: View {
    private struct PathPiece: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
    }

    private struct Pin: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
    }

    private let pieces: [PathPiece]
    private let startPins: [Pin]
    private let milePins: [Pin]
    private let youPins: [Pin]
    /// The route being followed, drawn thin and dim under the live track (empty when there is none).
    private let plannedPieces: [PathPiece]
    private let plannedStartPins: [Pin]

    @State private var position: MapCameraPosition = LiveRunMapView.followPosition

    private static var followPosition: MapCameraPosition {
        return .userLocation(followsHeading: false, fallback: .automatic)
    }

    init(route: [RoutePoint], lastCoordinate: CLLocationCoordinate2D?, plannedRoute: [GeoPoint] = []) {
        let plannedCoordinates = plannedRoute.map { point in
            CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        }
        if plannedCoordinates.count >= 2 {
            self.plannedPieces = [PathPiece(id: 0, coordinates: plannedCoordinates)]
            self.plannedStartPins = [Pin(id: 0, coordinate: plannedCoordinates[0])]
        } else {
            self.plannedPieces = []
            self.plannedStartPins = []
        }
        let split = LiveRouteSegments.split(route)
        var built: [PathPiece] = []
        for (index, piece) in split.enumerated() {
            built.append(PathPiece(id: index, coordinates: LiveRunMapView.coordinates(piece)))
        }
        self.pieces = built

        if let first = route.first {
            self.startPins = [Pin(id: 0, coordinate: LiveRunMapView.coordinate(first))]
        } else {
            self.startPins = []
        }
        self.milePins = RouteSegments.mileMarkers(route).map { item in
            Pin(id: item.mile, coordinate: LiveRunMapView.coordinate(item.point))
        }
        if let here = lastCoordinate {
            self.youPins = [Pin(id: 0, coordinate: here)]
        } else {
            self.youPins = []
        }
    }

    private static func coordinate(_ point: RoutePoint) -> CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    private static func coordinates(_ points: [RoutePoint]) -> [CLLocationCoordinate2D] {
        return points.map { point in
            LiveRunMapView.coordinate(point)
        }
    }

    var body: some View {
        mapView
            .overlay(alignment: .topTrailing) {
                followButton
            }
            .clipped()
    }

    private var mapView: some View {
        Map(position: $position) {
            ForEach(plannedPieces) { piece in
                MapPolyline(coordinates: piece.coordinates)
                    .stroke(Theme.dim, lineWidth: 3)
            }
            ForEach(plannedStartPins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    plannedStartMarker
                }
            }
            ForEach(pieces) { piece in
                MapPolyline(coordinates: piece.coordinates)
                    .stroke(Theme.signal, lineWidth: 6)
            }
            ForEach(startPins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    startMarker
                }
            }
            ForEach(milePins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    mileLabel(pin.id)
                }
            }
            ForEach(youPins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    youMarker
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
    }

    @ViewBuilder
    private var followButton: some View {
        if !position.followsUserLocation {
            BracketButton(title: "follow",
                          minHeight: 44,
                          fullWidth: false,
                          size: .micro) {
                position = LiveRunMapView.followPosition
            }
            .padding(Theme.s2)
        }
    }

    /// Start: a 12 pt foreground square with a 2 pt background border.
    private var startMarker: some View {
        Rectangle()
            .fill(Theme.fg)
            .frame(width: 12, height: 12)
            .overlay(Rectangle().strokeBorder(Theme.bg, lineWidth: 2))
    }

    /// Start of the followed route: a small hollow square.
    private var plannedStartMarker: some View {
        Rectangle()
            .fill(Theme.bg)
            .frame(width: 8, height: 8)
            .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: 2))
    }

    /// You: a 16 pt signal square with a 3 pt onSignal border.
    private var youMarker: some View {
        Rectangle()
            .fill(Theme.signal)
            .frame(width: 16, height: 16)
            .overlay(Rectangle().strokeBorder(Theme.onSignal, lineWidth: 3))
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
}

/// Compact readout under the live map: pace and meter on top, then distance, time and cadence.
struct LiveRunReadout: View {
    let pace: Double?
    let averagePace: Double?
    let zone: ClosedRange<Double>?
    let distanceMeters: Double
    let elapsed: Double
    let cadence: Double?

    private var cadenceValue: String? {
        guard let spm = cadence, spm.isFinite, spm > 0 else { return nil }
        return "\(Int(spm.rounded())) spm"
    }

    var body: some View {
        VStack(spacing: 0) {
            SolidRule()
            VStack(alignment: .leading, spacing: Theme.s2) {
                paceRow
                statsRow
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2)
        }
        .background(Theme.bg)
    }

    private var paceRow: some View {
        HStack(alignment: .center, spacing: Theme.s3) {
            HStack(alignment: .lastTextBaseline, spacing: Theme.s1) {
                Text(formatPace(secondsPerMile: pace))
                    .font(Theme.mono(.title))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("/mi")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            meter
        }
    }

    @ViewBuilder
    private var meter: some View {
        if let zone = zone {
            PaceMeter(pace: pace, zone: zone, compact: true)
                .frame(maxWidth: 170)
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: Theme.s2) {
            stat(value: "\(formatMiles(distanceMeters)) mi", label: "dist")
            stat(value: formatDuration(elapsed), label: "time")
            if let spm = cadenceValue {
                stat(value: spm, label: "cadence")
            } else {
                stat(value: formatPace(secondsPerMile: averagePace), label: "avg /mi")
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

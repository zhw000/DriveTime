import MapKit
import SwiftUI

struct MapCanvasView: View {
    var plan: RoutePlan?
    var showTrafficLayer: Bool
    var showsUserLocation: Bool
    @Binding var camera: MapCameraPosition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedRoute: RouteAlternative? {
        plan?.selectedAlternative
    }

    var body: some View {
        Map(position: $camera, interactionModes: .all) {
            if showsUserLocation {
                UserAnnotation()
            }

            if let plan {
                ForEach(plan.alternatives) { route in
                    if route.hasGeometry, route.id != plan.selectedRouteID {
                        MapPolyline(coordinates: route.polyline.map(\.appleMapCoordinate))
                            .stroke(
                                DriveTimeTheme.routeAlternative.opacity(0.55),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                    }
                }

                if let selected = selectedRoute, selected.hasGeometry {
                    MapPolyline(coordinates: selected.polyline.map(\.appleMapCoordinate))
                        .stroke(
                            DriveTimeTheme.accent.opacity(0.92),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )
                    if let traffic = selected.traffic, traffic.hasGeometry {
                        ForEach(traffic.segments.filter(\.hasGeometry)) { segment in
                            MapPolyline(coordinates: segment.coordinates.map(\.appleMapCoordinate))
                                .stroke(
                                    segment.level.color,
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                                )
                        }
                    }
                }

                Annotation("起点", coordinate: plan.origin.coordinate.appleMapCoordinate, anchor: .center) {
                    mapMarker(text: "起", color: DriveTimeTheme.origin)
                }
                .annotationTitles(.hidden)

                Annotation("终点", coordinate: plan.destination.coordinate.appleMapCoordinate, anchor: .center) {
                    mapMarker(text: "终", color: DriveTimeTheme.destination)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(
            .standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: showTrafficLayer
            )
        )
        .mapControls {
            MapCompass()
        }
        .onAppear {
            fitToCurrentPlan(animated: false)
        }
        .onChange(of: plan?.id) { _, _ in
            fitToCurrentPlan(animated: !reduceMotion)
        }
        .onChange(of: plan?.selectedRouteID) { _, _ in
            fitToCurrentPlan(animated: !reduceMotion)
        }
        .accessibilityLabel(plan == nil ? "地图" : "从\(plan?.origin.name ?? "起点")到\(plan?.destination.name ?? "终点")的路线地图")
    }

    private func mapMarker(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    private func fitToCurrentPlan(animated: Bool) {
        guard let plan else { return }
        let selected = plan.selectedAlternative
        let coordinates = selected.hasGeometry
            ? selected.polyline.map(\.appleMapCoordinate)
            : [
                plan.origin.coordinate.appleMapCoordinate,
                plan.destination.coordinate.appleMapCoordinate
            ]
        guard let region = MapViewportRegion.fitting(coordinates: coordinates) else { return }
        let cameraPosition = MapCameraPosition.region(region)
        if animated {
            withAnimation(.easeInOut(duration: 0.55)) {
                camera = cameraPosition
            }
        } else {
            camera = cameraPosition
        }
    }
}

enum MapViewportRegion {
    static func fitting(
        coordinates: [CLLocationCoordinate2D],
        minimumSpanMeters: Double = 1_600
    ) -> MKCoordinateRegion? {
        let valid = coordinates.filter(\.isValidMapCoordinate)
        guard !valid.isEmpty else { return nil }
        if valid.count == 1 {
            return MKCoordinateRegion(
                center: valid[0],
                latitudinalMeters: minimumSpanMeters * 2,
                longitudinalMeters: minimumSpanMeters * 2
            )
        }

        var minLat = valid[0].latitude
        var maxLat = valid[0].latitude
        var minLon = valid[0].longitude
        var maxLon = valid[0].longitude
        for coordinate in valid.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latMeters = max((maxLat - minLat) * 111_000 * 1.35, minimumSpanMeters)
        let lonMeters = max(
            (maxLon - minLon) * 111_000 * cos(center.latitude * .pi / 180) * 1.35,
            minimumSpanMeters
        )
        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: latMeters,
            longitudinalMeters: lonMeters
        )
    }
}

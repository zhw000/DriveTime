import CoreLocation
import Foundation
import MapKit

struct AppleMapRoutingProvider: RoutingProvider {
    let providerID: RouteProviderID = .appleMaps
    let capabilities: ProviderCapabilities = .appleMaps

    func searchPlaces(query: String, near: GeoCoordinate?) async throws -> [LocationResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let near {
            let center = near.appleMapCoordinate
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000
            )
        }

        let response = try await performLocalSearch(request)
        return response.mapItems.compactMap { mapItem in
            AppleMapItemMapper.location(from: mapItem)
        }
    }

    func calculateRoutes(for request: RouteRequest) async throws -> ProviderRouteResult {
        guard !request.origin.isSamePlace(as: request.destination) else {
            throw RouteProviderError.sameLocation
        }

        let directionsRequest = MKDirections.Request()
        directionsRequest.source = makeMapItem(for: request.origin)
        directionsRequest.destination = makeMapItem(for: request.destination)
        directionsRequest.transportType = .automobile
        directionsRequest.requestsAlternateRoutes = true
        // Deliberately no departureDate: MapKit does not guarantee that a
        // future-dated result is a traffic prediction. DriveTime labels future
        // departures as projected current conditions instead of inventing one.

        let response = try await performDirections(directionsRequest)
        let fetchedAt = Date()
        guard !response.routes.isEmpty else { throw RouteProviderError.noRoute }

        let isChinaRoute = request.origin.coordinate.isInMainlandChina
            || request.destination.coordinate.isInMainlandChina
        let datum: GeoCoordinate.Datum = isChinaRoute ? .gcj02 : .wgs84

        var alternatives: [RouteAlternative] = []
        for (index, route) in response.routes.enumerated() {
            guard route.expectedTravelTime > 0 else { continue }
            let geometry = Self.coordinates(for: route.polyline, datum: datum)
            var notes = route.advisoryNotices
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if route.hasTolls {
                notes.append("该路线包含收费路段；Apple 地图未提供过路费金额。")
            }
            let steps = route.steps.enumerated().map { stepIndex, step in
                RouteStep(
                    id: stepIndex,
                    instruction: step.instructions.isEmpty ? "继续行驶" : step.instructions,
                    distanceMeters: step.distance
                )
            }
            let title: String
            if index == 0 {
                title = "推荐路线"
            } else if !route.name.isEmpty {
                title = route.name
            } else {
                title = "备选路线 \(index + 1)"
            }
            alternatives.append(
                RouteAlternative(
                    title: title,
                    distanceMeters: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    polyline: geometry,
                    steps: steps,
                    traffic: nil,
                    tollAmountYuan: nil,
                    tollDistanceMeters: nil,
                    tollRoads: [],
                    hasTolls: route.hasTolls,
                    isRecommended: index == 0,
                    notes: Array(notes.prefix(4))
                )
            )
        }
        guard !alternatives.isEmpty else { throw RouteProviderError.noRoute }

        return ProviderRouteResult(
            provider: .appleMaps,
            alternatives: alternatives,
            fetchedAt: fetchedAt,
            forecastAvailability: .currentConditions
        )
    }

    func estimateETA(for request: RouteRequest) async throws -> ETAResult {
        guard !request.origin.isSamePlace(as: request.destination) else {
            throw RouteProviderError.sameLocation
        }
        let directionsRequest = MKDirections.Request()
        directionsRequest.source = makeMapItem(for: request.origin)
        directionsRequest.destination = makeMapItem(for: request.destination)
        directionsRequest.transportType = .automobile

        let response = try await performETA(directionsRequest)
        return ETAResult(
            provider: .appleMaps,
            distanceMeters: response.distance,
            expectedTravelTime: response.expectedTravelTime,
            departureAt: request.departureAt,
            fetchedAt: Date(),
            hasRouteGeometry: false
        )
    }

    // MARK: - Mapping

    private func makeMapItem(for location: LocationResult) -> MKMapItem {
        let coordinate = location.coordinate.appleMapCoordinate
        return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }

    private static func coordinates(for polyline: MKPolyline, datum: GeoCoordinate.Datum) -> [GeoCoordinate] {
        let count = polyline.pointCount
        guard count > 1 else { return [] }
        var coordinates = Array(
            repeating: CLLocationCoordinate2D(),
            count: count
        )
        polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: count)
        )
        var result: [GeoCoordinate] = []
        for coordinate in coordinates where coordinate.isValidMapCoordinate {
            if let last = result.last,
               abs(last.latitude - coordinate.latitude) < 1e-9,
               abs(last.longitude - coordinate.longitude) < 1e-9 {
                continue
            }
            result.append(GeoCoordinate(coordinate, datum: datum))
        }
        return result.count >= 2 ? result : []
    }

    // MARK: - Async MapKit bridges

    private func performLocalSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        let operation = MKLocalSearch(request: request)
        let box = LocalSearchBox(operation: operation)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start { response, error in
                    if let response {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: Self.mapError(error))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    private func performDirections(_ request: MKDirections.Request) async throws -> MKDirections.Response {
        let operation = MKDirections(request: request)
        let box = DirectionsBox(operation: operation)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.calculate { response, error in
                    if let response {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: Self.mapError(error))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    private func performETA(_ request: MKDirections.Request) async throws -> MKDirections.ETAResponse {
        let operation = MKDirections(request: request)
        let box = DirectionsBox(operation: operation)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.calculateETA { response, error in
                    if let response {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: Self.mapError(error))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    private static func mapError(_ error: Error?) -> RouteProviderError {
        guard let error else { return .unknown }
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        if nsError.domain == MKError.errorDomain,
           let code = MKError.Code(rawValue: UInt(nsError.code)) {
            switch code {
            case .loadingThrottled:
                return .rateLimited(retryAfter: nil)
            case .placemarkNotFound, .directionsNotFound:
                return .noRoute
            case .serverFailure:
                return .serverUnavailable
            case .decodingFailed:
                return .decodingFailed
            case .unknown:
                return .providerUnavailable("Apple 地图")
            @unknown default:
                return .providerUnavailable("Apple 地图")
            }
        }
        return RouteProviderError.map(error)
    }
}

private final class LocalSearchBox: @unchecked Sendable {
    private let operation: MKLocalSearch

    init(operation: MKLocalSearch) {
        self.operation = operation
    }

    func cancel() {
        operation.cancel()
    }
}

private final class DirectionsBox: @unchecked Sendable {
    private let operation: MKDirections

    init(operation: MKDirections) {
        self.operation = operation
    }

    func cancel() {
        operation.cancel()
    }
}

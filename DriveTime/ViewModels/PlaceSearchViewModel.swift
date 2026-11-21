import CoreLocation
import Foundation
import MapKit
import Observation

struct PlaceSuggestion: Identifiable {
    enum Payload {
        case location(LocationResult)
        case appleCompletion(MKLocalSearchCompletion)
    }

    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let payload: Payload

    var location: LocationResult? {
        if case .location(let location) = payload { return location }
        return nil
    }
}

struct PlaceSearchState {
    var query: String
    var suggestions: [PlaceSuggestion]
    var isLoading: Bool
    var error: RouteProviderError?
}

@MainActor
protocol PlaceSearchEngine: AnyObject {
    var providerLabel: String { get }
    var onStateChange: ((PlaceSearchState) -> Void)? { get set }
    func update(query: String, near: GeoCoordinate?)
    func resolve(_ suggestion: PlaceSuggestion) async throws -> LocationResult
    func cancel()
}

@MainActor
final class ApplePlaceSearchEngine: NSObject, PlaceSearchEngine, MKLocalSearchCompleterDelegate {
    let providerLabel = "Apple 地图"
    var onStateChange: ((PlaceSearchState) -> Void)?

    private let completer = MKLocalSearchCompleter()
    private var lastQuery = ""
    private var generation = 0
    private var fallbackLoadingTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, near: GeoCoordinate?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastQuery = trimmed
        generation += 1
        let currentGeneration = generation
        fallbackLoadingTask?.cancel()
        guard !trimmed.isEmpty else {
            onStateChange?(PlaceSearchState(query: "", suggestions: [], isLoading: false, error: nil))
            return
        }
        if let near {
            let center = near.appleMapCoordinate
            completer.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 80_000,
                longitudinalMeters: 80_000
            )
        }
        onStateChange?(PlaceSearchState(
            query: trimmed,
            suggestions: [],
            isLoading: true,
            error: nil
        ))
        completer.queryFragment = trimmed
        fallbackLoadingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled, self.generation == currentGeneration else { return }
            self.onStateChange?(PlaceSearchState(
                query: self.lastQuery,
                suggestions: [],
                isLoading: false,
                error: nil
            ))
        }
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> LocationResult {
        switch suggestion.payload {
        case .location(let location):
            return location
        case .appleCompletion(let completion):
            return try await resolve(completion)
        }
    }

    func cancel() {
        fallbackLoadingTask?.cancel()
        completer.queryFragment = ""
        lastQuery = ""
        generation += 1
    }

    private func resolve(_ completion: MKLocalSearchCompletion) async throws -> LocationResult {
        let request = MKLocalSearch.Request(completion: completion)
        let operation = MKLocalSearch(request: request)
        let box = PlaceSearchOperationBox(operation: operation)
        let response = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKLocalSearch.Response, Error>) in
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
        guard let mapItem = response.mapItems.first,
              let location = AppleMapItemMapper.location(from: mapItem) else {
            throw RouteProviderError.noRoute
        }
        return location
    }

    private static func mapError(_ error: Error?) -> RouteProviderError {
        guard let error else { return .unknown }
        if error is CancellationError { return .cancelled }
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
                return .providerUnavailable("Apple 地点搜索")
            @unknown default:
                return .providerUnavailable("Apple 地点搜索")
            }
        }
        return RouteProviderError.map(error)
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        fallbackLoadingTask?.cancel()
        guard !lastQuery.isEmpty else { return }
        let suggestions = completer.results.prefix(12).enumerated().map { index, completion in
            PlaceSuggestion(
                id: "apple-completion-\(index)-\(completion.title)|\(completion.subtitle)",
                title: completion.title,
                subtitle: completion.subtitle,
                iconName: "mappin.and.ellipse",
                payload: .appleCompletion(completion)
            )
        }
        onStateChange?(PlaceSearchState(
            query: lastQuery,
            suggestions: suggestions,
            isLoading: false,
            error: nil
        ))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        fallbackLoadingTask?.cancel()
        onStateChange?(PlaceSearchState(
            query: lastQuery,
            suggestions: [],
            isLoading: false,
            error: Self.mapError(error)
        ))
    }
}

@MainActor
final class AMapPlaceSearchEngine: PlaceSearchEngine {
    let providerLabel = "高德地图"
    var onStateChange: ((PlaceSearchState) -> Void)?

    private let provider: any RoutingProvider
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    init(provider: any RoutingProvider) {
        self.provider = provider
    }

    func update(query: String, near: GeoCoordinate?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        searchTask = nil
        generation += 1
        let currentGeneration = generation
        guard !trimmed.isEmpty else {
            onStateChange?(PlaceSearchState(query: "", suggestions: [], isLoading: false, error: nil))
            return
        }
        onStateChange?(PlaceSearchState(
            query: trimmed,
            suggestions: [],
            isLoading: true,
            error: nil
        ))

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                let places = try await self.provider.searchPlaces(query: trimmed, near: near)
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                let suggestions = places.enumerated().map { index, place in
                    PlaceSuggestion(
                        id: "amap-\(index)-\(place.id)",
                        title: place.name,
                        subtitle: place.subtitle,
                        iconName: "mappin.and.ellipse",
                        payload: .location(place)
                    )
                }
                self.onStateChange?(PlaceSearchState(
                    query: trimmed,
                    suggestions: suggestions,
                    isLoading: false,
                    error: nil
                ))
            } catch is CancellationError {
                return
            } catch {
                guard self.generation == currentGeneration, !Task.isCancelled else { return }
                let mapped = RouteProviderError.map(error)
                self.onStateChange?(PlaceSearchState(
                    query: trimmed,
                    suggestions: [],
                    isLoading: false,
                    error: mapped
                ))
            }
        }
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> LocationResult {
        guard let location = suggestion.location else {
            throw RouteProviderError.invalidResponse("高德地点缺少坐标")
        }
        return location
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        generation += 1
    }
}

@MainActor
enum PlaceSearchEngineFactory {
    static func make(for settings: AppSettings) -> any PlaceSearchEngine {
        if settings.preferredProvider == .amap,
           let configuration = settings.proxyConfiguration {
            return AMapPlaceSearchEngine(
                provider: AMapRoutingProvider(configuration: configuration)
            )
        }
        return ApplePlaceSearchEngine()
    }
}

@MainActor
@Observable
final class PlaceSearchViewModel {
    let endpoint: TripEndpoint
    let engine: any PlaceSearchEngine
    let locationService: LocationService

    var query = ""
    private(set) var suggestions: [PlaceSuggestion] = []
    private(set) var isLoading = false
    private(set) var isResolving = false
    private(set) var isLocating = false
    private(set) var errorMessage: String?
    private(set) var authorizationStatus: CLAuthorizationStatus

    init(
        endpoint: TripEndpoint,
        engine: any PlaceSearchEngine,
        locationService: LocationService
    ) {
        self.endpoint = endpoint
        self.engine = engine
        self.locationService = locationService
        self.authorizationStatus = locationService.authorizationStatus
        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            let trimmed = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard state.query == trimmed else { return }
            self.suggestions = state.suggestions
            self.isLoading = state.isLoading
            self.errorMessage = state.error?.userMessage
        }
    }

    var providerLabel: String { engine.providerLabel }

    var permissionExplanation: String {
        locationService.permissionExplanation
    }

    func updateQuery(_ value: String) {
        query = value
        errorMessage = nil
        engine.update(query: value, near: nil)
    }

    func select(_ suggestion: PlaceSuggestion) async -> LocationResult? {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }
        do {
            return try await engine.resolve(suggestion)
        } catch {
            errorMessage = RouteProviderError.map(error).userMessage
            return nil
        }
    }

    func useCurrentLocation() async -> LocationResult? {
        isLocating = true
        errorMessage = nil
        defer {
            isLocating = false
            authorizationStatus = locationService.authorizationStatus
        }
        do {
            let location = try await locationService.requestCurrentLocation()
            let coordinate = GeoCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                datum: .wgs84
            )
            return LocationResult(
                name: "当前位置",
                city: nil,
                district: nil,
                address: String(format: "GPS %.5f, %.5f", coordinate.latitude, coordinate.longitude),
                category: nil,
                coordinate: coordinate,
                provider: .appleMaps,
                providerPlaceID: nil,
                source: .currentLocation
            )
        } catch let error as LocationServiceError {
            errorMessage = error.providerError.userMessage
            return nil
        } catch {
            errorMessage = RouteProviderError.map(error).userMessage
            return nil
        }
    }

    func refreshPermission() {
        locationService.refreshAuthorizationStatus()
        authorizationStatus = locationService.authorizationStatus
    }

    func cancel() {
        engine.cancel()
    }
}

private final class PlaceSearchOperationBox: @unchecked Sendable {
    private let operation: MKLocalSearch

    init(operation: MKLocalSearch) {
        self.operation = operation
    }

    func cancel() {
        operation.cancel()
    }
}

import CoreLocation
import Foundation

struct LocationResult: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var city: String?
    var district: String?
    var address: String?
    var category: String?
    var coordinate: GeoCoordinate
    var provider: RouteProviderID
    var providerPlaceID: String?
    var source: LocationSource
    var createdAt: Date

    init(
        id: String? = nil,
        name: String,
        city: String? = nil,
        district: String? = nil,
        address: String? = nil,
        category: String? = nil,
        coordinate: GeoCoordinate,
        provider: RouteProviderID,
        providerPlaceID: String? = nil,
        source: LocationSource,
        createdAt: Date = Date()
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? "未命名地点" : trimmedName
        self.city = city?.nilIfBlank
        self.district = district?.nilIfBlank
        self.address = address?.nilIfBlank
        self.category = category?.nilIfBlank
        self.coordinate = coordinate
        self.provider = provider
        self.providerPlaceID = providerPlaceID?.nilIfBlank
        self.source = source
        self.createdAt = createdAt
        self.id = id ?? Self.makeID(
            provider: provider,
            providerPlaceID: providerPlaceID,
            coordinate: coordinate,
            name: self.name
        )
    }

    private static func makeID(
        provider: RouteProviderID,
        providerPlaceID: String?,
        coordinate: GeoCoordinate,
        name: String
    ) -> String {
        if let providerPlaceID, !providerPlaceID.isEmpty {
            return "\(provider.rawValue):\(providerPlaceID)"
        }
        return String(
            format: "%@:%.5f,%.5f:%@",
            provider.rawValue,
            coordinate.latitude,
            coordinate.longitude,
            name
        )
    }

    var subtitle: String {
        let components = [district, city, address]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != name }
        var seen = Set<String>()
        return components.filter { seen.insert($0).inserted }.joined(separator: " · ")
    }

    var cityLine: String? {
        let components = [city, district]
            .compactMap { $0?.nilIfBlank }
            .filter { $0 != name }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var coordinateText: String {
        coordinate.shortCoordinateText
    }

    func isSamePlace(as other: LocationResult, toleranceMeters: CLLocationDistance = 30) -> Bool {
        if let lhs = providerPlaceID, let rhs = other.providerPlaceID,
           provider == other.provider, lhs == rhs {
            return true
        }
        return coordinate.groundDistance(to: other.coordinate) <= toleranceMeters
    }

    /// Snapshot used for requests and history; removes transient search fields
    /// while keeping the provider POI identity.
    func snapshot(at date: Date = Date()) -> LocationResult {
        LocationResult(
            id: id,
            name: name,
            city: city,
            district: district,
            address: address,
            category: category,
            coordinate: coordinate,
            provider: provider,
            providerPlaceID: providerPlaceID,
            source: source,
            createdAt: createdAt
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct RouteRequest: Hashable, Sendable {
    var origin: LocationResult
    var destination: LocationResult
    var strategy: RouteStrategy
    /// The instant the user intends to leave. For an immediate query this is
    /// the exact query-start snapshot, not a time re-read while rendering.
    var departureAt: Date
    /// The instant this request was created.
    var requestedAt: Date

    var isFutureDeparture: Bool {
        departureAt.timeIntervalSince(requestedAt) > 120
    }
}

struct RouteStep: Identifiable, Hashable, Codable, Sendable {
    var id: Int
    var instruction: String
    var roadName: String?
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval?
    var maneuver: String?

    init(
        id: Int,
        instruction: String,
        roadName: String? = nil,
        distanceMeters: Double = 0,
        expectedTravelTime: TimeInterval? = nil,
        maneuver: String? = nil
    ) {
        self.id = id
        self.instruction = instruction
        self.roadName = roadName
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.maneuver = maneuver
    }
}

struct TrafficInformation: Hashable, Codable, Sendable {
    enum Level: Int, Codable, CaseIterable, Sendable {
        case unknown = 0
        case smooth = 1
        case slow = 2
        case congested = 3
        case severelyCongested = 4

        var displayName: String {
            switch self {
            case .unknown: "未知"
            case .smooth: "畅通"
            case .slow: "缓行"
            case .congested: "拥堵"
            case .severelyCongested: "严重拥堵"
            }
        }

        static func fromAMapStatus(_ value: String) -> Level {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains("严重拥堵") { return .severelyCongested }
            if text.contains("拥堵") { return .congested }
            if text.contains("缓行") { return .slow }
            if text.contains("畅通") { return .smooth }
            return .unknown
        }
    }

    struct Segment: Identifiable, Hashable, Codable, Sendable {
        var id: Int
        var level: Level
        var coordinates: [GeoCoordinate]
        var lengthMeters: Double?

        var hasGeometry: Bool { coordinates.count >= 2 }
    }

    var segments: [Segment]
    var fetchedAt: Date
    /// Set by a provider only when it states that the traffic inventory covers
    /// the whole route. Nil means unknown, not complete.
    var isComplete: Bool?
    var sourceLabel: String

    var hasUsableData: Bool {
        segments.contains { $0.level != .unknown }
    }

    var hasGeometry: Bool {
        segments.contains(where: \.hasGeometry)
    }

    func totalMeters(for level: TrafficInformation.Level) -> Double {
        segments.filter { $0.level == level }.reduce(0) { $0 + ($1.lengthMeters ?? 0) }
    }

    var knownLengthMeters: Double {
        segments.reduce(0) { total, segment in
            guard segment.level != .unknown else { return total }
            return total + (segment.lengthMeters ?? 0)
        }
    }
}

struct RouteAlternative: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var providerRouteIdentifier: String?
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval
    var polyline: [GeoCoordinate]
    var steps: [RouteStep]
    var traffic: TrafficInformation?
    var tollAmountYuan: Double?
    var tollDistanceMeters: Double?
    var tollRoads: [String]
    /// Nil means the provider did not state whether the route has tolls.
    var hasTolls: Bool?
    var isRecommended: Bool
    var notes: [String]

    init(
        id: UUID = UUID(),
        title: String? = nil,
        providerRouteIdentifier: String? = nil,
        distanceMeters: Double,
        expectedTravelTime: TimeInterval,
        polyline: [GeoCoordinate] = [],
        steps: [RouteStep] = [],
        traffic: TrafficInformation? = nil,
        tollAmountYuan: Double? = nil,
        tollDistanceMeters: Double? = nil,
        tollRoads: [String] = [],
        hasTolls: Bool? = nil,
        isRecommended: Bool = false,
        notes: [String] = []
    ) {
        self.id = id
        self.title = title ?? "推荐路线"
        self.providerRouteIdentifier = providerRouteIdentifier
        self.distanceMeters = max(0, distanceMeters)
        self.expectedTravelTime = max(0, expectedTravelTime)
        self.polyline = polyline
        self.steps = steps
        self.traffic = traffic
        self.tollAmountYuan = tollAmountYuan
        self.tollDistanceMeters = tollDistanceMeters
        self.tollRoads = tollRoads
        self.hasTolls = hasTolls
        self.isRecommended = isRecommended
        self.notes = notes
    }

    var hasGeometry: Bool { polyline.count >= 2 }

    var arrivalDate: Date {
        Date(timeIntervalSince1970: 0).addingTimeInterval(expectedTravelTime)
    }

    func travelTimeDifference(from other: RouteAlternative) -> TimeInterval {
        expectedTravelTime - other.expectedTravelTime
    }

    func distanceDifference(from other: RouteAlternative) -> Double {
        distanceMeters - other.distanceMeters
    }
}

struct ProviderRouteResult: Hashable, Sendable {
    var provider: RouteProviderID
    var alternatives: [RouteAlternative]
    var fetchedAt: Date
    var forecastAvailability: ForecastAvailability
    var notices: [String]

    init(
        provider: RouteProviderID,
        alternatives: [RouteAlternative],
        fetchedAt: Date,
        forecastAvailability: ForecastAvailability = .currentConditions,
        notices: [String] = []
    ) {
        self.provider = provider
        self.alternatives = alternatives
        self.fetchedAt = fetchedAt
        self.forecastAvailability = forecastAvailability
        self.notices = notices
    }
}

struct RoutePlan: Identifiable, Hashable, Sendable {
    var id: UUID
    var provider: RouteProviderID
    var origin: LocationResult
    var destination: LocationResult
    var strategy: RouteStrategy
    var requestedDepartureAt: Date
    var requestedAt: Date
    var fetchedAt: Date
    var alternatives: [RouteAlternative]
    var selectedRouteID: UUID
    var forecastAvailability: ForecastAvailability
    var dataKind: RouteDataKind
    var notices: [String]

    init(
        id: UUID = UUID(),
        provider: RouteProviderID,
        origin: LocationResult,
        destination: LocationResult,
        strategy: RouteStrategy,
        requestedDepartureAt: Date,
        requestedAt: Date,
        fetchedAt: Date,
        alternatives: [RouteAlternative],
        selectedRouteID: UUID? = nil,
        forecastAvailability: ForecastAvailability,
        dataKind: RouteDataKind = .live,
        notices: [String] = []
    ) {
        precondition(!alternatives.isEmpty, "RoutePlan requires at least one route")
        self.id = id
        self.provider = provider
        self.origin = origin
        self.destination = destination
        self.strategy = strategy
        self.requestedDepartureAt = requestedDepartureAt
        self.requestedAt = requestedAt
        self.fetchedAt = fetchedAt
        self.alternatives = alternatives
        self.selectedRouteID = selectedRouteID ?? alternatives[0].id
        self.forecastAvailability = forecastAvailability
        self.dataKind = dataKind
        self.notices = notices
    }

    var selectedAlternative: RouteAlternative {
        alternatives.first(where: { $0.id == selectedRouteID }) ?? alternatives[0]
    }

    var recommendedAlternative: RouteAlternative {
        alternatives.first(where: \.isRecommended) ?? alternatives[0]
    }

    var arrivalDate: Date {
        requestedDepartureAt.addingTimeInterval(selectedAlternative.expectedTravelTime)
    }

    var isHistorical: Bool { dataKind == .historical }

    var usesProjectedTraffic: Bool {
        forecastAvailability == .projectedFromCurrent
    }

    mutating func selectRoute(id: UUID) {
        guard alternatives.contains(where: { $0.id == id }) else { return }
        selectedRouteID = id
    }

    func replacing(selectedRouteID: UUID) -> RoutePlan {
        var copy = self
        copy.selectRoute(id: selectedRouteID)
        return copy
    }
}

struct ETAResult: Hashable, Sendable {
    var provider: RouteProviderID
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval
    var departureAt: Date
    var fetchedAt: Date
    /// A pure ETA query has no route geometry. Never render this as a route.
    var hasRouteGeometry: Bool
}

struct SavedRouteSnapshot {
    var origin: LocationResult
    var destination: LocationResult
    var provider: RouteProviderID
    var strategy: RouteStrategy
    var departureAt: Date
    var queriedAt: Date
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval
    var tollAmountYuan: Double?
    var arrivalAt: Date
    var destinationName: String
}

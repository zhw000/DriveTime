import AppIntents
import Foundation

struct SiriSettingsSnapshot: Sendable {
    var preference: ProviderPreference
    var strategy: RouteStrategy
    var proxy: AMapProxyConfiguration?
    var distanceUnit: DistanceUnit
    var timeFormat: TimeFormatPreference

    @MainActor
    init(settings: AppSettings) {
        self.preference = settings.preferredProvider
        self.strategy = settings.defaultStrategy
        self.proxy = settings.proxyConfiguration
        self.distanceUnit = settings.distanceUnit
        self.timeFormat = settings.timeFormat
    }

    init(
        preference: ProviderPreference,
        strategy: RouteStrategy,
        proxy: AMapProxyConfiguration?,
        distanceUnit: DistanceUnit,
        timeFormat: TimeFormatPreference
    ) {
        self.preference = preference
        self.strategy = strategy
        self.proxy = proxy
        self.distanceUnit = distanceUnit
        self.timeFormat = timeFormat
    }
}

struct SiriRouteSummary: Sendable {
    let originName: String
    let destinationName: String
    let expectedTravelTime: TimeInterval
    let distanceMeters: Double
    let departureDate: Date
    let arrivalDate: Date
    let provider: RouteProviderID
    let distanceUnit: DistanceUnit
    let displayFormatter: DateDisplayFormatter
    let notice: String?

    var formattedDuration: String {
        TravelTimeFormatter.string(from: expectedTravelTime)
    }

    var formattedDistance: String {
        DistanceFormatter.string(fromMeters: distanceMeters, unit: distanceUnit)
    }

    var formattedArrival: String {
        displayFormatter.relativeArrivalString(
            arrival: arrivalDate,
            relativeTo: departureDate
        )
    }

    var dialogText: String {
        var text = "从\(originName)到\(destinationName)，预计\(formattedDuration)，"
            + "\(formattedArrival)到达，全程\(formattedDistance)。"
        if let notice, !notice.isEmpty {
            text += " \(notice)"
        }
        return text
    }
}

enum SiriRouteError: Error, Equatable, Sendable, CustomLocalizedStringResourceConvertible {
    case placeNotFound
    case sameLocation
    case missingConfiguration
    case unauthorized
    case noRoute
    case unavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .placeNotFound:
            return "没有找到这个地点，请说得更具体一些。"
        case .sameLocation:
            return "起点和终点太近了，请换一个目的地。"
        case .missingConfiguration:
            return "高德地图尚未配置，请打开 DriveTime 设置代理地址，或切换到 Apple 地图。"
        case .unauthorized:
            return "地图服务鉴权失败，请打开 DriveTime 检查代理设置。"
        case .noRoute:
            return "没有找到可用的驾车路线。"
        case .unavailable:
            return "暂时无法获取车程，请检查网络或地图服务设置后再试。"
        }
    }

    static func map(_ error: Error) -> SiriRouteError {
        guard let providerError = error as? RouteProviderError else {
            return .unavailable
        }
        switch providerError {
        case .missingConfiguration(_):
            return .missingConfiguration
        case .unauthorized:
            return .unauthorized
        case .noRoute:
            return .noRoute
        default:
            return .unavailable
        }
    }
}

/// Headless query pipeline for Siri / Shortcuts. It resolves place names through
/// Apple MapKit search, then uses the same provider resolver and service
/// selection as the in-app planner. It never substitutes a fake route.
struct SiriRouteQueryService: Sendable {
    typealias PlaceSearch = @Sendable (String) async throws -> [LocationResult]

    private let settings: SiriSettingsSnapshot
    private let resolver: any RoutingProviderResolving
    private let searchPlaces: PlaceSearch
    private let now: @Sendable () -> Date

    init(
        settings: SiriSettingsSnapshot,
        resolver: any RoutingProviderResolving,
        now: @escaping @Sendable () -> Date = Date.init,
        searchPlaces: @escaping PlaceSearch
    ) {
        self.settings = settings
        self.resolver = resolver
        self.searchPlaces = searchPlaces
        self.now = now
    }

    @MainActor
    static func live() -> SiriRouteQueryService {
        let appSettings = AppSettings()
        let snapshot = SiriSettingsSnapshot(settings: appSettings)
        let appleSearch = AppleMapRoutingProvider()
        return SiriRouteQueryService(
            settings: snapshot,
            resolver: DefaultRoutingProviderResolver(),
            searchPlaces: { query in
                try await appleSearch.searchPlaces(query: query, near: nil)
            }
        )
    }

    func query(originText: String, destinationText: String) async throws -> SiriRouteSummary {
        let originQuery = originText.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationQuery = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originQuery.isEmpty, !destinationQuery.isEmpty else {
            throw SiriRouteError.placeNotFound
        }

        async let originResultsTask = searchPlaces(originQuery)
        async let destinationResultsTask = searchPlaces(destinationQuery)
        let originResults: [LocationResult]
        let destinationResults: [LocationResult]
        do {
            (originResults, destinationResults) = try await (
                originResultsTask,
                destinationResultsTask
            )
        } catch {
            AppLog.routing.error(
                "Siri place search failed: \(String(describing: error), privacy: .public)"
            )
            throw SiriRouteError.unavailable
        }

        guard let origin = originResults.first else {
            throw SiriRouteError.placeNotFound
        }
        guard let destination = destinationResults.first else {
            throw SiriRouteError.placeNotFound
        }
        guard !origin.isSamePlace(as: destination) else {
            throw SiriRouteError.sameLocation
        }

        let departureDate = now()
        let request = RouteRequest(
            origin: origin,
            destination: destination,
            strategy: settings.strategy,
            departureAt: departureDate,
            requestedAt: departureDate
        )

        let resolution: ProviderResolution
        do {
            resolution = try resolver.resolve(
                preference: settings.preference,
                origin: origin.coordinate,
                destination: destination.coordinate,
                proxy: settings.proxy
            )
        } catch {
            throw SiriRouteError.map(error)
        }

        var effectiveStrategy = settings.strategy
        var notice: String?
        if !resolution.provider.capabilities.strategies.contains(effectiveStrategy) {
            effectiveStrategy = .recommended
            notice = "当前地图服务仅支持智能推荐。"
        }
        var effectiveRequest = request
        effectiveRequest.strategy = effectiveStrategy

        let result: ProviderRouteResult
        do {
            result = try await resolution.provider.calculateRoutes(for: effectiveRequest)
        } catch let primaryError as RouteProviderError {
            guard !primaryError.isCancellation,
                  let fallback = resolution.fallback else {
                throw SiriRouteError.map(primaryError)
            }
            var fallbackRequest = effectiveRequest
            fallbackRequest.strategy = .recommended
            do {
                result = try await fallback.calculateRoutes(for: fallbackRequest)
            } catch {
                throw SiriRouteError.map(error)
            }
            notice = joinNotices([notice, "高德地图暂不可用，已改用 Apple 地图。"])
            effectiveStrategy = .recommended
        } catch {
            throw SiriRouteError.map(error)
        }

        guard let route = result.alternatives.first(where: \.isRecommended)
            ?? result.alternatives.first else {
            throw SiriRouteError.noRoute
        }
        let displayFormatter = DateDisplayFormatter(timeFormat: settings.timeFormat)
        var allNotices: [String?] = [notice]
        allNotices.append(contentsOf: result.notices.prefix(1).map(Optional.some))
        return SiriRouteSummary(
            originName: origin.name,
            destinationName: destination.name,
            expectedTravelTime: route.expectedTravelTime,
            distanceMeters: route.distanceMeters,
            departureDate: departureDate,
            arrivalDate: departureDate.addingTimeInterval(route.expectedTravelTime),
            provider: result.provider,
            distanceUnit: settings.distanceUnit,
            displayFormatter: displayFormatter,
            notice: joinNotices(allNotices)
        )
    }

    private func joinNotices(_ notices: [String?]) -> String? {
        let values = notices.compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }
}

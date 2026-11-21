import Foundation
import SwiftData
import XCTest
@testable import DriveTime

final class MockKeychain: KeychainStoring {
    var storage: [String: String] = [:]

    func read(key: String) -> String? { storage[key] }

    func write(_ value: String, key: String) throws {
        storage[key] = value
    }

    func delete(key: String) {
        storage.removeValue(forKey: key)
    }
}

enum TestSupport {
    static func makeDate(
        _ components: DateComponents,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)!
    }

    static func location(
        _ name: String,
        latitude: Double,
        longitude: Double,
        provider: RouteProviderID = .appleMaps
    ) -> LocationResult {
        LocationResult(
            name: name,
            city: "测试市",
            district: "测试区",
            address: "\(name)地址",
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude, datum: .gcj02),
            provider: provider,
            providerPlaceID: nil,
            source: provider == .amap ? .amap : .appleMapKit
        )
    }

    static func route(
        title: String,
        distance: Double,
        duration: Double,
        recommended: Bool,
        traffic: TrafficInformation? = nil,
        isChina: Bool = true
    ) -> RouteAlternative {
        RouteAlternative(
            title: title,
            distanceMeters: distance,
            expectedTravelTime: duration,
            polyline: [
                GeoCoordinate(latitude: 28.58, longitude: 121.36, datum: isChina ? .gcj02 : .wgs84),
                GeoCoordinate(latitude: 28.60, longitude: 121.38, datum: isChina ? .gcj02 : .wgs84)
            ],
            steps: [
                RouteStep(id: 0, instruction: "沿测试路直行", distanceMeters: distance)
            ],
            traffic: traffic,
            tollAmountYuan: recommended ? 32 : nil,
            tollDistanceMeters: recommended ? 8_000 : nil,
            tollRoads: recommended ? ["测试高速"] : [],
            hasTolls: recommended,
            isRecommended: recommended
        )
    }

    static func providerResult(
        provider: RouteProviderID = .appleMaps,
        alternatives: [RouteAlternative]? = nil,
        fetchedAt: Date = Date()
    ) -> ProviderRouteResult {
        let routes = alternatives ?? [
            route(title: "推荐路线", distance: 124_300, duration: 9_360, recommended: true),
            route(title: "备选路线 2", distance: 137_000, duration: 10_080, recommended: false)
        ]
        return ProviderRouteResult(
            provider: provider,
            alternatives: routes,
            fetchedAt: fetchedAt
        )
    }

    static func plan(
        origin: LocationResult? = nil,
        destination: LocationResult? = nil,
        fetchedAt: Date = Date(),
        provider: RouteProviderID = .appleMaps
    ) -> RoutePlan {
        let resolvedOrigin = origin ?? location("台州市路桥区", latitude: 28.58, longitude: 121.36)
        let resolvedDestination = destination ?? location("杭州市西湖区", latitude: 30.25, longitude: 120.13)
        return RoutePlan(
            provider: provider,
            origin: resolvedOrigin,
            destination: resolvedDestination,
            strategy: .recommended,
            requestedDepartureAt: fetchedAt.addingTimeInterval(-60),
            requestedAt: fetchedAt.addingTimeInterval(-70),
            fetchedAt: fetchedAt,
            alternatives: [
                route(title: "推荐路线", distance: 124_300, duration: 9_360, recommended: true),
                route(title: "备选路线 2", distance: 137_000, duration: 10_080, recommended: false)
            ],
            forecastAvailability: .currentConditions
        )
    }

    @MainActor
    static func makeSettings(
        keychain: MockKeychain = MockKeychain()
    ) -> (settings: AppSettings, defaults: UserDefaults, keychain: MockKeychain) {
        let suiteName = "DriveTimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults, keychain: keychain, infoDictionary: [:])
        return (settings, defaults, keychain)
    }

    @MainActor
    static func makeHistoryStore() throws -> (history: HistoryStore, container: ModelContainer) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SavedRoute.self,
            SavedPlace.self,
            configurations: configuration
        )
        let history = HistoryStore(context: container.mainContext)
        return (history, container)
    }
}

struct StubResolver: RoutingProviderResolving {
    let provider: any RoutingProvider

    func resolve(
        preference: ProviderPreference,
        origin: GeoCoordinate,
        destination: GeoCoordinate,
        proxy: AMapProxyConfiguration?
    ) throws -> ProviderResolution {
        ProviderResolution(provider: provider, fallback: nil, isAutomaticSelection: false)
    }
}

struct FallbackResolver: RoutingProviderResolving {
    let primary: any RoutingProvider
    let fallback: any RoutingProvider

    func resolve(
        preference: ProviderPreference,
        origin: GeoCoordinate,
        destination: GeoCoordinate,
        proxy: AMapProxyConfiguration?
    ) throws -> ProviderResolution {
        ProviderResolution(provider: primary, fallback: fallback, isAutomaticSelection: true)
    }
}

actor ProviderCallLog {
    private(set) var calculateCount = 0
    private(set) var searchCount = 0
    private(set) var cancelled = false

    func recordCalculate() {
        calculateCount += 1
    }

    func recordSearch() {
        searchCount += 1
    }

    func recordCancelled() {
        cancelled = true
    }
}

struct MockRoutingProvider: RoutingProvider {
    let providerID: RouteProviderID = .appleMaps
    let capabilities: ProviderCapabilities = .appleMaps
    let result: ProviderRouteResult
    let error: RouteProviderError?
    let log: ProviderCallLog

    init(
        result: ProviderRouteResult = TestSupport.providerResult(),
        error: RouteProviderError? = nil,
        log: ProviderCallLog = ProviderCallLog()
    ) {
        self.result = result
        self.error = error
        self.log = log
    }

    func calculateRoutes(for request: RouteRequest) async throws -> ProviderRouteResult {
        await log.recordCalculate()
        if let error { throw error }
        return result
    }

    func searchPlaces(query: String, near: GeoCoordinate?) async throws -> [LocationResult] {
        await log.recordSearch()
        if let error { throw error }
        return [TestSupport.location("测试地点", latitude: 30.25, longitude: 120.13)]
    }

    func estimateETA(for request: RouteRequest) async throws -> ETAResult {
        throw RouteProviderError.providerUnavailable("mock")
    }
}

struct SuspendingProvider: RoutingProvider {
    let providerID: RouteProviderID = .appleMaps
    let capabilities: ProviderCapabilities = .appleMaps
    let log: ProviderCallLog

    func calculateRoutes(for request: RouteRequest) async throws -> ProviderRouteResult {
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch {
            await log.recordCancelled()
            throw error
        }
        return TestSupport.providerResult()
    }

    func searchPlaces(query: String, near: GeoCoordinate?) async throws -> [LocationResult] {
        []
    }

    func estimateETA(for request: RouteRequest) async throws -> ETAResult {
        throw RouteProviderError.providerUnavailable("mock")
    }
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 3,
    poll: TimeInterval = 0.01,
    condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
    }
    return condition()
}

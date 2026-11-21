import AppIntents
import Foundation
import XCTest
@testable import DriveTime

@MainActor
final class SiriRouteQueryServiceTests: XCTestCase {
    private let fixedNow = TestSupport.makeDate(
        DateComponents(year: 2026, month: 5, day: 20, hour: 14, minute: 30)
    )

    private var origin: LocationResult {
        TestSupport.location("台州市路桥区", latitude: 28.582, longitude: 121.373)
    }

    private var destination: LocationResult {
        TestSupport.location("杭州市西湖区", latitude: 30.259, longitude: 120.130)
    }

    private func makeService(
        provider: any RoutingProvider = MockRoutingProvider(),
        resolver: (any RoutingProviderResolving)? = nil,
        places: [String: [LocationResult]]? = nil,
        strategy: RouteStrategy = .recommended,
        preference: ProviderPreference = .automatic,
        proxy: AMapProxyConfiguration? = nil,
        searchError: RouteProviderError? = nil
    ) -> SiriRouteQueryService {
        let resolvedPlaces = places ?? [
            "台州市路桥区": [origin],
            "杭州市西湖区": [destination]
        ]
        let snapshot = SiriSettingsSnapshot(
            preference: preference,
            strategy: strategy,
            proxy: proxy,
            distanceUnit: .metric,
            timeFormat: .twentyFourHour
        )
        let now = fixedNow
        return SiriRouteQueryService(
            settings: snapshot,
            resolver: resolver ?? StubResolver(provider: provider),
            now: { now },
            searchPlaces: { query in
                if let searchError { throw searchError }
                return resolvedPlaces[query] ?? []
            }
        )
    }

    func testQueryReturnsRealProviderValues() async throws {
        let result = try await makeService().query(
            originText: "台州市路桥区",
            destinationText: "杭州市西湖区"
        )
        XCTAssertEqual(result.originName, "台州市路桥区")
        XCTAssertEqual(result.destinationName, "杭州市西湖区")
        XCTAssertEqual(result.expectedTravelTime, 9_360, accuracy: 0.1)
        XCTAssertEqual(result.distanceMeters, 124_300, accuracy: 0.1)
        XCTAssertEqual(result.departureDate, fixedNow)
        XCTAssertEqual(result.arrivalDate.timeIntervalSince(fixedNow), 9_360, accuracy: 0.1)
        XCTAssertEqual(result.provider, .appleMaps)
        XCTAssertEqual(result.formattedDuration, "2 小时 36 分钟")
        XCTAssertFalse(result.dialogText.isEmpty)
        XCTAssertTrue(result.dialogText.contains("2 小时 36 分钟"))
        XCTAssertTrue(result.dialogText.contains("公里"))
    }

    func testFallbackToAppleIsReportedNotHidden() async throws {
        let primary = MockRoutingProvider(error: .serverUnavailable)
        let fallback = MockRoutingProvider()
        let service = makeService(
            resolver: FallbackResolver(primary: primary, fallback: fallback)
        )
        let result = try await service.query(
            originText: "台州市路桥区",
            destinationText: "杭州市西湖区"
        )
        XCTAssertEqual(result.provider, .appleMaps)
        XCTAssertTrue(result.notice?.contains("已改用 Apple 地图") == true)
        XCTAssertTrue(result.dialogText.contains("已改用 Apple 地图"))
    }

    func testEmptyPlaceSearchThrowsFriendlyError() async {
        let service = makeService(places: ["台州市路桥区": [origin]])
        do {
            _ = try await service.query(
                originText: "台州市路桥区",
                destinationText: "不存在的地点"
            )
            XCTFail("Expected placeNotFound")
        } catch {
            XCTAssertEqual(error as? SiriRouteError, .placeNotFound)
        }
    }

    func testSamePlaceThrows() async {
        let service = makeService(places: [
            "同一个地方": [origin],
            "也是同一个地方": [origin]
        ])
        do {
            _ = try await service.query(
                originText: "同一个地方",
                destinationText: "也是同一个地方"
            )
            XCTFail("Expected sameLocation")
        } catch {
            XCTAssertEqual(error as? SiriRouteError, .sameLocation)
        }
    }

    func testSearchFailureIsReportedAsUnavailable() async {
        let service = makeService(searchError: .networkUnavailable)
        do {
            _ = try await service.query(
                originText: "台州市路桥区",
                destinationText: "杭州市西湖区"
            )
            XCTFail("Expected unavailable")
        } catch {
            XCTAssertEqual(error as? SiriRouteError, .unavailable)
        }
    }

    func testMissingAMapConfigurationIsReported() async {
        let service = makeService(
            resolver: DefaultRoutingProviderResolver(),
            preference: .amap,
            proxy: nil
        )
        do {
            _ = try await service.query(
                originText: "台州市路桥区",
                destinationText: "杭州市西湖区"
            )
            XCTFail("Expected missingConfiguration")
        } catch {
            XCTAssertEqual(error as? SiriRouteError, .missingConfiguration)
        }
    }

    func testUnsupportedStrategyFallsBackToRecommended() async throws {
        let service = makeService(strategy: .avoidTolls)
        let result = try await service.query(
            originText: "台州市路桥区",
            destinationText: "杭州市西湖区"
        )
        XCTAssertTrue(result.notice?.contains("智能推荐") == true)
    }

    func testEmptyOriginTextIsRejectedBeforeSearch() async {
        let service = makeService()
        do {
            _ = try await service.query(originText: "   ", destinationText: "杭州市西湖区")
            XCTFail("Expected placeNotFound")
        } catch {
            XCTAssertEqual(error as? SiriRouteError, .placeNotFound)
        }
    }

    func testSiriErrorLocalizedCopy() {
        XCTAssertFalse(String(describing: SiriRouteError.missingConfiguration.localizedStringResource).isEmpty)
        XCTAssertFalse(String(describing: SiriRouteError.noRoute.localizedStringResource).isEmpty)
    }
}

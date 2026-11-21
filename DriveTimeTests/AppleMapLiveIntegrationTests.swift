import XCTest
@testable import DriveTime

/// Opt-in live check against Apple's MapKit servers. It never fakes a route:
/// if the simulator/network cannot reach MapKit, the test is skipped and the
/// final report must say that live Apple routing was not demonstrated.
final class AppleMapLiveIntegrationTests: XCTestCase {
    func testAppleMapKitLiveDrivingRoute() async throws {
        let origin = LocationResult(
            name: "人民广场",
            city: "上海市",
            coordinate: GeoCoordinate(latitude: 31.2304, longitude: 121.4737, datum: .gcj02),
            provider: .appleMaps,
            source: .appleMapKit
        )
        let destination = LocationResult(
            name: "陆家嘴",
            city: "上海市",
            coordinate: GeoCoordinate(latitude: 31.2397, longitude: 121.4998, datum: .gcj02),
            provider: .appleMaps,
            source: .appleMapKit
        )
        let now = Date()
        let request = RouteRequest(
            origin: origin,
            destination: destination,
            strategy: .recommended,
            departureAt: now,
            requestedAt: now
        )
        let provider = AppleMapRoutingProvider()
        do {
            let result = try await provider.calculateRoutes(for: request)
            let route = try XCTUnwrap(result.alternatives.first)
            XCTAssertEqual(result.provider, .appleMaps)
            XCTAssertGreaterThan(route.distanceMeters, 500)
            XCTAssertGreaterThan(route.expectedTravelTime, 60)
            XCTAssertFalse(route.polyline.isEmpty, "Apple MapKit returned no route geometry")
            print(
                "LIVE_APPLE_MAPKIT route distance=\(route.distanceMeters)m "
                    + "duration=\(route.expectedTravelTime)s points=\(route.polyline.count)"
            )
        } catch let error as RouteProviderError {
            throw XCTSkip("Live Apple MapKit route unavailable in simulator: \(error.technicalDescription)")
        }
    }
}

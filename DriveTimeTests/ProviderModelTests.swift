import Foundation
import XCTest
@testable import DriveTime

final class ProviderModelTests: XCTestCase {
    func testSamePlaceDetectionUsesCoordinateTolerance() {
        let a = TestSupport.location("A", latitude: 30.25000, longitude: 120.13000)
        let b = TestSupport.location("B", latitude: 30.25010, longitude: 120.13010)
        let far = TestSupport.location("C", latitude: 30.26000, longitude: 120.14000)
        XCTAssertTrue(a.isSamePlace(as: b))
        XCTAssertFalse(a.isSamePlace(as: far))
    }

    func testSameProviderPOIIdentifierWinsOverDistance() {
        let first = LocationResult(
            name: "西湖",
            coordinate: GeoCoordinate(latitude: 30.25, longitude: 120.13, datum: .gcj02),
            provider: .amap,
            providerPlaceID: "B001",
            source: .amap
        )
        let second = LocationResult(
            name: "西湖风景区",
            coordinate: GeoCoordinate(latitude: 31.00, longitude: 121.00, datum: .gcj02),
            provider: .amap,
            providerPlaceID: "B001",
            source: .amap
        )
        XCTAssertTrue(first.isSamePlace(as: second))
    }

    func testRouteAlternativeDifferencesUseActualValues() {
        let recommended = TestSupport.route(
            title: "推荐",
            distance: 100_000,
            duration: 9_000,
            recommended: true
        )
        let slower = TestSupport.route(
            title: "备选",
            distance: 112_000,
            duration: 9_720,
            recommended: false
        )
        XCTAssertEqual(slower.travelTimeDifference(from: recommended), 720, accuracy: 0.001)
        XCTAssertEqual(slower.distanceDifference(from: recommended), 12_000, accuracy: 0.001)
    }

    func testErrorMessagesAreUserFacing() {
        XCTAssertFalse(RouteProviderError.noRoute.userMessage.contains("NSError"))
        XCTAssertFalse(RouteProviderError.decodingFailed.userMessage.contains("JSONDecoder"))
        XCTAssertTrue(RouteProviderError.timedOut.userMessage.contains("超时"))
        XCTAssertTrue(RouteProviderError.locationPermissionDenied.userMessage.contains("定位"))
    }

    @MainActor
    func testProxyURLValidationAllowsHTTPSTunnelAndLocalHTTPOnly() {
        XCTAssertNotNil(AppSettings.validatedProxyURL(from: "https://example.workers.dev"))
        XCTAssertNotNil(AppSettings.validatedProxyURL(from: "http://127.0.0.1:8787"))
        XCTAssertNotNil(AppSettings.validatedProxyURL(from: "http://localhost:8787"))
        XCTAssertNil(AppSettings.validatedProxyURL(from: "http://example.com"))
        XCTAssertNil(AppSettings.validatedProxyURL(from: "ftp://example.com"))
        XCTAssertNil(AppSettings.validatedProxyURL(from: "not a url"))
    }

    @MainActor
    func testSettingsProviderSelectionAndAvailableStrategies() {
        let (settings, _, _) = TestSupport.makeSettings()

        settings.preferredProvider = .appleMaps
        XCTAssertEqual(settings.availableStrategies(), [.recommended])

        settings.preferredProvider = .amap
        XCTAssertEqual(settings.availableStrategies(), [.recommended])
        XCTAssertNil(settings.proxyConfiguration)

        settings.proxyBaseURLString = "https://proxy.example.workers.dev"
        XCTAssertEqual(settings.availableStrategies(), RouteStrategy.allCases)
        XCTAssertNotNil(settings.proxyConfiguration)
    }

    @MainActor
    func testSettingsFormatsAndTokenKeychain() {
        let keychain = MockKeychain()
        let (settings, _, _) = TestSupport.makeSettings(keychain: keychain)
        settings.setProxyAccessToken("  top-secret-proxy-token  ")
        XCTAssertEqual(settings.proxyAccessToken, "top-secret-proxy-token")
        XCTAssertEqual(keychain.storage["proxyAccessToken"], "top-secret-proxy-token")
        settings.setProxyAccessToken("")
        XCTAssertNil(keychain.read(key: "proxyAccessToken"))
    }

    @MainActor
    func testResolverSelectsAMapOnlyWhenConfiguredAndInChina() throws {
        let resolver = DefaultRoutingProviderResolver(
            makeApple: { AppleMapRoutingProvider() },
            makeAMap: { AMapRoutingProvider(configuration: $0) }
        )
        let proxy = AMapProxyConfiguration(
            baseURL: URL(string: "https://proxy.example.workers.dev")!,
            accessToken: nil
        )
        let chinaA = GeoCoordinate(latitude: 28.58, longitude: 121.36, datum: .gcj02)
        let chinaB = GeoCoordinate(latitude: 30.25, longitude: 120.13, datum: .gcj02)
        let tokyo = GeoCoordinate(latitude: 35.67, longitude: 139.65, datum: .wgs84)

        let automaticAMap = try resolver.resolve(
            preference: .automatic,
            origin: chinaA,
            destination: chinaB,
            proxy: proxy
        )
        XCTAssertEqual(automaticAMap.provider.providerID, .amap)
        XCTAssertNotNil(automaticAMap.fallback)

        let automaticApple = try resolver.resolve(
            preference: .automatic,
            origin: tokyo,
            destination: chinaA,
            proxy: proxy
        )
        XCTAssertEqual(automaticApple.provider.providerID, .appleMaps)
        XCTAssertNil(automaticApple.fallback)

        XCTAssertThrowsError(
            try resolver.resolve(
                preference: .amap,
                origin: chinaA,
                destination: chinaB,
                proxy: nil
            )
        )
    }
}

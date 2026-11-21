import Foundation
import XCTest
@testable import DriveTime

final class AMapResponseMapperTests: XCTestCase {
    private let fixedDate = TestSupport.makeDate(
        DateComponents(year: 2026, month: 5, day: 20, hour: 14, minute: 30)
    )

    private func request(strategy: RouteStrategy = .recommended) -> RouteRequest {
        RouteRequest(
            origin: TestSupport.location("台州市路桥区", latitude: 28.58, longitude: 121.36, provider: .amap),
            destination: TestSupport.location("杭州市西湖区", latitude: 30.25, longitude: 120.13, provider: .amap),
            strategy: strategy,
            departureAt: fixedDate,
            requestedAt: fixedDate.addingTimeInterval(-1)
        )
    }

    func testParsesDrivingResponseWithCostsTrafficAndGeometry() throws {
        let result = try AMapResponseMapper.drivingRoutes(
            from: Data(successJSON.utf8),
            request: request(strategy: .avoidCongestion),
            fetchedAt: fixedDate
        )
        XCTAssertEqual(result.provider, .amap)
        XCTAssertEqual(result.alternatives.count, 2)
        let first = result.alternatives[0]
        XCTAssertEqual(first.distanceMeters, 124_300, accuracy: 0.1)
        XCTAssertEqual(first.expectedTravelTime, 9_360, accuracy: 0.1)
        XCTAssertEqual(first.tollAmountYuan ?? -1, 32, accuracy: 0.001)
        XCTAssertEqual(first.tollDistanceMeters ?? -1, 8_000, accuracy: 0.001)
        XCTAssertEqual(first.hasTolls, true)
        XCTAssertTrue(first.isRecommended)
        XCTAssertEqual(first.polyline.count, 3)
        XCTAssertEqual(first.polyline.first?.datum, .gcj02)
        XCTAssertEqual(first.steps.count, 2)
        XCTAssertEqual(first.traffic?.segments.count, 3)
        XCTAssertEqual(first.traffic?.segments.first?.level, .smooth)
        XCTAssertEqual(first.traffic?.segments.filter { $0.level == .congested }.count, 1)
        XCTAssertTrue(first.hasGeometry)
        XCTAssertTrue(first.tollRoads.contains("沪昆高速"))
    }

    func testAMapNumericStringsAreConvertedWithoutGuessing() throws {
        let result = try AMapResponseMapper.drivingRoutes(
            from: Data(minimalJSON.utf8),
            request: request()
        )
        XCTAssertEqual(result.alternatives[0].distanceMeters, 1_000)
        XCTAssertEqual(result.alternatives[0].expectedTravelTime, 600)
        XCTAssertNil(result.alternatives[0].tollAmountYuan)
        XCTAssertNil(result.alternatives[0].hasTolls)
        XCTAssertNil(result.alternatives[0].traffic)
        XCTAssertTrue(result.alternatives[0].notes.contains { $0.contains("未返回") } == false)
    }

    func testMalformedPolylineIsRejectedInsteadOfDrawingStraightLine() throws {
        let result = try AMapResponseMapper.drivingRoutes(
            from: Data(malformedPolylineJSON.utf8),
            request: request()
        )
        let route = result.alternatives[0]
        XCTAssertTrue(route.polyline.isEmpty)
        XCTAssertFalse(route.hasGeometry)
        XCTAssertTrue(route.notes.contains { $0.contains("未返回完整路线轨迹") })
    }

    func testMissingDurationThrows() {
        XCTAssertThrowsError(
            try AMapResponseMapper.drivingRoutes(
                from: Data(missingDurationJSON.utf8),
                request: request()
            )
        ) { error in
            guard case RouteProviderError.missingRouteData = error else {
                return XCTFail("Expected missingRouteData, got \(error)")
            }
        }
    }

    func testNoPathsThrowsNoRoute() {
        XCTAssertThrowsError(
            try AMapResponseMapper.drivingRoutes(
                from: Data(noRouteJSON.utf8),
                request: request()
            )
        ) { error in
            XCTAssertEqual(error as? RouteProviderError, .noRoute)
        }
    }

    func testAMapErrorStatusMapsToQuotaError() {
        XCTAssertThrowsError(
            try AMapResponseMapper.drivingRoutes(
                from: Data(quotaErrorJSON.utf8),
                request: request()
            )
        ) { error in
            XCTAssertEqual(error as? RouteProviderError, .quotaExceeded)
        }
    }

    func testPlacesParsingSkipsInvalidPOIs() throws {
        let places = try AMapResponseMapper.places(
            from: Data(placesJSON.utf8),
            fetchedAt: fixedDate
        )
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].name, "西湖风景区")
        XCTAssertEqual(places[0].city, "杭州市")
        XCTAssertEqual(places[0].district, "西湖区")
        XCTAssertEqual(places[0].address, "龙井路1号")
        XCTAssertEqual(places[0].provider, .amap)
        XCTAssertEqual(places[0].providerPlaceID, "B001")
        XCTAssertEqual(places[0].coordinate.datum, .gcj02)
        XCTAssertEqual(places[0].coordinate.latitude, 30.245, accuracy: 0.000_001)
        XCTAssertEqual(places[0].coordinate.longitude, 120.148, accuracy: 0.000_001)
    }

    func testEmptyPOIListReturnsEmptyWithoutError() throws {
        let places = try AMapResponseMapper.places(
            from: Data(emptyPlacesJSON.utf8),
            fetchedAt: fixedDate
        )
        XCTAssertTrue(places.isEmpty)
    }

    @MainActor
    func testStrategyMappingUsesV5Codes() {
        XCTAssertEqual(RouteStrategy.recommended.amapStrategyCode, 32)
        XCTAssertEqual(RouteStrategy.fastest.amapStrategyCode, 38)
        XCTAssertEqual(RouteStrategy.avoidCongestion.amapStrategyCode, 33)
        XCTAssertEqual(RouteStrategy.avoidTolls.amapStrategyCode, 36)
        XCTAssertEqual(RouteStrategy.avoidHighways.amapStrategyCode, 35)
        XCTAssertEqual(RouteStrategy.highwayFirst.amapStrategyCode, 34)
    }

    func testPolylineParserRejectsMalformedCoordinate() {
        XCTAssertTrue(AMapResponseMapper.parsePolyline("120.1,30.1;120.2,30.2").count == 2)
        XCTAssertTrue(AMapResponseMapper.parsePolyline("120.1,30.1;oops;120.2,30.2").isEmpty)
        XCTAssertTrue(AMapResponseMapper.parsePolyline("120.1,30.1;120.2").isEmpty)
        XCTAssertTrue(AMapResponseMapper.parsePolyline("200.1,30.1;120.2,30.2").isEmpty)
    }

    func testProviderErrorCodeMapping() {
        XCTAssertEqual(AMapResponseMapper.mapProviderError(infocode: "10001"), .unauthorized)
        XCTAssertEqual(AMapResponseMapper.mapProviderError(infocode: "10003"), .quotaExceeded)
        XCTAssertEqual(AMapResponseMapper.mapProviderError(infocode: "10021"), .rateLimited(retryAfter: nil))
        XCTAssertEqual(AMapResponseMapper.mapProviderError(infocode: "20800"), .noRoute)
    }

    func testAppleCapabilitiesOnlyAdvertiseRecommendedStrategy() {
        XCTAssertEqual(ProviderCapabilities.appleMaps.strategies, [.recommended])
        XCTAssertTrue(ProviderCapabilities.appleMaps.supportsAlternateRoutes)
        XCTAssertFalse(ProviderCapabilities.appleMaps.supportsTrafficSegments)
        XCTAssertFalse(ProviderCapabilities.amap.supportsFutureTraffic)
        XCTAssertTrue(ProviderCapabilities.amap.supportsTollAmounts)
        XCTAssertTrue(ProviderCapabilities.amap.supportsTrafficSegments)
    }

    func testProxyErrorEnvelopeDecoder() throws {
        let data = Data(#"{"error":{"code":"AMAP_10003","message":"quota"}}"#.utf8)
        let envelope = try JSONDecoder().decode(ProxyErrorEnvelope.self, from: data)
        XCTAssertEqual(envelope.error?.code, "AMAP_10003")
        XCTAssertEqual(envelope.error?.message, "quota")
    }

    // MARK: - Fixtures

    private var successJSON: String {
        """
        {
          "status":"1","info":"OK","infocode":"10000","count":"2",
          "route":{
            "origin":"121.360000,28.580000",
            "destination":"120.130000,30.250000",
            "paths":[
              {
                "distance":"124300",
                "cost":{"duration":"9360","tolls":"32","toll_distance":"8000","toll_road":"沪昆高速;杭州绕城高速","traffic_lights":"12"},
                "steps":[
                  {
                    "instruction":"沿沈海高速向杭州方向行驶",
                    "road_name":"沈海高速",
                    "step_distance":"60000",
                    "cost":{"duration":"4000"},
                    "polyline":"121.360000,28.580000;121.380000,28.600000",
                    "navi":{"action":"直行","assistant_action":""},
                    "tmcs":[
                      {"tmc_status":"畅通","tmc_distance":"30000","tmc_polyline":"121.360000,28.580000;121.370000,28.590000"},
                      {"tmc_status":"缓行","tmc_distance":"30000","tmc_polyline":"121.370000,28.590000;121.380000,28.600000"}
                    ]
                  },
                  {
                    "instruction":"靠右进入杭州绕城高速",
                    "road_name":"杭州绕城高速",
                    "step_distance":"64300",
                    "cost":{"duration":"5360"},
                    "polyline":"121.380000,28.600000;120.130000,30.250000",
                    "navi":{"action":"靠右","assistant_action":""},
                    "tmcs":[
                      {"tmc_status":"拥堵","tmc_distance":"64300","tmc_polyline":"121.380000,28.600000;120.130000,30.250000"}
                    ]
                  }
                ]
              },
              {
                "distance":"137000",
                "cost":{"duration":"10080","tolls":[]},
                "steps":[
                  {
                    "instruction":"沿地方道路行驶",
                    "road_name":"G104",
                    "step_distance":"137000",
                    "cost":{"duration":"10080"},
                    "polyline":"121.360000,28.580000;119.900000,29.900000;120.130000,30.250000"
                  }
                ]
              }
            ]
          }
        }
        """
    }

    private var minimalJSON: String {
        """
        {
          "status":"1","info":"OK","infocode":"10000",
          "route":{"paths":[{"distance":"1000","cost":{"duration":"600"},"steps":[{"step_distance":"1000","cost":{"duration":"600"},"polyline":"120.100000,30.100000;120.200000,30.200000"}]}]}
        }
        """
    }

    private var malformedPolylineJSON: String {
        """
        {
          "status":"1","info":"OK","infocode":"10000",
          "route":{"paths":[{"distance":"1000","cost":{"duration":"600"},"steps":[{"step_distance":"1000","polyline":"bad;120.2,30.2","cost":{"duration":"600"}}]}]}
        }
        """
    }

    private var missingDurationJSON: String {
        """
        {
          "status":"1","info":"OK","infocode":"10000",
          "route":{"paths":[{"distance":"1000","steps":[{"step_distance":"1000"}]}]}
        }
        """
    }

    private var noRouteJSON: String {
        """
        {"status":"1","info":"OK","infocode":"10000","route":{"paths":[]}}
        """
    }

    private var quotaErrorJSON: String {
        """
        {"status":"0","info":"DAILY_QUERY_OVER_LIMIT","infocode":"10003","route":[]}
        """
    }

    private var placesJSON: String {
        """
        {
          "status":"1","info":"OK","infocode":"10000","count":"2",
          "pois":[
            {
              "name":"西湖风景区","id":"B001","location":"120.148000,30.245000",
              "type":"风景名胜;公园","typecode":"110000","pname":"浙江省",
              "cityname":"杭州市","adname":"西湖区","address":"龙井路1号"
            },
            {
              "name":"坏数据","id":"B002","location":"not-a-coordinate",
              "pname":"浙江省","cityname":"杭州市"
            }
          ]
        }
        """
    }

    private var emptyPlacesJSON: String {
        """
        {"status":"1","info":"OK","infocode":"10000","count":"0","pois":[]}
        """
    }
}

import CoreLocation
import XCTest
@testable import DriveTime

final class CoordinateTransformTests: XCTestCase {
    func testWGS84ToGCJ02ProducesChinaOffset() {
        let wgs = CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975)
        let gcj = ChinaCoordinateTransform.wgs84ToGcj02(wgs)
        XCTAssertGreaterThan(abs(gcj.latitude - wgs.latitude), 0.000_001)
        XCTAssertGreaterThan(abs(gcj.longitude - wgs.longitude), 0.000_001)
        let northMeters = abs(gcj.latitude - wgs.latitude) * 111_000
        let eastMeters = abs(gcj.longitude - wgs.longitude) * 85_000
        XCTAssertGreaterThan(northMeters, 20)
        XCTAssertGreaterThan(eastMeters, 50)
    }

    func testGCJ02RoundTripIsSubMeter() {
        let wgs = CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551)
        let gcj = ChinaCoordinateTransform.wgs84ToGcj02(wgs)
        let roundTrip = ChinaCoordinateTransform.gcj02ToWgs84(gcj)
        XCTAssertEqual(roundTrip.latitude, wgs.latitude, accuracy: 0.000_005)
        XCTAssertEqual(roundTrip.longitude, wgs.longitude, accuracy: 0.000_005)
    }

    func testCoordinatesOutsideChinaAreUntouched() {
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let gcj = ChinaCoordinateTransform.wgs84ToGcj02(tokyo)
        XCTAssertEqual(gcj.latitude, tokyo.latitude, accuracy: 0.000_000_1)
        XCTAssertEqual(gcj.longitude, tokyo.longitude, accuracy: 0.000_000_1)
    }

    func testHongKongIsNotTreatedAsMainlandChina() {
        let coordinate = GeoCoordinate(latitude: 22.3193, longitude: 114.1694, datum: .wgs84)
        XCTAssertFalse(coordinate.isInMainlandChina)
        let converted = coordinate.converted(to: .gcj02)
        XCTAssertEqual(converted.latitude, coordinate.latitude, accuracy: 0.000_000_1)
    }

    func testExplicitDatumConversion() {
        let wgs = GeoCoordinate(latitude: 30.2741, longitude: 120.1551, datum: .wgs84)
        let gcj = wgs.converted(to: .gcj02)
        XCTAssertEqual(gcj.datum, .gcj02)
        XCTAssertEqual(gcj.wgs84Coordinate.latitude, wgs.latitude, accuracy: 0.000_01)
        XCTAssertEqual(gcj.wgs84Coordinate.longitude, wgs.longitude, accuracy: 0.000_01)
    }

    func testGroundDistanceUsesComparableDatum() {
        let wgs = GeoCoordinate(latitude: 28.58, longitude: 121.36, datum: .wgs84)
        let gcj = wgs.converted(to: .gcj02)
        XCTAssertLessThan(wgs.groundDistance(to: gcj), 0.5)

        let other = TestSupport.location("附近", latitude: 28.5801, longitude: 121.3601)
        XCTAssertLessThan(other.coordinate.groundDistance(to: wgs), 40)
    }
}

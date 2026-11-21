import CoreLocation
import MapKit
import XCTest
@testable import DriveTime

final class MapViewportTests: XCTestCase {
    func testRouteViewportLeavesRoomForBottomSheet() throws {
        let north = CLLocationCoordinate2D(latitude: 30.259, longitude: 120.130)
        let south = CLLocationCoordinate2D(latitude: 28.582, longitude: 121.372)
        let region = try XCTUnwrap(MapViewportRegion.fitting(coordinates: [north, south]))

        let midpoint = (north.latitude + south.latitude) / 2
        XCTAssertLessThan(region.center.latitude, midpoint)

        let top = region.center.latitude + region.span.latitudeDelta / 2
        let bottom = region.center.latitude - region.span.latitudeDelta / 2
        XCTAssertGreaterThan(top, north.latitude)
        XCTAssertLessThan(bottom, south.latitude)
        let topGap = top - north.latitude
        let bottomGap = south.latitude - bottom
        XCTAssertGreaterThan(bottomGap, topGap * 2)
    }

    func testViewportIsBoundedForTinyRoute() throws {
        let a = CLLocationCoordinate2D(latitude: 30.2500, longitude: 120.1300)
        let b = CLLocationCoordinate2D(latitude: 30.2501, longitude: 120.1301)
        let region = try XCTUnwrap(MapViewportRegion.fitting(coordinates: [a, b]))
        XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
    }
}

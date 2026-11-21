import Foundation
import SwiftData
import XCTest
@testable import DriveTime

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testRecordAndFetchHistorySummary() throws {
        let (history, _) = try TestSupport.makeHistoryStore()
        let queriedAt = TestSupport.makeDate(
            DateComponents(year: 2026, month: 5, day: 20, hour: 14, minute: 30)
        )
        let plan = TestSupport.plan(fetchedAt: queriedAt)
        let saved = history.record(plan: plan)

        XCTAssertEqual(history.recentRoutes.count, 1)
        XCTAssertEqual(saved.durationSeconds, plan.selectedAlternative.expectedTravelTime, accuracy: 0.1)
        XCTAssertEqual(saved.distanceMeters, plan.selectedAlternative.distanceMeters, accuracy: 0.1)
        XCTAssertEqual(saved.provider, plan.provider)
        XCTAssertEqual(saved.arrivalAt, plan.arrivalDate)
        XCTAssertEqual(saved.queriedAt, queriedAt)
        XCTAssertEqual(saved.originLocation.name, plan.origin.name)
        XCTAssertEqual(saved.destinationLocation.name, plan.destination.name)
        XCTAssertEqual(saved.originLocation.coordinate.datum, .gcj02)
        XCTAssertFalse(saved.isFavorite)
    }

    func testFavoriteAndDeleteRoute() throws {
        let (history, _) = try TestSupport.makeHistoryStore()
        let saved = history.record(plan: TestSupport.plan())
        XCTAssertEqual(history.favoriteRoutes.count, 0)

        history.toggleFavorite(route: saved)
        XCTAssertEqual(history.favoriteRoutes.count, 1)
        XCTAssertTrue(history.recentRoutes.first?.isFavorite == true)

        history.delete(route: saved)
        XCTAssertTrue(history.recentRoutes.isEmpty)
        XCTAssertTrue(history.favoriteRoutes.isEmpty)
    }

    func testClearHistoryKeepsFavorites() throws {
        let (history, _) = try TestSupport.makeHistoryStore()
        let favorite = history.record(plan: TestSupport.plan(origin: TestSupport.location("家", latitude: 28.58, longitude: 121.36)))
        history.toggleFavorite(route: favorite)
        _ = history.record(plan: TestSupport.plan(origin: TestSupport.location("公司", latitude: 29.0, longitude: 121.0)))

        XCTAssertEqual(history.recentRoutes.count, 2)
        history.clearHistory(keepingFavorites: true)
        XCTAssertEqual(history.recentRoutes.count, 1)
        XCTAssertEqual(history.recentRoutes.first?.originName, "家")
        XCTAssertTrue(history.recentRoutes.first?.isFavorite == true)
    }

    func testFavoritePlaceToggleAndLookup() throws {
        let (history, _) = try TestSupport.makeHistoryStore()
        let location = TestSupport.location("西湖", latitude: 30.25, longitude: 120.13)
        XCTAssertFalse(history.isFavoritePlace(location))

        history.toggleFavoritePlace(location)
        XCTAssertTrue(history.isFavoritePlace(location))
        XCTAssertEqual(history.favoritePlaces.count, 1)
        XCTAssertEqual(history.favoritePlaces.first?.location.name, "西湖")

        history.toggleFavoritePlace(location)
        XCTAssertFalse(history.isFavoritePlace(location))
        XCTAssertTrue(history.favoritePlaces.isEmpty)
    }

    func testDuplicateFavoriteMatchingUsesCoordinates() throws {
        let (history, _) = try TestSupport.makeHistoryStore()
        let original = TestSupport.location("西湖", latitude: 30.25, longitude: 120.13)
        history.toggleFavoritePlace(original)
        let nearby = TestSupport.location("西湖", latitude: 30.2501, longitude: 120.1301)
        XCTAssertTrue(history.isFavoritePlace(nearby))
        history.toggleFavoritePlace(nearby)
        XCTAssertTrue(history.favoritePlaces.isEmpty)
    }

    func testRecordPreservesFavoriteOnMatchingRoute() throws {
        let (history, _) = try TestSupport.makeHistoryStore()
        let plan = TestSupport.plan()
        let first = history.record(plan: plan)
        history.toggleFavorite(route: first)
        let second = history.record(plan: plan)
        XCTAssertTrue(second.isFavorite)
        XCTAssertEqual(history.favoriteRoutes.count, 2)
    }
}

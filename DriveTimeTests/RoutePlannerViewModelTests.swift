import Foundation
import SwiftData
import XCTest
@testable import DriveTime

@MainActor
final class RoutePlannerViewModelTests: XCTestCase {
    func testSuccessfulQueryBuildsPlanAndSavesHistory() async throws {
        let provider = MockRoutingProvider()
        let sut = try makeSUT(provider: provider)
        sut.vm.setEndpoint(TestSupport.location("台州市路桥区", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("杭州市西湖区", latitude: 30.25, longitude: 120.13), for: .destination)

        sut.vm.calculateRoute()
        await assertEventually { sut.vm.phase == .success }
        let plan = try XCTUnwrap(sut.vm.plan)
        XCTAssertEqual(plan.provider, .appleMaps)
        XCTAssertEqual(plan.alternatives.count, 2)
        XCTAssertEqual(plan.selectedAlternative.title, "推荐路线")
        XCTAssertEqual(sut.history.recentRoutes.count, 1)
        XCTAssertEqual(sut.history.recentRoutes.first?.durationSeconds ?? 0, 9_360, accuracy: 0.1)
        XCTAssertTrue(sut.vm.canToggleFavorite)
        XCTAssertNotNil(sut.vm.savedRouteID)
    }

    func testUnsupportedStrategyNotFoundDoesNotCrash() async throws {
        let provider = MockRoutingProvider()
        let sut = try makeSUT(provider: provider)
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25, longitude: 120.13), for: .destination)
        sut.vm.selectedStrategy = .avoidTolls
        sut.vm.calculateRoute()
        await assertEventually { sut.vm.phase == .success }
        let plan = try XCTUnwrap(sut.vm.plan)
        XCTAssertEqual(plan.strategy, .recommended)
        XCTAssertTrue(plan.notices.contains { $0.contains("不支持") })
    }

    func testSameLocationIsRejectedBeforeNetworkCall() async throws {
        let log = ProviderCallLog()
        let provider = MockRoutingProvider(log: log)
        let sut = try makeSUT(provider: provider)
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 30.25000, longitude: 120.13000), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25010, longitude: 120.13010), for: .destination)

        sut.vm.calculateRoute()
        try await Task.sleep(nanoseconds: 80_000_000)
        guard case .failed(let message) = sut.vm.phase else {
            return XCTFail("Expected failed phase, got \(sut.vm.phase)")
        }
        XCTAssertTrue(message.contains("太近"))
        let callCount = await log.calculateCount
        XCTAssertEqual(callCount, 0)
    }

    func testSwapEndpointsProducesReversedTrip() {
        let provider = MockRoutingProvider()
        let sut = try? makeSUT(provider: provider)
        guard let sut else { return XCTFail("Unable to create SUT") }
        let origin = TestSupport.location("起点A", latitude: 28.58, longitude: 121.36)
        let destination = TestSupport.location("终点B", latitude: 30.25, longitude: 120.13)
        sut.vm.setEndpoint(origin, for: .origin)
        sut.vm.setEndpoint(destination, for: .destination)

        sut.vm.swapEndpoints()

        XCTAssertEqual(sut.vm.origin?.name, "终点B")
        XCTAssertEqual(sut.vm.destination?.name, "起点A")
        XCTAssertEqual(sut.vm.phase, .ready)
    }

    func testCancellingInFlightRequestStopsProvider() async throws {
        let log = ProviderCallLog()
        let provider = SuspendingProvider(log: log)
        let sut = try makeSUT(resolver: StubResolver(provider: provider))
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25, longitude: 120.13), for: .destination)

        sut.vm.calculateRoute()
        XCTAssertTrue(sut.vm.isBusy)
        sut.vm.cancelActiveRequest()
        try await Task.sleep(nanoseconds: 150_000_000)
        let providerSawCancellation = await log.cancelled
        XCTAssertTrue(providerSawCancellation)
        XCTAssertNil(sut.vm.plan)
        XCTAssertEqual(sut.vm.phase, .ready)
    }

    func testNoRouteShowsEmptyState() async throws {
        let provider = MockRoutingProvider(error: .noRoute)
        let sut = try makeSUT(provider: provider)
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25, longitude: 120.13), for: .destination)

        sut.vm.calculateRoute()
        await assertEventually { sut.vm.phase == .empty }
        XCTAssertTrue(sut.vm.errorMessage?.contains("没有找到") == true)
        XCTAssertNil(sut.vm.plan)
    }

    func testFutureDepartureIsLabeledAsProjectedNotPredicted() async throws {
        let fixedNow = TestSupport.makeDate(
            DateComponents(year: 2026, month: 5, day: 20, hour: 14, minute: 30)
        )
        let scheduled = fixedNow.addingTimeInterval(3_600)
        let provider = MockRoutingProvider()
        let sut = try makeSUT(provider: provider, now: { fixedNow })
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25, longitude: 120.13), for: .destination)
        sut.vm.setDepartureChoice(.scheduled(scheduled))

        sut.vm.calculateRoute()
        await assertEventually { sut.vm.phase == .success }
        let plan = try XCTUnwrap(sut.vm.plan)
        XCTAssertEqual(plan.requestedDepartureAt, scheduled)
        XCTAssertEqual(plan.forecastAvailability, .projectedFromCurrent)
        XCTAssertEqual(
            plan.arrivalDate.timeIntervalSince(scheduled),
            plan.selectedAlternative.expectedTravelTime,
            accuracy: 0.1
        )
        XCTAssertTrue(plan.notices.contains { $0.contains("预测") || $0.contains("推算") })
    }

    func testAutomaticFallbackIsVisibleNotSilent() async throws {
        let primary = MockRoutingProvider(error: .serverUnavailable)
        let fallback = MockRoutingProvider()
        let sut = try makeSUT(resolver: FallbackResolver(primary: primary, fallback: fallback))
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25, longitude: 120.13), for: .destination)

        sut.vm.calculateRoute()
        await assertEventually { sut.vm.phase == .success }
        let plan = try XCTUnwrap(sut.vm.plan)
        XCTAssertEqual(plan.provider, .appleMaps)
        XCTAssertTrue(plan.notices.contains { $0.contains("已改用 Apple 地图") })
    }

    func testRefreshCooldownPreventsImmediateDuplicateRequest() async throws {
        let log = ProviderCallLog()
        let provider = MockRoutingProvider(log: log)
        let sut = try makeSUT(provider: provider)
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25, longitude: 120.13), for: .destination)
        sut.vm.calculateRoute()
        await assertEventually { sut.vm.phase == .success }
        XCTAssertFalse(sut.vm.canRefresh)

        sut.vm.refresh()
        XCTAssertNotNil(sut.vm.inlineError)
        let callCount = await log.calculateCount
        XCTAssertEqual(callCount, 1)
    }

    func testChangingEndpointsClearsPreviousPlan() async throws {
        let sut = try makeSUT(provider: MockRoutingProvider())
        sut.vm.setEndpoint(TestSupport.location("A", latitude: 28.58, longitude: 121.36), for: .origin)
        sut.vm.setEndpoint(TestSupport.location("B", latitude: 30.25, longitude: 120.13), for: .destination)
        sut.vm.calculateRoute()
        await assertEventually { sut.vm.phase == .success }
        XCTAssertNotNil(sut.vm.plan)

        sut.vm.setEndpoint(TestSupport.location("C", latitude: 29.87, longitude: 121.55), for: .destination)
        XCTAssertNil(sut.vm.plan)
        XCTAssertEqual(sut.vm.phase, .ready)
        XCTAssertNil(sut.vm.savedRouteID)
    }

    private func makeSUT(
        provider: MockRoutingProvider,
        now: @escaping @MainActor () -> Date = { Date() }
    ) throws -> (vm: RoutePlannerViewModel, history: HistoryStore, container: ModelContainer) {
        try makeSUT(resolver: StubResolver(provider: provider), now: now)
    }

    private func makeSUT(
        resolver: any RoutingProviderResolving,
        now: @escaping @MainActor () -> Date = { Date() }
    ) throws -> (vm: RoutePlannerViewModel, history: HistoryStore, container: ModelContainer) {
        let (settings, _, _) = TestSupport.makeSettings()
        let (history, container) = try TestSupport.makeHistoryStore()
        let vm = RoutePlannerViewModel(
            settings: settings,
            history: history,
            resolver: resolver,
            now: now
        )
        return (vm, history, container)
    }
}

import Foundation
import Observation

enum TripEndpoint: String, Identifiable, CaseIterable, Sendable {
    case origin
    case destination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .origin: "设置起点"
        case .destination: "设置终点"
        }
    }

    var shortTitle: String {
        switch self {
        case .origin: "起点"
        case .destination: "终点"
        }
    }
}

enum DepartureChoice: Hashable, Sendable {
    case now
    case scheduled(Date)

    func resolvedDeparture(now: Date) -> Date {
        switch self {
        case .now:
            return now
        case .scheduled(let date):
            return max(date, now)
        }
    }

    var isNow: Bool {
        if case .now = self { return true }
        return false
    }
}

enum PlannerPhase: Equatable {
    case idle
    case ready
    case loading
    case refreshing
    case success
    case empty
    case failed(String)
}

@MainActor
@Observable
final class RoutePlannerViewModel {
    var origin: LocationResult?
    var destination: LocationResult?
    var departureChoice: DepartureChoice = .now
    var selectedStrategy: RouteStrategy
    private(set) var plan: RoutePlan?
    private(set) var phase: PlannerPhase = .idle
    /// A non-fatal error, e.g. a failed refresh that leaves the previous live
    /// plan on screen.
    private(set) var inlineError: String?
    private(set) var lastRequestStartedAt: Date?
    private(set) var savedRouteID: UUID?
    private(set) var isPlanFavorite = false

    let settings: AppSettings
    private let history: HistoryStore
    private let resolver: any RoutingProviderResolving
    private let now: @MainActor () -> Date
    private var routingTask: Task<Void, Never>?
    private var activeRequestID: UUID?

    let refreshCooldown: TimeInterval = 8

    init(
        settings: AppSettings,
        history: HistoryStore,
        resolver: any RoutingProviderResolving = DefaultRoutingProviderResolver(),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.settings = settings
        self.history = history
        self.resolver = resolver
        self.now = now
        self.selectedStrategy = settings.defaultStrategy
    }

    var hasEndpoints: Bool { origin != nil && destination != nil }

    var isBusy: Bool {
        phase == .loading || phase == .refreshing
    }

    var isRefreshing: Bool { phase == .refreshing }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return inlineError
    }

    var canRefresh: Bool {
        guard plan != nil else { return false }
        return refreshCooldownRemaining <= 0
    }

    var refreshCooldownRemaining: Int {
        guard let last = lastRequestStartedAt else { return 0 }
        let elapsed = now().timeIntervalSince(last)
        let remaining = refreshCooldown - elapsed
        return remaining > 0 ? Int(ceil(remaining)) : 0
    }

    var providerCapabilities: ProviderCapabilities {
        if let plan {
            return plan.provider == .amap ? .amap : .appleMaps
        }
        switch settings.configuredProviderKind(
            for: origin?.coordinate ?? GeoCoordinate(latitude: 0, longitude: 0, datum: .wgs84),
            destination: destination?.coordinate ?? GeoCoordinate(latitude: 0, longitude: 0, datum: .wgs84)
        ) {
        case .amap:
            return .amap
        case .appleMaps:
            return .appleMaps
        }
    }

    var availableStrategies: [RouteStrategy] {
        providerCapabilities.strategies
    }

    var displayFormatter: DateDisplayFormatter {
        settings.displayFormatter
    }

    func setEndpoint(_ location: LocationResult, for endpoint: TripEndpoint) {
        switch endpoint {
        case .origin:
            origin = location
        case .destination:
            destination = location
        }
        resetPlanForEditedEndpoints()
    }

    func clearEndpoint(_ endpoint: TripEndpoint) {
        switch endpoint {
        case .origin:
            origin = nil
        case .destination:
            destination = nil
        }
        resetPlanForEditedEndpoints()
    }

    func swapEndpoints() {
        let previousOrigin = origin
        let shouldRequery = plan != nil && previousOrigin != nil && destination != nil
        origin = destination
        destination = previousOrigin
        resetPlanForEditedEndpoints()
        if shouldRequery {
            calculateRoute()
        }
    }

    func setStrategy(_ strategy: RouteStrategy) {
        guard availableStrategies.contains(strategy) else { return }
        selectedStrategy = strategy
        settings.defaultStrategy = strategy
        if plan != nil, hasEndpoints {
            calculateRoute()
        }
    }

    func setDepartureChoice(_ choice: DepartureChoice) {
        departureChoice = choice
        if plan != nil, hasEndpoints {
            calculateRoute()
        }
    }

    func selectRoute(id: UUID) {
        guard var currentPlan = plan, currentPlan.selectedRouteID != id else { return }
        currentPlan.selectRoute(id: id)
        plan = currentPlan
    }

    func loadTrip(origin: LocationResult, destination: LocationResult, autostart: Bool = true) {
        self.origin = origin
        self.destination = destination
        resetPlanForEditedEndpoints()
        if autostart {
            calculateRoute()
        }
    }

    func loadSavedTrip(_ saved: SavedRoute) {
        loadTrip(origin: saved.originLocation, destination: saved.destinationLocation)
    }

    func calculateRoute() {
        guard let origin, let destination else {
            phase = .ready
            return
        }
        if origin.isSamePlace(as: destination) {
            inlineError = nil
            phase = .failed(RouteProviderError.sameLocation.userMessage)
            return
        }

        routingTask?.cancel()
        routingTask = nil
        activeRequestID = UUID()
        guard let requestID = activeRequestID else { return }

        let startedAt = now()
        lastRequestStartedAt = startedAt
        let departure = departureChoice.resolvedDeparture(now: startedAt)
        let hadPlan = plan != nil
        phase = hadPlan ? .refreshing : .loading
        inlineError = nil

        let request = RouteRequest(
            origin: origin,
            destination: destination,
            strategy: selectedStrategy,
            departureAt: departure,
            requestedAt: startedAt
        )
        let proxy = settings.proxyConfiguration
        let preference = settings.preferredProvider

        routingTask = Task { [weak self] in
            guard let self else { return }
            await self.execute(
                request: request,
                preference: preference,
                proxy: proxy,
                requestID: requestID
            )
        }
    }

    func refresh() {
        guard plan != nil else { return }
        let remaining = refreshCooldownRemaining
        guard remaining <= 0 else {
            inlineError = "刚刚刷新过，请 \(remaining) 秒后再试。"
            return
        }
        calculateRoute()
    }

    func cancelActiveRequest() {
        routingTask?.cancel()
        routingTask = nil
        activeRequestID = nil
        if phase == .loading || phase == .refreshing {
            phase = plan == nil ? .ready : .success
        }
    }

    func clearInlineError() {
        inlineError = nil
    }

    func toggleFavoriteForCurrentPlan() {
        guard let savedRouteID, let route = history.route(withID: savedRouteID) else { return }
        history.toggleFavorite(route: route)
        isPlanFavorite = route.isFavorite
    }

    var canToggleFavorite: Bool {
        savedRouteID != nil
    }

    // MARK: - Query pipeline

    private func execute(
        request: RouteRequest,
        preference: ProviderPreference,
        proxy: AMapProxyConfiguration?,
        requestID: UUID
    ) async {
        do {
            let resolution = try resolver.resolve(
                preference: preference,
                origin: request.origin.coordinate,
                destination: request.destination.coordinate,
                proxy: proxy
            )
            var effectiveStrategy = request.strategy
            var notices: [String] = []
            if !resolution.provider.capabilities.strategies.contains(effectiveStrategy) {
                effectiveStrategy = .recommended
                notices.append("当前地图服务不支持“\(request.strategy.displayName)”，已按智能推荐查询。")
            }
            var effectiveRequest = request
            effectiveRequest.strategy = effectiveStrategy

            let result: ProviderRouteResult
            var usedFallback = false
            do {
                result = try await resolution.provider.calculateRoutes(for: effectiveRequest)
            } catch let error as RouteProviderError {
                if error.isCancellation { throw error }
                guard let fallback = resolution.fallback else { throw error }
                AppLog.routing.error(
                    "Primary provider failed: \(error.technicalDescription, privacy: .public); trying Apple fallback"
                )
                usedFallback = true
                var fallbackRequest = effectiveRequest
                fallbackRequest.strategy = .recommended
                result = try await fallback.calculateRoutes(for: fallbackRequest)
                notices.append("高德地图暂时不可用，已改用 Apple 地图。")
            } catch {
                throw RouteProviderError.map(error)
            }

            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }

            if usedFallback, effectiveStrategy != .recommended {
                notices.append("Apple 地图使用智能推荐。")
                effectiveStrategy = .recommended
            }
            notices.append(contentsOf: result.notices)

            let forecastAvailability = forecastAvailability(
                for: request,
                provider: result.provider,
                providerReported: result.forecastAvailability
            )
            if forecastAvailability == .projectedFromCurrent {
                notices.append("当前地图服务不提供该时刻的交通预测，车程按当前路况估算，抵达时间仅供参考。")
            }

            guard !result.alternatives.isEmpty else {
                throw RouteProviderError.noRoute
            }
            let plan = RoutePlan(
                provider: result.provider,
                origin: request.origin,
                destination: request.destination,
                strategy: effectiveStrategy,
                requestedDepartureAt: request.departureAt,
                requestedAt: request.requestedAt,
                fetchedAt: result.fetchedAt,
                alternatives: result.alternatives,
                forecastAvailability: forecastAvailability,
                dataKind: .live,
                notices: deduplicatedNotices(notices)
            )
            apply(plan: plan)
        } catch is CancellationError {
            guard activeRequestID == requestID else { return }
            routingTask = nil
            if plan == nil { phase = .ready }
        } catch let error as RouteProviderError {
            guard activeRequestID == requestID else { return }
            if error.isCancellation { return }
            handleFailure(error)
        } catch {
            guard activeRequestID == requestID else { return }
            handleFailure(RouteProviderError.map(error))
        }
    }

    private func apply(plan: RoutePlan) {
        self.plan = plan
        phase = .success
        inlineError = nil
        routingTask = nil
        selectedStrategy = plan.strategy
        let saved = history.record(plan: plan)
        savedRouteID = saved.id
        isPlanFavorite = saved.isFavorite
    }

    private func handleFailure(_ error: RouteProviderError) {
        routingTask = nil
        AppLog.routing.error("Route query failed: \(error.technicalDescription, privacy: .public)")
        if plan != nil {
            phase = .success
            inlineError = error.userMessage
        } else if error == .noRoute {
            phase = .empty
            inlineError = error.userMessage
        } else {
            phase = .failed(error.userMessage)
        }
    }

    private func resetPlanForEditedEndpoints() {
        routingTask?.cancel()
        routingTask = nil
        activeRequestID = nil
        plan = nil
        inlineError = nil
        savedRouteID = nil
        isPlanFavorite = false
        phase = hasEndpoints ? .ready : .idle
    }

    private func forecastAvailability(
        for request: RouteRequest,
        provider: RouteProviderID,
        providerReported: ForecastAvailability
    ) -> ForecastAvailability {
        guard request.isFutureDeparture else { return .currentConditions }
        let capabilities = provider == .amap ? ProviderCapabilities.amap : ProviderCapabilities.appleMaps
        guard capabilities.supportsFutureTraffic else {
            return .projectedFromCurrent
        }
        return providerReported == .unknown ? .currentConditions : providerReported
    }

    private func deduplicatedNotices(_ notices: [String]) -> [String] {
        var seen = Set<String>()
        return notices.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

extension PlannerPhase {
    var isLoading: Bool {
        switch self {
        case .loading, .refreshing: return true
        default: return false
        }
    }
}

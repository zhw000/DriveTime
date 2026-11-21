import Foundation

protocol RoutingProvider: Sendable {
    var providerID: RouteProviderID { get }
    var capabilities: ProviderCapabilities { get }

    func calculateRoutes(for request: RouteRequest) async throws -> ProviderRouteResult
    func searchPlaces(query: String, near: GeoCoordinate?) async throws -> [LocationResult]
    func estimateETA(for request: RouteRequest) async throws -> ETAResult
}

extension RoutingProvider {
    func estimateETA(for request: RouteRequest) async throws -> ETAResult {
        throw RouteProviderError.providerUnavailable(providerID.displayName)
    }
}

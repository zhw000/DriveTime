import CoreLocation
import Foundation

struct AMapHealthStatus: Sendable {
    var isConfigured: Bool
    var providerReachable: Bool
    var message: String
    var latencyMilliseconds: Int?
}

actor AMapAPIClient {
    private let configuration: AMapProxyConfiguration
    private let http: any HTTPPerforming
    private let rateLimiter: RateLimiter
    private let decoder = JSONDecoder()

    init(
        configuration: AMapProxyConfiguration,
        http: any HTTPPerforming = URLSessionHTTPClient(),
        rateLimiter: RateLimiter = RateLimiter(minimumInterval: 1.1)
    ) {
        self.configuration = configuration
        self.http = http
        self.rateLimiter = rateLimiter
    }

    func driving(
        origin: GeoCoordinate,
        destination: GeoCoordinate,
        strategy: RouteStrategy,
        originPOIID: String?,
        destinationPOIID: String?
    ) async throws -> Data {
        let originPoint = origin.amapCoordinate
        let destinationPoint = destination.amapCoordinate
        var items = [
            URLQueryItem(name: "origin", value: coordinateParameter(originPoint)),
            URLQueryItem(name: "destination", value: coordinateParameter(destinationPoint)),
            URLQueryItem(name: "strategy", value: String(strategy.amapStrategyCode)),
            URLQueryItem(name: "show_fields", value: "cost,tmcs,polyline,navi,cities")
        ]
        if let originPOIID, !originPOIID.isEmpty {
            items.append(URLQueryItem(name: "origin_id", value: originPOIID))
        }
        if let destinationPOIID, !destinationPOIID.isEmpty {
            items.append(URLQueryItem(name: "destination_id", value: destinationPOIID))
        }
        return try await fetch(path: "/v1/route/driving", queryItems: items)
    }

    func searchPlaces(query: String, region: String? = nil) async throws -> Data {
        var items = [
            URLQueryItem(name: "keywords", value: String(query.prefix(80))),
            URLQueryItem(name: "page_size", value: "10"),
            URLQueryItem(name: "page_num", value: "1")
        ]
        if let region, !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "region", value: String(region.prefix(64))))
            items.append(URLQueryItem(name: "city_limit", value: "false"))
        }
        return try await fetch(path: "/v1/places/text", queryItems: items)
    }

    func health() async throws -> AMapHealthStatus {
        let started = Date()
        let data = try await fetch(path: "/v1/health", queryItems: [])
        let latency = Int(Date().timeIntervalSince(started) * 1_000)
        struct HealthEnvelope: Decodable {
            var ok: Bool?
            var configured: Bool?
            var providerReachable: Bool?
            var message: String?

            enum CodingKeys: String, CodingKey {
                case ok
                case configured
                case providerReachable = "provider_reachable"
                case message
            }
        }
        let health = (try? decoder.decode(HealthEnvelope.self, from: data)) ?? HealthEnvelope()
        return AMapHealthStatus(
            isConfigured: health.configured ?? health.ok ?? true,
            providerReachable: health.providerReachable ?? health.ok ?? true,
            message: health.message ?? "代理服务已连接",
            latencyMilliseconds: latency
        )
    }

    private func fetch(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        let request = try makeRequest(path: path, queryItems: queryItems)
        try await rateLimiter.acquire()
        let response: HTTPResponse
        do {
            response = try await http.data(for: request)
        } catch let error as RouteProviderError {
            throw error
        } catch {
            throw RouteProviderError.map(error)
        }

        guard response.isSuccess else {
            throw mapHTTPError(response)
        }
        if let proxyError = try? decoder.decode(ProxyErrorEnvelope.self, from: response.data),
           let error = proxyError.error,
           error.code != nil {
            // A proxy may return a JSON error envelope with a 2xx status. Do
            // not silently accept it as route data.
            throw mapProxyError(code: error.code, message: error.message, statusCode: response.statusCode)
        }
        return response.data
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw RouteProviderError.missingConfiguration("高德代理地址无效。")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw RouteProviderError.missingConfiguration("高德代理地址无效。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios/\(AppInfo.version)", forHTTPHeaderField: "X-DriveTime-Client")
        if let token = configuration.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func coordinateParameter(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude)
    }

    private func mapHTTPError(_ response: HTTPResponse) -> RouteProviderError {
        let envelope = try? decoder.decode(ProxyErrorEnvelope.self, from: response.data)
        if let error = envelope?.error, let code = error.code {
            return mapProxyError(code: code, message: error.message, statusCode: response.statusCode)
        }
        switch response.statusCode {
        case 401, 403:
            return .unauthorized
        case 404:
            return .providerUnavailable("高德代理服务")
        case 429:
            return .rateLimited(retryAfter: nil)
        case 500...599:
            return .serverUnavailable
        default:
            return .httpStatus(response.statusCode, code: nil)
        }
    }

    private func mapProxyError(code: String?, message: String?, statusCode: Int) -> RouteProviderError {
        let code = (code ?? "").uppercased()
        AppLog.routing.error("AMap proxy error \(code, privacy: .public), HTTP \(statusCode, privacy: .public)")
        switch code {
        case "UNAUTHORIZED", "AMAP_INVALID_KEY":
            return .unauthorized
        case "RATE_LIMITED":
            return .rateLimited(retryAfter: nil)
        case "AMAP_QUOTA":
            return .quotaExceeded
        case "AMAP_NO_ROUTE":
            return .noRoute
        case "PROXY_NOT_CONFIGURED":
            return .missingConfiguration("高德代理服务尚未配置 API Key。")
        case "BAD_REQUEST":
            return .providerRejected(code: code, message: "路线请求参数无效，请重新选择地点。")
        default:
            if code.hasPrefix("AMAP_") {
                return AMapResponseMapper.mapProviderError(infocode: String(code.dropFirst("AMAP_".count)))
            }
            if statusCode == 429 {
                return .rateLimited(retryAfter: nil)
            }
            if statusCode >= 500 {
                return .serverUnavailable
            }
            return .providerRejected(code: code.isEmpty ? "unknown" : code, message: "地图服务暂时无法完成这次查询，请稍后重试。")
        }
    }
}

struct AMapRoutingProvider: RoutingProvider {
    let providerID: RouteProviderID = .amap
    let capabilities: ProviderCapabilities = .amap
    private let client: AMapAPIClient

    init(
        configuration: AMapProxyConfiguration,
        http: any HTTPPerforming = URLSessionHTTPClient()
    ) {
        self.client = AMapAPIClient(configuration: configuration, http: http)
    }

    func calculateRoutes(for request: RouteRequest) async throws -> ProviderRouteResult {
        let data = try await client.driving(
            origin: request.origin.coordinate,
            destination: request.destination.coordinate,
            strategy: request.strategy,
            originPOIID: request.origin.provider == .amap ? request.origin.providerPlaceID : nil,
            destinationPOIID: request.destination.provider == .amap ? request.destination.providerPlaceID : nil
        )
        let fetchedAt = Date()
        return try AMapResponseMapper.drivingRoutes(
            from: data,
            request: request,
            fetchedAt: fetchedAt
        )
    }

    func searchPlaces(query: String, near: GeoCoordinate?) async throws -> [LocationResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let data = try await client.searchPlaces(query: trimmed)
        return try AMapResponseMapper.places(from: data, fetchedAt: Date())
    }

    func healthCheck() async throws -> AMapHealthStatus {
        try await client.health()
    }
}

import Foundation

struct HTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
    var headers: [String: String]

    var isSuccess: Bool { (200..<300).contains(statusCode) }
}

protocol HTTPPerforming: Sendable {
    func data(for request: URLRequest) async throws -> HTTPResponse
}

struct HTTPRequestPolicy: Sendable {
    var maxAttempts: Int = 3
    var baseRetryDelay: TimeInterval = 0.6
    var maximumRetryDelay: TimeInterval = 3.0

    static let `default` = HTTPRequestPolicy()
}

/// URLSession-backed client with cancellation, request timeouts and bounded
/// retries for transient failures. It never performs synchronous networking.
actor URLSessionHTTPClient: HTTPPerforming {
    private let session: URLSession
    private let policy: HTTPRequestPolicy

    init(
        configuration: URLSessionConfiguration = .ephemeral,
        policy: HTTPRequestPolicy = .default
    ) {
        let config = configuration
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)
        self.policy = policy
    }

    func data(for request: URLRequest) async throws -> HTTPResponse {
        var lastError: Error?

        for attempt in 1...max(1, policy.maxAttempts) {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw RouteProviderError.invalidResponse("非 HTTP 响应")
                }
                let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                    if let key = pair.key as? String {
                        result[key] = String(describing: pair.value)
                    }
                }
                let response = HTTPResponse(
                    data: data,
                    statusCode: http.statusCode,
                    headers: headers
                )
                if shouldRetry(statusCode: http.statusCode), attempt < policy.maxAttempts {
                    let delay = retryDelay(attempt: attempt, response: response)
                    AppLog.network.warning("HTTP \(http.statusCode, privacy: .public); retrying in \(delay, format: .fixed(precision: 1))s")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                return response
            } catch is CancellationError {
                throw RouteProviderError.cancelled
            } catch let error as RouteProviderError {
                throw error
            } catch let error as URLError {
                if error.code == .cancelled {
                    throw RouteProviderError.cancelled
                }
                lastError = error
                if isTransient(error), attempt < policy.maxAttempts {
                    let delay = min(
                        policy.maximumRetryDelay,
                        policy.baseRetryDelay * pow(2, Double(attempt - 1))
                    )
                    AppLog.network.warning("Transient network error \(error.code.rawValue, privacy: .public); retrying")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw RouteProviderError.map(error)
            } catch {
                throw RouteProviderError.map(error)
            }
        }

        throw RouteProviderError.map(lastError ?? RouteProviderError.unknown)
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        [408, 429, 500, 502, 503, 504].contains(statusCode)
    }

    private func retryDelay(attempt: Int, response: HTTPResponse) -> TimeInterval {
        if let value = response.headers.first(where: { $0.key.lowercased() == "retry-after" })?.value,
           let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
            return min(policy.maximumRetryDelay, max(0.2, seconds))
        }
        return min(
            policy.maximumRetryDelay,
            policy.baseRetryDelay * pow(2, Double(attempt - 1))
        )
    }

    private func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

actor RateLimiter {
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var lastRequestAt: Date?

    init(minimumInterval: TimeInterval, now: @escaping @Sendable () -> Date = { Date() }) {
        self.minimumInterval = max(0, minimumInterval)
        self.now = now
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if let lastRequestAt {
            let elapsed = now().timeIntervalSince(lastRequestAt)
            let remaining = minimumInterval - elapsed
            if remaining > 0 {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                try Task.checkCancellation()
            }
        }
        lastRequestAt = now()
    }
}

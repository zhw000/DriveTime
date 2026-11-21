import Foundation

enum RouteProviderError: Error, Equatable, Sendable {
    case missingConfiguration(String)
    case providerUnavailable(String)
    case noRoute
    case sameLocation
    case invalidResponse(String)
    case missingRouteData(String)
    case missingRouteGeometry
    case providerRejected(code: String, message: String)
    case httpStatus(Int, code: String?)
    case unauthorized
    case quotaExceeded
    case rateLimited(retryAfter: TimeInterval?)
    case networkUnavailable
    case timedOut
    case cancelled
    case locationPermissionDenied
    case locationAccuracyInsufficient
    case locationUnavailable
    case unsupportedRegion
    case serverUnavailable
    case decodingFailed
    case unknown

    var isCancellation: Bool { self == .cancelled }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .timedOut, .serverUnavailable:
            return true
        case .httpStatus(let status, _):
            return status == 408 || status == 429 || status >= 500
        case .rateLimited:
            return true
        default:
            return false
        }
    }

    var userMessage: String {
        switch self {
        case .missingConfiguration(let detail):
            return detail
        case .providerUnavailable(let provider):
            return "\(provider)暂时不可用，请稍后重试或切换地图服务。"
        case .noRoute:
            return "没有找到可用的驾车路线，请尝试更换起点或终点。"
        case .sameLocation:
            return "起点和终点太近了，请选择两个不同的地点。"
        case .invalidResponse, .missingRouteData, .decodingFailed:
            return "地图服务返回的数据不完整，暂时无法计算这条路线。"
        case .missingRouteGeometry:
            return "地图服务没有返回路线轨迹，无法在地图上绘制这段行程。"
        case .providerRejected(_, let message):
            return message.isEmpty ? "地图服务暂时无法完成这次查询，请稍后重试。" : message
        case .httpStatus:
            return "地图服务暂时无法响应，请稍后再试。"
        case .unauthorized:
            return "地图服务鉴权失败，请检查代理配置与访问令牌。"
        case .quotaExceeded:
            return "地图服务今日配额可能已用完，请稍后再试。"
        case .rateLimited:
            return "查询有些频繁，请稍等几秒再刷新。"
        case .networkUnavailable:
            return "网络连接似乎中断了，请检查网络后重试。"
        case .timedOut:
            return "获取路线超时了，请稍后重试。"
        case .cancelled:
            return "查询已取消。"
        case .locationPermissionDenied:
            return "需要定位权限才能使用当前位置。你可以在系统设置中开启。"
        case .locationAccuracyInsufficient:
            return "当前位置精度不足，请移动到开阔处后重试。"
        case .locationUnavailable:
            return "暂时无法获取当前位置，请稍后再试。"
        case .unsupportedRegion:
            return "当前地区暂不支持这条路线查询。"
        case .serverUnavailable:
            return "路线服务暂时不可用，请稍后重试。"
        case .unknown:
            return "暂时无法获取这条路线，请检查网络后重试。"
        }
    }

    var technicalDescription: String {
        switch self {
        case .missingConfiguration(let detail):
            return "missingConfiguration: \(detail)"
        case .providerUnavailable(let provider):
            return "providerUnavailable: \(provider)"
        case .noRoute:
            return "noRoute"
        case .sameLocation:
            return "sameLocation"
        case .invalidResponse(let detail):
            return "invalidResponse: \(detail)"
        case .missingRouteData(let detail):
            return "missingRouteData: \(detail)"
        case .missingRouteGeometry:
            return "missingRouteGeometry"
        case .providerRejected(let code, let message):
            return "providerRejected: \(code), \(message)"
        case .httpStatus(let status, let code):
            return "httpStatus: \(status), code: \(code ?? "nil")"
        case .unauthorized:
            return "unauthorized"
        case .quotaExceeded:
            return "quotaExceeded"
        case .rateLimited(let retryAfter):
            return "rateLimited: \(retryAfter.map(String.init) ?? "nil")"
        case .networkUnavailable:
            return "networkUnavailable"
        case .timedOut:
            return "timedOut"
        case .cancelled:
            return "cancelled"
        case .locationPermissionDenied:
            return "locationPermissionDenied"
        case .locationAccuracyInsufficient:
            return "locationAccuracyInsufficient"
        case .locationUnavailable:
            return "locationUnavailable"
        case .unsupportedRegion:
            return "unsupportedRegion"
        case .serverUnavailable:
            return "serverUnavailable"
        case .decodingFailed:
            return "decodingFailed"
        case .unknown:
            return "unknown"
        }
    }

    static func map(_ error: Error) -> RouteProviderError {
        if let providerError = error as? RouteProviderError {
            return providerError
        }
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled:
                return .cancelled
            case NSURLErrorTimedOut:
                return .timedOut
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed:
                return .networkUnavailable
            default:
                return .networkUnavailable
            }
        }
        return .unknown
    }
}

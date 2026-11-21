import CoreLocation
import Foundation

enum RouteProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMaps = "apple_maps"
    case amap = "amap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMaps: "Apple 地图"
        case .amap: "高德地图"
        }
    }

    var shortName: String {
        switch self {
        case .appleMaps: "Apple"
        case .amap: "高德"
        }
    }

    var iconName: String {
        switch self {
        case .appleMaps: "apple.logo"
        case .amap: "map.fill"
        }
    }

    var attribution: String {
        switch self {
        case .appleMaps: "路线与地点由 Apple MapKit 提供"
        case .amap: "路线与路况由高德地图 Web 服务经代理提供"
        }
    }
}

enum ProviderPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case appleMaps
    case amap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "自动"
        case .appleMaps: "Apple 地图"
        case .amap: "高德地图"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "优先高德（已配置时），不可用时回退 Apple 地图"
        case .appleMaps: "使用 Apple MapKit，无需额外配置"
        case .amap: "使用高德路径规划 2.0，需要代理服务"
        }
    }
}

enum RouteStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case recommended
    case fastest
    case avoidCongestion
    case avoidTolls
    case avoidHighways
    case highwayFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recommended: "智能推荐"
        case .fastest: "时间优先"
        case .avoidCongestion: "躲避拥堵"
        case .avoidTolls: "少收费"
        case .avoidHighways: "不走高速"
        case .highwayFirst: "高速优先"
        }
    }

    var shortDetail: String {
        switch self {
        case .recommended: "综合时间、距离与路况"
        case .fastest: "优先选择预计耗时最短的路线"
        case .avoidCongestion: "尽量绕开拥堵路段"
        case .avoidTolls: "优先减少收费路段"
        case .avoidHighways: "尽量不经过高速公路"
        case .highwayFirst: "优先选择高速公路"
        }
    }

    var iconName: String {
        switch self {
        case .recommended: "sparkles"
        case .fastest: "bolt.fill"
        case .avoidCongestion: "car.side.fill"
        case .avoidTolls: "banknote"
        case .avoidHighways: "road.lanes"
        case .highwayFirst: "road.lanes.curved.left"
        }
    }

    /// AMap Route Planning 2.0 driving strategy values. These intentionally
    /// differ from the v3 API and must not be mixed.
    var amapStrategyCode: Int {
        switch self {
        case .recommended: 32
        case .fastest: 38
        case .avoidCongestion: 33
        case .avoidTolls: 36
        case .avoidHighways: 35
        case .highwayFirst: 34
        }
    }
}

enum ProviderConfigurationState: String, Sendable {
    case ready
    case requiresProxy
    case unavailable
}

struct ProviderCapabilities: Hashable, Sendable {
    let supportsAlternateRoutes: Bool
    let supportsTollAmounts: Bool
    let supportsTrafficSegments: Bool
    let supportsFutureTraffic: Bool
    let supportsPlaceSearch: Bool
    let supportsETAOnly: Bool
    let strategies: [RouteStrategy]
    let configurationState: ProviderConfigurationState

    static let appleMaps = ProviderCapabilities(
        supportsAlternateRoutes: true,
        supportsTollAmounts: false,
        supportsTrafficSegments: false,
        supportsFutureTraffic: false,
        supportsPlaceSearch: true,
        supportsETAOnly: true,
        strategies: [.recommended],
        configurationState: .ready
    )

    static let amap = ProviderCapabilities(
        supportsAlternateRoutes: false,
        supportsTollAmounts: true,
        supportsTrafficSegments: true,
        supportsFutureTraffic: false,
        supportsPlaceSearch: true,
        supportsETAOnly: false,
        strategies: RouteStrategy.allCases,
        configurationState: .ready
    )
}

enum ProviderConfigurationError: Error, Equatable, Sendable {
    case missingProxy
    case invalidProxyURL
    case unauthorized
}

struct AMapProxyConfiguration: Hashable, Sendable {
    let baseURL: URL
    let accessToken: String?

    var normalizedDescription: String {
        baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

enum RouteDataKind: String, Codable, Sendable {
    case live
    case historical
    case demo

    var displayName: String {
        switch self {
        case .live: "实时查询"
        case .historical: "历史记录"
        case .demo: "演示数据"
        }
    }
}

enum ForecastAvailability: String, Codable, Sendable {
    /// The traffic figures were calculated for the current moment.
    case currentConditions
    /// The provider explicitly supports traffic predictions for the requested
    /// departure time.
    case predictedForDeparture
    /// The user picked a future departure but the provider only supplies
    /// present-moment traffic. The UI must label the extrapolation.
    case projectedFromCurrent
    case unknown

    var supportsTruePrediction: Bool {
        self == .predictedForDeparture
    }
}

enum LocationSource: String, Codable, Sendable {
    case appleMapKit
    case amap
    case currentLocation
    case mapSelection
    case savedPlace

    var displayName: String {
        switch self {
        case .appleMapKit: "Apple 地图地点"
        case .amap: "高德地点"
        case .currentLocation: "当前位置"
        case .mapSelection: "地图选点"
        case .savedPlace: "收藏地点"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric
    case imperial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metric: "公里 / 米"
        case .imperial: "英里 / 英尺"
        }
    }
}

enum TimeFormatPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case twentyFourHour
    case twelveHour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .twentyFourHour: "24 小时"
        case .twelveHour: "12 小时"
        }
    }
}

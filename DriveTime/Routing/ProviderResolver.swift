import Foundation

struct ProviderResolution: Sendable {
    var provider: any RoutingProvider
    /// Only automatic mode supplies an Apple fallback when the preferred AMap
    /// proxy request fails. The UI is told when the fallback was used.
    var fallback: (any RoutingProvider)?
    var isAutomaticSelection: Bool
}

protocol RoutingProviderResolving: Sendable {
    func resolve(
        preference: ProviderPreference,
        origin: GeoCoordinate,
        destination: GeoCoordinate,
        proxy: AMapProxyConfiguration?
    ) throws -> ProviderResolution
}

struct DefaultRoutingProviderResolver: RoutingProviderResolving {
    private let makeApple: @Sendable () -> any RoutingProvider
    private let makeAMap: @Sendable (AMapProxyConfiguration) -> any RoutingProvider

    init(
        makeApple: @escaping @Sendable () -> any RoutingProvider = { AppleMapRoutingProvider() },
        makeAMap: @escaping @Sendable (AMapProxyConfiguration) -> any RoutingProvider = {
            AMapRoutingProvider(configuration: $0)
        }
    ) {
        self.makeApple = makeApple
        self.makeAMap = makeAMap
    }

    func resolve(
        preference: ProviderPreference,
        origin: GeoCoordinate,
        destination: GeoCoordinate,
        proxy: AMapProxyConfiguration?
    ) throws -> ProviderResolution {
        let apple = makeApple()
        switch preference {
        case .appleMaps:
            return ProviderResolution(provider: apple, fallback: nil, isAutomaticSelection: false)
        case .amap:
            guard let proxy else {
                throw RouteProviderError.missingConfiguration(
                    "高德地图尚未配置代理地址。请前往设置填写 Cloudflare Worker 地址。"
                )
            }
            return ProviderResolution(
                provider: makeAMap(proxy),
                fallback: nil,
                isAutomaticSelection: false
            )
        case .automatic:
            guard let proxy,
                  origin.isInMainlandChina,
                  destination.isInMainlandChina else {
                return ProviderResolution(provider: apple, fallback: nil, isAutomaticSelection: true)
            }
            return ProviderResolution(
                provider: makeAMap(proxy),
                fallback: apple,
                isAutomaticSelection: true
            )
        }
    }
}

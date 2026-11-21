import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let provider = "drivetime.provider"
        static let strategy = "drivetime.strategy"
        static let distanceUnit = "drivetime.distanceUnit"
        static let timeFormat = "drivetime.timeFormat"
        static let trafficLayer = "drivetime.trafficLayer"
        static let proxyBaseURL = "drivetime.proxyBaseURL"
        static let proxyToken = "proxyAccessToken"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStoring
    private let infoDefaultProxyURL: String

    var preferredProvider: ProviderPreference {
        didSet { defaults.set(preferredProvider.rawValue, forKey: Key.provider) }
    }

    var defaultStrategy: RouteStrategy {
        didSet { defaults.set(defaultStrategy.rawValue, forKey: Key.strategy) }
    }

    var distanceUnit: DistanceUnit {
        didSet { defaults.set(distanceUnit.rawValue, forKey: Key.distanceUnit) }
    }

    var timeFormat: TimeFormatPreference {
        didSet { defaults.set(timeFormat.rawValue, forKey: Key.timeFormat) }
    }

    var showTrafficLayer: Bool {
        didSet { defaults.set(showTrafficLayer, forKey: Key.trafficLayer) }
    }

    var proxyBaseURLString: String {
        didSet { defaults.set(proxyBaseURLString, forKey: Key.proxyBaseURL) }
    }

    private(set) var proxyAccessToken: String

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainStore(),
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.infoDefaultProxyURL = (infoDictionary["DriveTimeDefaultProxyBaseURL"] as? String) ?? ""

        let storedProvider = defaults.string(forKey: Key.provider)
        self.preferredProvider = ProviderPreference(rawValue: storedProvider ?? "") ?? .automatic
        let storedStrategy = defaults.string(forKey: Key.strategy)
        self.defaultStrategy = RouteStrategy(rawValue: storedStrategy ?? "") ?? .recommended
        let storedUnit = defaults.string(forKey: Key.distanceUnit)
        self.distanceUnit = DistanceUnit(rawValue: storedUnit ?? "") ?? .metric
        let storedTime = defaults.string(forKey: Key.timeFormat)
        self.timeFormat = TimeFormatPreference(rawValue: storedTime ?? "") ?? .system
        self.showTrafficLayer = defaults.object(forKey: Key.trafficLayer) as? Bool ?? false

        let storedProxy = defaults.string(forKey: Key.proxyBaseURL)
        if let storedProxy, !storedProxy.isEmpty {
            self.proxyBaseURLString = storedProxy
        } else {
            self.proxyBaseURLString = Self.sanitizeURLString(infoDefaultProxyURL)
        }
        self.proxyAccessToken = keychain.read(key: Key.proxyToken) ?? ""
    }

    var proxyConfiguration: AMapProxyConfiguration? {
        guard let url = Self.validatedProxyURL(from: proxyBaseURLString) else { return nil }
        let token = proxyAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return AMapProxyConfiguration(
            baseURL: url,
            accessToken: token.isEmpty ? nil : token
        )
    }

    var proxyConfigurationState: ProviderConfigurationState {
        if proxyConfiguration != nil { return .ready }
        if proxyBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .requiresProxy
        }
        return .unavailable
    }

    var proxyURLValidationMessage: String? {
        let trimmed = proxyBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard Self.validatedProxyURL(from: trimmed) != nil else {
            return "请输入 https:// 开头的有效代理地址（本地开发可用 http://127.0.0.1）。"
        }
        return nil
    }

    var displayFormatter: DateDisplayFormatter {
        DateDisplayFormatter(timeFormat: timeFormat)
    }

    func configuredProviderKind(for origin: GeoCoordinate, destination: GeoCoordinate) -> RouteProviderID {
        switch preferredProvider {
        case .appleMaps:
            return .appleMaps
        case .amap:
            return .amap
        case .automatic:
            if proxyConfiguration != nil,
               origin.isInMainlandChina,
               destination.isInMainlandChina {
                return .amap
            }
            return .appleMaps
        }
    }

    func availableStrategies() -> [RouteStrategy] {
        switch preferredProvider {
        case .appleMaps:
            return [.recommended]
        case .amap:
            return proxyConfiguration == nil ? [.recommended] : RouteStrategy.allCases
        case .automatic:
            return proxyConfiguration == nil ? [.recommended] : RouteStrategy.allCases
        }
    }

    func setProxyAccessToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        proxyAccessToken = trimmed
        do {
            if trimmed.isEmpty {
                keychain.delete(key: Key.proxyToken)
            } else {
                try keychain.write(trimmed, key: Key.proxyToken)
            }
        } catch {
            AppLog.settings.error("Unable to persist proxy token: \(String(describing: error), privacy: .public)")
        }
    }

    static func sanitizeURLString(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    static func validatedProxyURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        guard scheme == "https" || (scheme == "http" && isLocalHost(host)) else {
            return nil
        }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        while components.path.hasSuffix("/") && components.path.count > 1 {
            components.path.removeLast()
        }
        if components.path == "/" {
            components.path = ""
        }
        return components.url
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

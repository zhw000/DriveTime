import SwiftUI
import UIKit

struct SettingsView: View {
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var proxyURLInput: String
    @State private var proxyTokenInput: String
    @State private var connectionState: ConnectionState = .idle
    @State private var dataConfirmation: DataConfirmation?

    private enum DataConfirmation: String, Identifiable {
        case history
        case favorites

        var id: String { rawValue }
    }

    private enum ConnectionState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    init(appModel: AppModel) {
        self.appModel = appModel
        _proxyURLInput = State(initialValue: appModel.settings.proxyBaseURLString)
        _proxyTokenInput = State(initialValue: appModel.settings.proxyAccessToken)
    }

    var body: some View {
        @Bindable var settings = appModel.settings
        NavigationStack {
            Form {
                Section {
                    Picker("地图服务", selection: $settings.preferredProvider) {
                        ForEach(ProviderPreference.allCases) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("providerPicker")

                    Text(settings.preferredProvider.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("导航服务")
                } footer: {
                    Text("自动模式在已配置高德代理且起终点位于中国大陆时优先使用高德；高德请求失败时会明确提示并回退到 Apple 地图。")
                }

                Section {
                    LabeledContent("代理状态") {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(proxyStatusColor)
                                .frame(width: 7, height: 7)
                            Text(proxyStatusText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("https://your-worker.workers.dev", text: $proxyURLInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("proxyURLField")

                    SecureField("访问令牌（可选）", text: $proxyTokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("proxyTokenField")

                    if let validation = proxyValidationMessage {
                        Text(validation)
                            .font(.caption)
                            .foregroundStyle(DriveTimeTheme.warning)
                    }

                    Button {
                        saveAndTestProxy()
                    } label: {
                        HStack {
                            Text("保存并测试连接")
                            Spacer()
                            if connectionState == .testing {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(connectionState == .testing)
                    .accessibilityIdentifier("testProxy")

                    switch connectionState {
                    case .idle:
                        EmptyView()
                    case .testing:
                        Text("正在连接代理服务…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .success(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DriveTimeTheme.success)
                    case .failure(let message):
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DriveTimeTheme.danger)
                    }
                } header: {
                    Text("高德路线代理")
                } footer: {
                    Text("高德 Web 服务 Key 只保存在 Cloudflare Worker Secret 中，绝不会写入 App、UserDefaults 或 Git 仓库。DriveTime 未链接高德 iOS SDK，因此不需要按 Bundle ID 绑定高德 SDK 授权；更换签名 Bundle ID 不会影响这条 Web 服务代理链路。")
                }

                Section {
                    Picker("默认路线偏好", selection: $settings.defaultStrategy) {
                        ForEach(settings.availableStrategies()) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .accessibilityIdentifier("defaultStrategyPicker")

                    Text(strategyFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("路线偏好")
                }

                Section {
                    Picker("距离单位", selection: $settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    Picker("时间格式", selection: $settings.timeFormat) {
                        ForEach(TimeFormatPreference.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Toggle("Apple 地图路况图层", isOn: $settings.showTrafficLayer)
                    Text("路况图层只改变地图显示；ETA 始终使用地图服务返回的路线预计耗时。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("显示")
                }

                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: locationIcon)
                            .foregroundStyle(locationColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(locationTitle)
                                .font(.subheadline.weight(.medium))
                            Text(appModel.locationService.permissionExplanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !appModel.locationService.isAuthorized {
                        Button("打开系统设置") {
                            openSettings()
                        }
                    }
                } header: {
                    Text("位置权限")
                } footer: {
                    Text("位置仅用于把当前位置设为行程起点。DriveTime 不保存位置轨迹，也不需要后台定位。")
                }

                Section {
                    Button(role: .destructive) {
                        dataConfirmation = .history
                    } label: {
                        HStack {
                            Text("清空查询历史")
                            Spacer()
                            Text("\(appModel.history.recentRoutes.count) 条")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("clearHistory")

                    Button(role: .destructive) {
                        dataConfirmation = .favorites
                    } label: {
                        HStack {
                            Text("清除收藏地点与路线标记")
                            Spacer()
                            Text("\(appModel.history.favoritePlaces.count + appModel.history.favoriteRoutes.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("本地历史使用 SwiftData 保存。删除后无法恢复；收藏路线不会被“清空历史”移除。")
                }

                Section {
                    LabeledContent("应用", value: "DriveTime")
                    LabeledContent("版本", value: AppInfo.versionDescription)
                    LabeledContent("Bundle ID", value: AppInfo.bundleIdentifier)
                        .font(.caption)
                    Link(
                        "高德 Web 服务路线规划文档",
                        destination: URL(string: "https://lbs.amap.com/api/webservice/guide/api/newroute")!
                    )
                    Link(
                        "Apple MapKit 文档",
                        destination: URL(string: "https://developer.apple.com/documentation/mapkit")!
                    )
                } header: {
                    Text("关于")
                } footer: {
                    Text("DriveTime 不收集账号信息，不包含广告、订阅或分析 SDK。路线查询会发送到所选地图服务（Apple 或你配置的高德代理）。未配置代理时只会使用 Apple 地图。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: settings.preferredProvider) { _, _ in
                if !settings.availableStrategies().contains(settings.defaultStrategy) {
                    settings.defaultStrategy = .recommended
                }
            }
            .onAppear {
                appModel.locationService.refreshAuthorizationStatus()
                if !appModel.settings.availableStrategies().contains(appModel.settings.defaultStrategy) {
                    appModel.settings.defaultStrategy = .recommended
                }
            }
            .alert(
                dataConfirmation == .favorites ? "清除收藏？" : "清空查询历史？",
                isPresented: Binding(
                    get: { dataConfirmation != nil },
                    set: { if !$0 { dataConfirmation = nil } }
                )
            ) {
                Button("清除", role: .destructive) {
                    switch dataConfirmation {
                    case .history:
                        appModel.clearHistory()
                    case .favorites:
                        appModel.history.clearFavorites()
                    case .none:
                        break
                    }
                    dataConfirmation = nil
                }
                Button("取消", role: .cancel) {
                    dataConfirmation = nil
                }
            } message: {
                if dataConfirmation == .favorites {
                    Text("所有收藏地点和路线收藏标记都会被删除。")
                } else {
                    Text("将删除所有非收藏查询记录，收藏路线会保留。")
                }
            }
        }
    }

    private var proxyValidationMessage: String? {
        let trimmed = proxyURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if AppSettings.validatedProxyURL(from: trimmed) == nil {
            return "请输入 https:// 开头的有效地址；本地开发也可以使用 http://127.0.0.1。"
        }
        return nil
    }

    private var proxyStatusText: String {
        switch appModel.settings.proxyConfigurationState {
        case .ready: return "已配置"
        case .requiresProxy: return "未配置"
        case .unavailable: return "地址无效"
        }
    }

    private var proxyStatusColor: Color {
        switch appModel.settings.proxyConfigurationState {
        case .ready: return DriveTimeTheme.success
        case .requiresProxy, .unavailable: return DriveTimeTheme.tertiaryInk
        }
    }

    private var strategyFootnote: String {
        if appModel.settings.availableStrategies() == [.recommended] {
            return "当前服务仅支持智能推荐。Apple 地图不开放躲避拥堵、少收费等筛选参数。"
        }
        return "偏好会作为高德驾车路径规划 2.0 的 strategy 参数发送。Apple 地图只使用智能推荐。"
    }

    private var locationTitle: String {
        if appModel.locationService.isAuthorized {
            return "已允许使用定位"
        }
        if appModel.locationService.authorizationStatus == .denied {
            return "定位权限已关闭"
        }
        return "未请求定位权限"
    }

    private var locationIcon: String {
        appModel.locationService.isAuthorized ? "location.fill" : "location.slash"
    }

    private var locationColor: Color {
        appModel.locationService.isAuthorized ? DriveTimeTheme.origin : DriveTimeTheme.secondaryInk
    }

    private func saveAndTestProxy() {
        proxyURLInput = AppSettings.sanitizeURLString(proxyURLInput)
        appModel.settings.proxyBaseURLString = proxyURLInput
        appModel.settings.setProxyAccessToken(proxyTokenInput)
        guard let configuration = appModel.settings.proxyConfiguration else {
            connectionState = .failure("请先填写有效的代理地址。")
            return
        }
        connectionState = .testing
        Task {
            do {
                let health = try await AMapAPIClient(configuration: configuration).health()
                let latency = health.latencyMilliseconds.map { " · \($0) ms" } ?? ""
                if health.isConfigured {
                    connectionState = .success("代理可达，AMap Key 已配置\(latency)。路线请求时验证实际可用性。")
                } else {
                    connectionState = .failure("代理可达，但 Worker 尚未配置 AMAP_KEY。")
                }
            } catch {
                connectionState = .failure(RouteProviderError.map(error).userMessage)
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

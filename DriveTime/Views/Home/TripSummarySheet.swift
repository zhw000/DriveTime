import SwiftUI

struct TripSummarySheet: View {
    let appModel: AppModel
    @Binding var detent: PresentationDetent
    let onEditEndpoint: (TripEndpoint) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSteps = false
    @ScaledMetric(relativeTo: .largeTitle) private var etaSize: CGFloat = 43

    private var planner: RoutePlannerViewModel { appModel.planner }
    private var settings: AppSettings { appModel.settings }
    private var formatter: DateDisplayFormatter { settings.displayFormatter }
    private var isCompact: Bool { detent == .height(206) }

    var body: some View {
        Group {
            if let plan = planner.plan {
                sheetContent(plan: plan)
            } else {
                unavailableContent
            }
        }
        .background(DriveTimeTheme.surface)
        .accessibilityIdentifier("tripSummary")
    }

    private func sheetContent(plan: RoutePlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryHeader(plan: plan)

                if let error = planner.inlineError {
                    InlineErrorBanner(
                        message: error,
                        actionTitle: "重试",
                        action: { planner.refresh() }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                if isCompact {
                    compactMeta(plan: plan)
                } else {
                    expandedContent(plan: plan)
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.selection, trigger: plan.selectedRouteID)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: plan.selectedRouteID)
    }

    // MARK: - Header

    private func summaryHeader(plan: RoutePlan) -> some View {
        let route = plan.selectedAlternative
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                LabelChip(
                    text: plan.provider.displayName,
                    systemImage: plan.provider.iconName,
                    tint: DriveTimeTheme.secondaryInk
                )
                if plan.usesProjectedTraffic {
                    LabelChip(
                        text: "未来时刻推算",
                        systemImage: "clock.badge.exclamationmark",
                        tint: DriveTimeTheme.warning
                    )
                }
                if plan.dataKind == .demo {
                    LabelChip(
                        text: "演示数据",
                        systemImage: "testtube.2",
                        tint: DriveTimeTheme.danger
                    )
                    .accessibilityIdentifier("demoBadge")
                }
                Spacer(minLength: 0)
                if planner.availableStrategies.count > 1 {
                    Menu {
                        ForEach(planner.availableStrategies) { strategy in
                            Button {
                                planner.setStrategy(strategy)
                            } label: {
                                if strategy == plan.strategy {
                                    Label(strategy.displayName, systemImage: "checkmark")
                                } else {
                                    Text(strategy.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: plan.strategy.iconName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(plan.strategy.displayName)
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(DriveTimeTheme.secondaryInk.opacity(0.09)))
                    }
                    .accessibilityIdentifier("resultStrategyMenu")
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TravelTimeFormatter.string(from: route.expectedTravelTime))
                        .font(.system(size: etaSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DriveTimeTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .accessibilityLabel("预计驾车时间 \(TravelTimeFormatter.string(from: route.expectedTravelTime))")
                        .accessibilityIdentifier("etaSummary")

                    HStack(spacing: 7) {
                        Text(formatter.relativeArrivalString(
                            arrival: plan.arrivalDate,
                            relativeTo: plan.requestedDepartureAt
                        ) + " 抵达")
                        Text("·")
                            .foregroundStyle(DriveTimeTheme.tertiaryInk)
                        Text(DistanceFormatter.string(
                            fromMeters: route.distanceMeters,
                            unit: settings.distanceUnit
                        ))
                    }
                    .font(.subheadline)
                    .foregroundStyle(DriveTimeTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Text("\(plan.origin.name) → \(plan.destination.name)")
                        .font(.footnote)
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                        .lineLimit(1)

                    if plan.usesProjectedTraffic {
                        Text("当前路况推算 · 不代表该时刻的实际交通")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DriveTimeTheme.warning)
                    }
                }
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    refreshButton
                    expandButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 13)
    }

    private var refreshButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = planner.refreshCooldownRemaining
            Button {
                planner.refresh()
            } label: {
                ZStack {
                    Circle()
                        .fill(DriveTimeTheme.surfaceElevated)
                    Circle()
                        .strokeBorder(DriveTimeTheme.hairline.opacity(0.8), lineWidth: 0.5)
                    if planner.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DriveTimeTheme.ink)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                remaining > 0
                                    ? DriveTimeTheme.tertiaryInk
                                    : DriveTimeTheme.ink
                            )
                    }
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(planner.isRefreshing || remaining > 0)
            .accessibilityLabel(
                planner.isRefreshing
                    ? "正在刷新路况"
                    : remaining > 0
                        ? "\(remaining) 秒后可刷新路况"
                        : "刷新路况"
            )
            .accessibilityIdentifier("refreshRoute")
        }
    }

    private var expandButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.32)) {
                detent = isCompact ? .large : .height(206)
            }
        } label: {
            Image(systemName: isCompact ? "chevron.up" : "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DriveTimeTheme.secondaryInk)
                .frame(width: 38, height: 30)
                .background(Circle().fill(DriveTimeTheme.canvas))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompact ? "展开车程详情" : "收起车程详情")
        .accessibilityIdentifier("expandSheet")
    }

    private func compactMeta(plan: RoutePlan) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DriveTimeTheme.hairline.opacity(0.6))
                .frame(height: 0.5)
            HStack(spacing: 8) {
                Image(systemName: plan.strategy.iconName)
                    .font(.caption)
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
                Text(plan.strategy.displayName)
                Text("·")
                Text(plan.recommendedAlternative.title)
                Spacer()
                Text(formatter.freshnessString(for: plan.fetchedAt))
            }
            .font(.caption)
            .foregroundStyle(DriveTimeTheme.tertiaryInk)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Expanded content

    private func expandedContent(plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionDivider

            if plan.alternatives.count > 1 {
                alternativesSection(plan: plan)
            }

            factsSection(plan: plan)

            trafficSection(plan: plan)

            if !plan.notices.isEmpty || !plan.selectedAlternative.notes.isEmpty {
                noticesSection(plan: plan)
            }

            tollSection(plan: plan)

            stepsSection(plan: plan)

            footerSection(plan: plan)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(DriveTimeTheme.hairline.opacity(0.6))
            .frame(height: 0.5)
    }

    private func alternativesSection(plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                title: "可选路线",
                detail: "\(plan.provider.shortName)提供 \(plan.alternatives.count) 条"
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(plan.alternatives) { route in
                        routeOptionCard(route: route, plan: plan)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func routeOptionCard(route: RouteAlternative, plan: RoutePlan) -> some View {
        let isSelected = route.id == plan.selectedRouteID
        let delta = route.travelTimeDifference(from: plan.recommendedAlternative)
        return Button {
            planner.selectRoute(id: route.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text(route.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DriveTimeTheme.accent)
                    }
                }
                Text(TravelTimeFormatter.string(from: route.expectedTravelTime))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DriveTimeTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    Text(DistanceFormatter.string(
                        fromMeters: route.distanceMeters,
                        unit: settings.distanceUnit
                    ))
                    if !route.isRecommended {
                        Text("·")
                            .foregroundStyle(DriveTimeTheme.tertiaryInk)
                        Text(TravelTimeFormatter.differenceShortString(from: delta))
                    }
                }
                .font(.caption)
                .foregroundStyle(DriveTimeTheme.secondaryInk)
                .lineLimit(1)

                if let toll = route.tollAmountYuan {
                    Text(CurrencyFormatter.yuan(toll))
                        .font(.caption2)
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                } else if route.hasTolls == true {
                    Text("含收费路段")
                        .font(.caption2)
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                }
            }
            .padding(13)
            .frame(width: 174, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? DriveTimeTheme.accent.opacity(0.08) : DriveTimeTheme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? DriveTimeTheme.accent.opacity(0.55) : DriveTimeTheme.hairline.opacity(0.6),
                        lineWidth: isSelected ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(route.title)，\(TravelTimeFormatter.string(from: route.expectedTravelTime))，\(DistanceFormatter.string(fromMeters: route.distanceMeters, unit: settings.distanceUnit))")
        .accessibilityHint(isSelected ? "当前选中" : "轻点切换路线")
        .accessibilityIdentifier("routeOption-\(route.title)")
    }

    private func factsSection(plan: RoutePlan) -> some View {
        let route = plan.selectedAlternative
        return VStack(alignment: .leading, spacing: 13) {
            SectionHeading(title: "路线信息", detail: route.title)
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 15
            ) {
                StatItem(value: departureText(plan.requestedDepartureAt), label: "计划出发")
                StatItem(value: formatter.relativeArrivalString(
                    arrival: plan.arrivalDate,
                    relativeTo: plan.requestedDepartureAt
                ), label: "预计抵达")
                StatItem(value: DistanceFormatter.string(fromMeters: route.distanceMeters, unit: settings.distanceUnit), label: "路线距离")
                StatItem(value: tollShortText(route), label: "过路费")
                StatItem(value: plan.strategy.displayName, label: "规划偏好")
                StatItem(value: formatter.freshnessString(for: plan.fetchedAt), label: "数据时间")
            }
        }
    }

    private func trafficSection(plan: RoutePlan) -> some View {
        let route = plan.selectedAlternative
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                title: "路况",
                detail: route.traffic?.sourceLabel ?? "暂无数据"
            )
            if let traffic = route.traffic, traffic.hasUsableData {
                Text(TrafficSummaryText.summary(for: traffic))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DriveTimeTheme.ink)
                if traffic.segments.allSatisfy({ $0.lengthMeters != nil }),
                   traffic.knownLengthMeters > 0 {
                    TrafficFlowBar(traffic: traffic)
                }
                TrafficLegend()
                Text("以上颜色只代表高德返回的当前分段路况；数据不完整处不推断拥堵等级。")
                    .font(.caption2)
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                    Text(plan.provider == .appleMaps
                        ? "Apple 地图未提供逐路段路况。车程由路线预估返回，地图路况图层可在设置中开启。"
                        : "高德未返回可用的分段路况。")
                        .font(.caption)
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(DriveTimeTheme.canvas)
                )
            }
        }
    }

    private func noticesSection(plan: RoutePlan) -> some View {
        let notes = unique(plan.notices + plan.selectedAlternative.notes)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "路线说明", detail: nil)
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            note.contains("预测") || note.contains("推算")
                                ? DriveTimeTheme.warning
                                : DriveTimeTheme.secondaryInk
                        )
                        .padding(.top, 1)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tollSection(plan: RoutePlan) -> some View {
        let route = plan.selectedAlternative
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "收费与道路", detail: nil)
            VStack(spacing: 0) {
                infoRow(label: "过路费", value: tollLongText(route))
                if let tollDistance = route.tollDistanceMeters, tollDistance > 0 {
                    rowDivider
                    infoRow(
                        label: "收费路段",
                        value: DistanceFormatter.string(fromMeters: tollDistance, unit: settings.distanceUnit)
                    )
                }
                if !route.tollRoads.isEmpty {
                    rowDivider
                    infoRow(label: "收费道路", value: route.tollRoads.prefix(3).joined(separator: "、"))
                }
                if route.tollAmountYuan == nil, route.hasTolls == nil {
                    rowDivider
                    infoRow(label: "收费信息", value: "暂无数据")
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(DriveTimeTheme.canvas)
            )
        }
    }

    private func stepsSection(plan: RoutePlan) -> some View {
        let steps = plan.selectedAlternative.steps
        return VStack(alignment: .leading, spacing: 8) {
            if !steps.isEmpty {
                DisclosureGroup(isExpanded: $showSteps) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(steps.prefix(12)) { step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(step.id + 1)")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(DriveTimeTheme.secondaryInk)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(DriveTimeTheme.canvas))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.instruction)
                                        .font(.footnote)
                                        .foregroundStyle(DriveTimeTheme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if step.distanceMeters > 0 {
                                        Text(DistanceFormatter.string(
                                            fromMeters: step.distanceMeters,
                                            unit: settings.distanceUnit
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                        }
                        if steps.count > 12 {
                            Text("仅显示前 12 个路段，共 \(steps.count) 段。")
                                .font(.caption2)
                                .foregroundStyle(DriveTimeTheme.tertiaryInk)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text("路线详情")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DriveTimeTheme.ink)
                        Text("\(steps.count) 段")
                            .font(.caption)
                            .foregroundStyle(DriveTimeTheme.tertiaryInk)
                        Spacer()
                    }
                }
                .tint(DriveTimeTheme.accent)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(DriveTimeTheme.canvas)
                )
            }
        }
    }

    private func footerSection(plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionDivider

            HStack(spacing: 10) {
                Button {
                    planner.toggleFavoriteForCurrentPlan()
                } label: {
                    Label(
                        planner.isPlanFavorite ? "已收藏" : "收藏行程",
                        systemImage: planner.isPlanFavorite ? "star.fill" : "star"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(
                        planner.isPlanFavorite ? DriveTimeTheme.warning : DriveTimeTheme.secondaryInk
                    )
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(
                        Capsule().fill(DriveTimeTheme.canvas)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!planner.canToggleFavorite)
                .accessibilityIdentifier("favoriteRoute")

                Menu {
                    Button {
                        onEditEndpoint(.origin)
                    } label: {
                        Label("修改起点", systemImage: "circle")
                    }
                    Button {
                        onEditEndpoint(.destination)
                    } label: {
                        Label("修改终点", systemImage: "mappin")
                    }
                } label: {
                    Label("修改行程", systemImage: "arrow.left.arrow.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DriveTimeTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(Capsule().fill(DriveTimeTheme.canvas))
                }
                .accessibilityIdentifier("editTrip")
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(plan.provider.attribution)
                    .font(.caption2)
                    .foregroundStyle(DriveTimeTheme.secondaryInk)
                if plan.provider == .appleMaps {
                    Link(
                        "Apple 地图数据与条款",
                        destination: URL(string: "https://www.apple.com/legal/internet-services/maps/")!
                    )
                    .font(.caption2)
                    .foregroundStyle(DriveTimeTheme.accent)
                }
                Text("查询时间 \(formatter.dateTimeString(for: plan.fetchedAt, includeYear: true)) · \(plan.dataKind.displayName)")
                    .font(.caption2)
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
                Text("路线轨迹与预计时间均来自 \(plan.provider.displayName)；DriveTime 不使用直线距离或固定速度估算。")
                    .font(.caption2)
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unavailableContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DriveTimeTheme.tertiaryInk)
            Text("选择起点和终点后查看车程")
                .font(.headline)
                .foregroundStyle(DriveTimeTheme.ink)
            Text("路线数据将来自真实地图服务。")
                .font(.subheadline)
                .foregroundStyle(DriveTimeTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(DriveTimeTheme.secondaryInk)
            Spacer(minLength: 16)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(DriveTimeTheme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DriveTimeTheme.hairline.opacity(0.6))
            .frame(height: 0.5)
    }

    private func departureText(_ date: Date) -> String {
        let day = formatter.relativeDayString(for: date)
        if ["今天", "明天", "昨天"].contains(day) {
            return "\(day) \(formatter.timeString(for: date))"
        }
        return day
    }

    private func tollShortText(_ route: RouteAlternative) -> String {
        if let toll = route.tollAmountYuan {
            return CurrencyFormatter.yuan(toll)
        }
        if route.hasTolls == true { return "含收费路段" }
        if route.hasTolls == false { return "免费" }
        return "暂无数据"
    }

    private func tollLongText(_ route: RouteAlternative) -> String {
        if let toll = route.tollAmountYuan {
            return "\(CurrencyFormatter.yuan(toll))（高德预估）"
        }
        if route.hasTolls == true { return "含收费路段，金额暂无数据" }
        if route.hasTolls == false { return "未提供收费路段信息" }
        return "暂无数据"
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

private struct TrafficFlowBar: View {
    let traffic: TrafficInformation

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, traffic.segments.reduce(0) { $0 + ($1.lengthMeters ?? 0) })
            HStack(spacing: 1) {
                ForEach(traffic.segments) { segment in
                    let fraction = (segment.lengthMeters ?? 0) / total
                    Rectangle()
                        .fill(segment.level.color)
                        .frame(width: max(2, proxy.size.width * fraction))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "路况分布，" + traffic.segments
                .filter { $0.level != .unknown }
                .map { "\($0.level.displayName) \(Int(($0.lengthMeters ?? 0).rounded())) 米" }
                .joined(separator: "，")
        )
    }
}

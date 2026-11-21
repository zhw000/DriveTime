import MapKit
import SwiftUI

private enum RootModal: Identifiable {
    case result
    case search(TripEndpoint)
    case settings
    case history
    case departure

    var id: String {
        switch self {
        case .result: "result"
        case .search(let endpoint): "search-\(endpoint.rawValue)"
        case .settings: "settings"
        case .history: "history"
        case .departure: "departure"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModelModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.2, longitude: 120.1),
            span: MKCoordinateSpan(latitudeDelta: 3.6, longitudeDelta: 3.6)
        )
    )
    @State private var modal: RootModal?
    @State private var resultDetent: PresentationDetent = .height(206)

    private var appModel: AppModel { appModelModel }
    private var planner: RoutePlannerViewModel { appModelModel.planner }
    private var isCompactHeight: Bool { verticalSizeClass == .compact }
    private var isResultPresented: Bool {
        if case .result = modal { return true }
        return false
    }

    private var uiTestColorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DriveTimeDarkMode") {
            return .dark
        }
        #endif
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                MapCanvasView(
                    plan: planner.plan,
                    showTrafficLayer: appModel.settings.showTrafficLayer,
                    showsUserLocation: appModel.locationService.isAuthorized,
                    camera: $camera
                )
                .ignoresSafeArea()

                topScrim

                if isResultPresented {
                    resultSheetPresentedHeader
                } else {
                    controls(proxy: proxy)
                }

                if !isResultPresented {
                    bottomOverlay
                }
            }
        }
        .background(DriveTimeTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(uiTestColorScheme)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-DriveTimeDemo") {
                appModel.planner.activateUITestDemo()
            }
            #endif
        }
        .onChange(of: planner.plan?.id) { _, newValue in
            guard newValue != nil else { return }
            if !isResultPresented, modal == nil {
                resultDetent = .height(206)
                modal = .result
            }
        }
        .sheet(item: $modal) { destination in
            modalContent(destination)
        }
    }

    @ViewBuilder
    private func modalContent(_ destination: RootModal) -> some View {
        switch destination {
        case .result:
            TripSummarySheet(
                appModel: appModel,
                detent: $resultDetent,
                onEditEndpoint: beginEditing
            )
            .presentationDetents(
                [.height(206), .medium, .large],
                selection: $resultDetent
            )
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationBackground(DriveTimeTheme.surface)
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
        case .search(let endpoint):
            PlaceSearchView(
                endpoint: endpoint,
                appModel: appModel,
                initialCoordinate: otherEndpointCoordinate(for: endpoint),
                onSelect: { location in
                    planner.setEndpoint(location, for: endpoint)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        case .settings:
            SettingsView(appModel: appModel)
                .presentationDetents([.large])
        case .history:
            HistoryView(appModel: appModel) { savedRoute in
                modal = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    planner.loadSavedTrip(savedRoute)
                }
            }
            .presentationDetents([.large])
        case .departure:
            DeparturePickerView(
                currentChoice: planner.departureChoice,
                now: Date(),
                formatter: appModel.settings.displayFormatter
            ) { choice in
                planner.setDepartureChoice(choice)
            }
            .presentationDetents([.height(430), .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func controls(proxy: GeometryProxy) -> some View {
        if isCompactHeight {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 10) {
                    header
                    searchCard
                    errorBanner
                }
                .frame(width: min(370, max(300, proxy.size.width * 0.46)))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        } else {
            VStack(spacing: 10) {
                header
                searchCard
                errorBanner
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                brandMark
                Text("DriveTime")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(DriveTimeTheme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            CircleIconButton(systemName: "clock.arrow.circlepath", accessibilityLabel: "历史记录") {
                modal = .history
            }
            .accessibilityIdentifier("historyButton")
            CircleIconButton(systemName: "gearshape", accessibilityLabel: "设置") {
                modal = .settings
            }
            .accessibilityIdentifier("settingsButton")
        }
        .padding(.horizontal, 2)
    }

    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DriveTimeTheme.ink)
                .frame(width: 30, height: 30)
            Path { path in
                path.move(to: CGPoint(x: 10, y: 23))
                path.addCurve(
                    to: CGPoint(x: 21, y: 8),
                    control1: CGPoint(x: 8, y: 14),
                    control2: CGPoint(x: 22, y: 17)
                )
            }
            .stroke(DriveTimeTheme.surface, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            Circle()
                .fill(DriveTimeTheme.accent)
                .frame(width: 7, height: 7)
                .offset(x: 6, y: -7)
        }
        .accessibilityHidden(true)
    }

    private var searchCard: some View {
        TripSearchCard(
            origin: planner.origin,
            destination: planner.destination,
            isCalculating: planner.isBusy,
            availableStrategies: planner.availableStrategies,
            selectedStrategy: selectedStrategyForDisplay,
            departureLabel: departureLabel,
            onOriginTap: { modal = .search(.origin) },
            onDestinationTap: { modal = .search(.destination) },
            onSwap: { planner.swapEndpoints() },
            onCalculate: { planner.calculateRoute() },
            onDepartureTap: { modal = .departure },
            onStrategySelected: { planner.setStrategy($0) }
        )
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = planner.errorMessage {
            InlineErrorBanner(
                message: message,
                actionTitle: planner.origin != nil && planner.destination != nil ? "重试" : nil,
                action: planner.origin != nil && planner.destination != nil
                    ? { planner.calculateRoute() }
                    : nil
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var topScrim: some View {
        LinearGradient(
            stops: [
                .init(color: DriveTimeTheme.canvas.opacity(0.94), location: 0),
                .init(color: DriveTimeTheme.canvas.opacity(0.68), location: 0.55),
                .init(color: DriveTimeTheme.canvas.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: isCompactHeight ? 260 : 330)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var resultSheetPresentedHeader: some View {
        HStack {
            HStack(spacing: 9) {
                brandMark
                Text("DriveTime")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DriveTimeTheme.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(DriveTimeTheme.hairline.opacity(0.5), lineWidth: 0.5))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack {
            Spacer()
            if let plan = planner.plan, !isResultPresented {
                reopenResultButton(plan: plan)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else if planner.plan == nil,
                      !planner.isBusy,
                      planner.origin == nil,
                      planner.destination == nil,
                      !isCompactHeight {
                recentTripsStrip
                    .padding(.bottom, 8)
            }
        }
    }

    private func reopenResultButton(plan: RoutePlan) -> some View {
        Button {
            resultDetent = .height(206)
            modal = .result
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TravelTimeFormatter.string(from: plan.selectedAlternative.expectedTravelTime))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(DistanceFormatter.string(fromMeters: plan.selectedAlternative.distanceMeters, unit: appModel.settings.distanceUnit)) · \(arrivalText(for: plan)) 抵达")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DriveTimeTheme.ink)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看车程详情")
    }

    @ViewBuilder
    private var recentTripsStrip: some View {
        let recents = Array(appModel.history.recentRoutes.prefix(3))
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最近行程")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                    Spacer()
                    Button("全部") {
                        modal = .history
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DriveTimeTheme.accent)
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recents) { saved in
                            Button {
                                planner.loadSavedTrip(saved)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(saved.destinationName)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(DriveTimeTheme.ink)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(TravelTimeFormatter.compactString(from: saved.durationSeconds))
                                        Text("·")
                                        Text(DistanceFormatter.compactString(
                                            fromMeters: saved.distanceMeters,
                                            unit: appModel.settings.distanceUnit
                                        ))
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(DriveTimeTheme.secondaryInk)
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .frame(minWidth: 132, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(.regularMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(DriveTimeTheme.hairline.opacity(0.6), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var selectedStrategyForDisplay: RouteStrategy {
        if planner.availableStrategies.contains(planner.selectedStrategy) {
            return planner.selectedStrategy
        }
        return planner.availableStrategies.first ?? .recommended
    }

    private var departureLabel: String {
        switch planner.departureChoice {
        case .now:
            return "现在出发"
        case .scheduled(let date):
            guard date > Date() else { return "现在出发" }
            let formatter = appModel.settings.displayFormatter
            return "\(formatter.relativeDayString(for: date)) \(formatter.timeString(for: date)) 出发"
        }
    }

    private func arrivalText(for plan: RoutePlan) -> String {
        let formatter = appModel.settings.displayFormatter
        return formatter.timeString(for: plan.arrivalDate)
    }

    private func otherEndpointCoordinate(for endpoint: TripEndpoint) -> GeoCoordinate? {
        switch endpoint {
        case .origin:
            return planner.destination?.coordinate
        case .destination:
            return planner.origin?.coordinate
        }
    }

    private func beginEditing(_ endpoint: TripEndpoint) {
        modal = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            modal = .search(endpoint)
        }
    }
}

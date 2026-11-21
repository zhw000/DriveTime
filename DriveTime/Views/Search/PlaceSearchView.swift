import CoreLocation
import SwiftUI
import UIKit

struct PlaceSearchView: View {
    let endpoint: TripEndpoint
    let appModel: AppModel
    let initialCoordinate: GeoCoordinate?
    let onSelect: (LocationResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PlaceSearchViewModel
    @State private var showMapPicker = false
    @FocusState private var searchFocused: Bool

    init(
        endpoint: TripEndpoint,
        appModel: AppModel,
        initialCoordinate: GeoCoordinate?,
        onSelect: @escaping (LocationResult) -> Void
    ) {
        self.endpoint = endpoint
        self.appModel = appModel
        self.initialCoordinate = initialCoordinate
        self.onSelect = onSelect
        _viewModel = State(initialValue: appModel.makePlaceSearchViewModel(for: endpoint))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, DriveTimeTheme.contentPadding)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let message = viewModel.errorMessage {
                        InlineErrorBanner(
                            message: message,
                            actionTitle: "打开系统设置",
                            action: openSystemSettings
                        )
                        .padding(.horizontal, DriveTimeTheme.contentPadding)
                        .padding(.bottom, 12)
                    }

                    quickActions
                    if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        favoritePlacesSection
                        recentPlacesSection
                    } else {
                        suggestionsSection
                    }

                    Color.clear.frame(height: 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DriveTimeTheme.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationBackground(DriveTimeTheme.canvas)
        .task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            searchFocused = true
        }
        .onDisappear {
            viewModel.cancel()
        }
        .sheet(isPresented: $showMapPicker) {
            MapPickerView(
                initialCoordinate: initialCoordinate ?? appModel.planner.origin?.coordinate,
                initialName: endpoint == .destination ? "目的地" : "起点"
            ) { location in
                select(location)
            }
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack {
            Button("取消") { dismiss() }
                .font(.body.weight(.medium))
                .foregroundStyle(DriveTimeTheme.secondaryInk)
                .buttonStyle(.plain)
            Spacer()
            Text(endpoint.title)
                .font(.headline)
                .foregroundStyle(DriveTimeTheme.ink)
            Spacer()
            Color.clear.frame(width: 34, height: 1)
        }
        .padding(.horizontal, DriveTimeTheme.contentPadding)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DriveTimeTheme.hairline.opacity(0.6))
                .frame(height: 0.5)
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DriveTimeTheme.tertiaryInk)
            TextField("搜索地点、街道或地标", text: Binding(
                get: { viewModel.query },
                set: { viewModel.updateQuery($0) }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .submitLabel(.search)
            .accessibilityIdentifier("placeSearchField")
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(DriveTimeTheme.secondaryInk)
            } else if !viewModel.query.isEmpty {
                Button {
                    viewModel.updateQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DriveTimeTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    searchFocused ? DriveTimeTheme.accent.opacity(0.65) : DriveTimeTheme.hairline.opacity(0.8),
                    lineWidth: searchFocused ? 1.4 : 0.5
                )
        )
    }

    private var quickActions: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "location.fill",
                title: viewModel.isLocating ? "正在获取当前位置…" : "使用当前位置",
                subtitle: viewModel.permissionExplanation,
                tint: DriveTimeTheme.origin,
                isEnabled: !viewModel.isLocating
            ) {
                Task {
                    if let location = await viewModel.useCurrentLocation() {
                        select(location)
                    }
                }
            }
            .accessibilityIdentifier("useCurrentLocation")

            Divider()
                .overlay(DriveTimeTheme.hairline.opacity(0.6))
                .padding(.leading, 58)

            actionRow(
                icon: "mappin.and.ellipse",
                title: "在地图上选点",
                subtitle: "拖动地图，把中心点放在准确的位置",
                tint: DriveTimeTheme.accent,
                isEnabled: true
            ) {
                searchFocused = false
                showMapPicker = true
            }
            .accessibilityIdentifier("mapPickerButton")
        }
        .background(DriveTimeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous)
                .strokeBorder(DriveTimeTheme.hairline.opacity(0.65), lineWidth: 0.5)
        )
        .padding(.horizontal, DriveTimeTheme.contentPadding)
        .padding(.bottom, 18)
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint.opacity(0.10)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DriveTimeTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private var favoritePlacesSection: some View {
        let favorites = appModel.history.favoritePlaces
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title: "收藏地点", detail: "\(favorites.count)")
                    .padding(.horizontal, DriveTimeTheme.contentPadding)
                    .padding(.bottom, 4)
                ForEach(favorites) { place in
                    locationRow(place.location, icon: "star.fill", tint: DriveTimeTheme.warning) {
                        select(place.location)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            appModel.history.delete(place: place)
                        } label: {
                            Label("删除收藏", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var recentPlacesSection: some View {
        let recent = recentPlaces
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title: "最近去过", detail: nil)
                    .padding(.horizontal, DriveTimeTheme.contentPadding)
                    .padding(.bottom, 4)
                ForEach(recent) { place in
                    locationRow(place, icon: "clock.arrow.circlepath", tint: DriveTimeTheme.secondaryInk) {
                        select(place)
                    }
                }
            }
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if !viewModel.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title: "搜索结果", detail: viewModel.providerLabel)
                    .padding(.horizontal, DriveTimeTheme.contentPadding)
                    .padding(.bottom, 4)
                ForEach(viewModel.suggestions) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        } else if !viewModel.isLoading && viewModel.errorMessage == nil {
            VStack(spacing: 8) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
                Text("没有找到匹配的地点")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DriveTimeTheme.secondaryInk)
                Text("试试更具体的城市、街道或地标名称。")
                    .font(.caption)
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        }
    }

    private func suggestionRow(_ suggestion: PlaceSuggestion) -> some View {
        HStack(spacing: 0) {
            Button {
                Task {
                    if let location = await viewModel.select(suggestion) {
                        select(location)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: suggestion.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(DriveTimeTheme.canvas))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DriveTimeTheme.ink)
                            .lineLimit(1)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(DriveTimeTheme.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if viewModel.isResolving {
                        ProgressView().controlSize(.small)
                    } else if suggestion.location == nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DriveTimeTheme.tertiaryInk)
                    }
                }
                .padding(.leading, DriveTimeTheme.contentPadding)
                .padding(.trailing, 8)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isResolving)

            if let location = suggestion.location {
                Button {
                    appModel.history.toggleFavoritePlace(location)
                } label: {
                    Image(systemName: appModel.history.isFavoritePlace(location) ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            appModel.history.isFavoritePlace(location)
                                ? DriveTimeTheme.warning
                                : DriveTimeTheme.tertiaryInk
                        )
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel(
                    appModel.history.isFavoritePlace(location) ? "取消收藏" : "收藏地点"
                )
            }
        }
    }

    private func locationRow(
        _ location: LocationResult,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint.opacity(0.09)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DriveTimeTheme.ink)
                        .lineLimit(1)
                    if !location.subtitle.isEmpty {
                        Text(location.subtitle)
                            .font(.caption)
                            .foregroundStyle(DriveTimeTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
            }
            .padding(.horizontal, DriveTimeTheme.contentPadding)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recentPlaces: [LocationResult] {
        var seen = Set<String>()
        var places: [LocationResult] = []
        for route in appModel.history.recentRoutes {
            for location in [route.originLocation, route.destinationLocation] {
                guard seen.insert(location.id).inserted else { continue }
                places.append(location)
                if places.count >= 6 { return places }
            }
        }
        return places
    }

    private func select(_ location: LocationResult) {
        onSelect(location)
        dismiss()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

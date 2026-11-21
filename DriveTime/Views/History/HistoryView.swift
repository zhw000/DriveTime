import SwiftUI

struct HistoryView: View {
    let appModel: AppModel
    let onSelect: (SavedRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false

    private var history: HistoryStore { appModel.history }
    private var formatter: DateDisplayFormatter { appModel.settings.displayFormatter }
    private var nonFavoriteRoutes: [SavedRoute] {
        history.recentRoutes.filter { !$0.isFavorite }
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.recentRoutes.isEmpty {
                    emptyState
                } else {
                    List {
                        if let error = history.lastError {
                            Section {
                                InlineErrorBanner(message: error)
                            }
                        }

                        if !history.favoriteRoutes.isEmpty {
                            Section {
                                ForEach(history.favoriteRoutes) { route in
                                    routeRow(route, isFavoriteSection: true)
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button {
                                                history.toggleFavorite(route: route)
                                            } label: {
                                                Label("取消收藏", systemImage: "star.slash")
                                            }
                                            .tint(DriveTimeTheme.warning)
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                history.delete(route: route)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                Text("收藏路线")
                            }
                        }

                        if !nonFavoriteRoutes.isEmpty {
                            Section {
                                ForEach(nonFavoriteRoutes) { route in
                                    routeRow(route, isFavoriteSection: false)
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button {
                                                history.toggleFavorite(route: route)
                                            } label: {
                                                Label("收藏", systemImage: "star")
                                            }
                                            .tint(DriveTimeTheme.warning)
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                history.delete(route: route)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                Text("最近查询")
                            } footer: {
                                Text("历史记录只保存摘要和上次的 ETA，不代表当前路况。轻点任意记录可重新获取实时路线。")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .accessibilityIdentifier("historyList")
                }
            }
            .background(DriveTimeTheme.canvas.ignoresSafeArea())
            .navigationTitle("行程记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(history.recentRoutes.isEmpty)
                    .accessibilityLabel("清空历史")
                }
            }
            .alert("清空查询历史？", isPresented: $showClearConfirmation) {
                Button("清空", role: .destructive) {
                    history.clearHistory(keepingFavorites: true)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除最近的查询记录；收藏路线会保留。")
            }
        }
    }

    private func routeRow(_ route: SavedRoute, isFavoriteSection: Bool) -> some View {
        Button {
            onSelect(route)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    endpointMinimalLabel(route.originLocation, isOrigin: true)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                    Text(route.destinationLocation.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DriveTimeTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isFavoriteSection {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DriveTimeTheme.warning)
                    }
                }

                HStack(spacing: 6) {
                    Text(TravelTimeFormatter.string(from: route.durationSeconds))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(DriveTimeTheme.ink)
                    Text("·")
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                    Text(DistanceFormatter.string(
                        fromMeters: route.distanceMeters,
                        unit: appModel.settings.distanceUnit
                    ))
                        .font(.footnote)
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                    Spacer(minLength: 0)
                    Text(route.provider.shortName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                }

                HStack(spacing: 7) {
                    Text("\(formatter.dateTimeString(for: route.queriedAt)) 查询")
                    Text("·")
                    Text("历史车程")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(DriveTimeTheme.accent)
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.caption2)
                .foregroundStyle(DriveTimeTheme.tertiaryInk)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(route.originLocation.name) 到 \(route.destinationLocation.name)，上次预计 \(TravelTimeFormatter.string(from: route.durationSeconds))，历史的 \(formatter.dateTimeString(for: route.queriedAt))。轻点重新查询。"
        )
        .contextMenu {
            Button {
                history.toggleFavorite(route: route)
            } label: {
                Label(route.isFavorite ? "取消收藏" : "收藏路线", systemImage: route.isFavorite ? "star.slash" : "star")
            }
            Button(role: .destructive) {
                history.delete(route: route)
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
    }

    private func endpointMinimalLabel(_ location: LocationResult, isOrigin: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOrigin ? DriveTimeTheme.origin : DriveTimeTheme.destination)
                .frame(width: 6, height: 6)
            Text(location.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DriveTimeTheme.secondaryInk)
                .lineLimit(1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DriveTimeTheme.tertiaryInk)
            Text("还没有行程记录")
                .font(.headline)
                .foregroundStyle(DriveTimeTheme.ink)
            Text("完成一次路线查询后，历史记录会出现在这里。")
                .font(.subheadline)
                .foregroundStyle(DriveTimeTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DriveTimeTheme.canvas)
    }
}

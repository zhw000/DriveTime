import SwiftUI

struct TripSearchCard: View {
    let origin: LocationResult?
    let destination: LocationResult?
    let isCalculating: Bool
    let availableStrategies: [RouteStrategy]
    let selectedStrategy: RouteStrategy
    let departureLabel: String
    let onOriginTap: () -> Void
    let onDestinationTap: () -> Void
    let onSwap: () -> Void
    let onCalculate: () -> Void
    let onDepartureTap: () -> Void
    let onStrategySelected: (RouteStrategy) -> Void

    @State private var swapAngle: Double = 0

    private var hasEndpoints: Bool { origin != nil && destination != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 0) {
                    endpointButton(
                        endpoint: .origin,
                        location: origin,
                        tint: DriveTimeTheme.origin,
                        action: onOriginTap
                    )
                    .accessibilityIdentifier("originField")

                    Rectangle()
                        .fill(DriveTimeTheme.hairline.opacity(0.7))
                        .frame(height: 0.5)
                        .padding(.leading, 27)

                    endpointButton(
                        endpoint: .destination,
                        location: destination,
                        tint: DriveTimeTheme.destination,
                        action: onDestinationTap
                    )
                    .accessibilityIdentifier("destinationField")
                }

                Button {
                    withAnimation(.snappy(duration: 0.32)) {
                        swapAngle += 180
                    }
                    onSwap()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DriveTimeTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(DriveTimeTheme.canvas))
                        .overlay(Circle().strokeBorder(DriveTimeTheme.hairline.opacity(0.8), lineWidth: 0.5))
                        .rotationEffect(.degrees(swapAngle))
                }
                .buttonStyle(.plain)
                .disabled(origin == nil && destination == nil)
                .opacity(origin == nil && destination == nil ? 0.45 : 1)
                .accessibilityLabel("交换起点和终点")
                .accessibilityIdentifier("swapEndpoints")
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(DriveTimeTheme.hairline.opacity(0.6))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button(action: onDepartureTap) {
                    Label(departureLabel, systemImage: "clock")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("出发时间，\(departureLabel)")
                .accessibilityIdentifier("departureButton")

                if availableStrategies.count > 1 {
                    Menu {
                        ForEach(availableStrategies) { strategy in
                            Button {
                                onStrategySelected(strategy)
                            } label: {
                                if strategy == selectedStrategy {
                                    Label(strategy.displayName, systemImage: "checkmark")
                                } else {
                                    Text(strategy.displayName)
                                }
                            }
                        }
                    } label: {
                        Label(selectedStrategy.displayName, systemImage: selectedStrategy.iconName)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DriveTimeTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("strategyMenu")
                } else {
                    Label(
                        availableStrategies.first?.displayName ?? "智能推荐",
                        systemImage: "sparkles"
                    )
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17)
            .frame(height: 40)

            if hasEndpoints {
                Rectangle()
                    .fill(DriveTimeTheme.hairline.opacity(0.6))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                PrimaryButton(
                    title: isCalculating ? "正在计算车程…" : "计算车程",
                    systemImage: isCalculating ? nil : "arrow.triangle.turn.up.right.diamond.fill",
                    isLoading: isCalculating,
                    isEnabled: !isCalculating,
                    action: onCalculate
                )
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .accessibilityIdentifier("calculateRoute")
            }
        }
        .background(DriveTimeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous)
                .strokeBorder(DriveTimeTheme.hairline.opacity(0.8), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 8)
    }

    private func endpointButton(
        endpoint: TripEndpoint,
        location: LocationResult?,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                endpointDot(location == nil, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(endpoint.shortTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    Text(location?.name ?? (endpoint == .origin ? "选择起点" : "搜索目的地"))
                        .font(.system(size: 16.5, weight: location == nil ? .regular : .medium))
                        .foregroundStyle(location == nil ? DriveTimeTheme.tertiaryInk : DriveTimeTheme.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DriveTimeTheme.tertiaryInk.opacity(0.7))
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(endpoint.shortTitle)，\(location?.name ?? "未选择")")
        .accessibilityHint("轻点搜索\(endpoint.shortTitle)")
    }

    private func endpointDot(_ hollow: Bool, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(hollow ? Color.clear : tint)
                .frame(width: 10, height: 10)
            if hollow {
                Circle()
                    .strokeBorder(tint, lineWidth: 1.8)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(width: 16, height: 16)
    }
}

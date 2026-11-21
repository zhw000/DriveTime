import SwiftUI

struct CircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var role: ButtonRole?
    var action: () -> Void

    init(
        systemName: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DriveTimeTheme.ink)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(DriveTimeTheme.hairline.opacity(0.6), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct EndpointRail: View {
    var lineColor: Color = DriveTimeTheme.hairline
    var originColor: Color = DriveTimeTheme.origin
    var destinationColor: Color = DriveTimeTheme.destination

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .strokeBorder(originColor, lineWidth: 2)
                .background(Circle().fill(originColor.opacity(0.12)))
                .frame(width: 12, height: 12)
            Rectangle()
                .fill(lineColor)
                .frame(width: 1.5, height: 18)
            Circle()
                .fill(destinationColor)
                .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}

struct EndpointRowContent: View {
    let label: String
    let location: LocationResult?
    let placeholder: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DriveTimeTheme.tertiaryInk)
                .textCase(.uppercase)
                .tracking(0.6)
            if let location {
                Text(location.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DriveTimeTheme.ink)
                    .lineLimit(1)
                if !location.subtitle.isEmpty {
                    Text(location.subtitle)
                        .font(.caption)
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                        .lineLimit(1)
                }
            } else {
                Text(placeholder)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(location?.name ?? placeholder)")
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isEnabled ? DriveTimeTheme.accent : DriveTimeTheme.tertiaryInk.opacity(0.45))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityHint(isLoading ? "正在查询" : "")
    }
}

struct InlineErrorBanner: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DriveTimeTheme.warning)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DriveTimeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DriveTimeTheme.accent)
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DriveTimeTheme.controlRadius, style: .continuous)
                .fill(DriveTimeTheme.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DriveTimeTheme.controlRadius, style: .continuous)
                .strokeBorder(DriveTimeTheme.warning.opacity(0.18), lineWidth: 0.5)
        )
    }
}

struct LabelChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = DriveTimeTheme.secondaryInk

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.09)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.10), lineWidth: 0.5))
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DriveTimeTheme.ink)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
            }
        }
    }
}

struct TrafficLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach([TrafficInformation.Level.smooth, .slow, .congested, .severelyCongested], id: \.rawValue) { level in
                HStack(spacing: 4) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 6, height: 6)
                    Text(level.displayName)
                        .font(.caption2)
                        .foregroundStyle(DriveTimeTheme.tertiaryInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("路况图例：畅通、缓行、拥堵、严重拥堵")
    }
}

struct StatItem: View {
    let value: String
    let label: String
    var tint: Color = DriveTimeTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(DriveTimeTheme.tertiaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)：\(value)")
    }
}

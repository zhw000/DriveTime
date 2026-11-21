import SwiftUI

struct DeparturePickerView: View {
    let currentChoice: DepartureChoice
    let formatter: DateDisplayFormatter
    let onApply: (DepartureChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Selection
    @State private var customDate: Date
    @State private var now: Date

    private enum Selection: Hashable {
        case now
        case nextHour(Date)
        case tomorrowMorning(Date)
        case custom
    }

    init(
        currentChoice: DepartureChoice,
        now: Date,
        formatter: DateDisplayFormatter = DateDisplayFormatter(),
        onApply: @escaping (DepartureChoice) -> Void
    ) {
        self.currentChoice = currentChoice
        self.formatter = formatter
        self.onApply = onApply
        self._now = State(initialValue: now)
        let calendar = formatter.calendar
        let suggestedNextHour = calendar.date(
            bySettingHour: calendar.component(.hour, from: now) + 1,
            minute: 0,
            second: 0,
            of: now
        ) ?? now.addingTimeInterval(3_600)
        let tomorrowMorning = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        ) ?? now.addingTimeInterval(86_400)

        let initialDate: Date
        let initialSelection: Selection
        switch currentChoice {
        case .now:
            initialDate = suggestedNextHour
            initialSelection = .now
        case .scheduled(let date):
            initialDate = date
            initialSelection = .custom
        }
        self._customDate = State(initialValue: initialDate)
        self._selection = State(initialValue: initialSelection)
        self._nextHour = State(initialValue: suggestedNextHour)
        self._tomorrowMorning = State(initialValue: tomorrowMorning)
    }

    @State private var nextHour: Date
    @State private var tomorrowMorning: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("计划出发时间")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DriveTimeTheme.ink)
                        Text("选择现在出发，或为稍后的行程设定时间。")
                            .font(.subheadline)
                            .foregroundStyle(DriveTimeTheme.secondaryInk)
                    }

                    VStack(spacing: 0) {
                        optionRow(
                            title: "现在出发",
                            subtitle: formatter.timeString(for: now) + " 查询当前路况",
                            icon: "bolt.fill",
                            isSelected: selection == .now
                        ) {
                            selection = .now
                        }
                        rowDivider
                        optionRow(
                            title: "稍后 · \(formatter.timeString(for: nextHour))",
                            subtitle: formatter.relativeDayString(for: nextHour, relativeTo: now),
                            icon: "clock",
                            isSelected: selection == .nextHour(nextHour)
                        ) {
                            selection = .nextHour(nextHour)
                        }
                        rowDivider
                        optionRow(
                            title: "明天 \(formatter.timeString(for: tomorrowMorning))",
                            subtitle: "提前查看计划行程",
                            icon: "sunrise.fill",
                            isSelected: selection == .tomorrowMorning(tomorrowMorning)
                        ) {
                            selection = .tomorrowMorning(tomorrowMorning)
                        }
                        rowDivider
                        optionRow(
                            title: "自定义日期和时间",
                            subtitle: selection == .custom
                                ? "\(formatter.relativeDayString(for: customDate, relativeTo: now)) \(formatter.timeString(for: customDate))"
                                : "选择具体日期",
                            icon: "calendar",
                            isSelected: selection == .custom
                        ) {
                            selection = .custom
                        }
                    }
                    .background(DriveTimeTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous)
                            .strokeBorder(DriveTimeTheme.hairline.opacity(0.7), lineWidth: 0.5)
                    )

                    if selection == .custom {
                        DatePicker(
                            "出发时间",
                            selection: $customDate,
                            in: now...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .padding(16)
                        .background(DriveTimeTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(DriveTimeTheme.hairline.opacity(0.7), lineWidth: 0.5)
                        )
                    }

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DriveTimeTheme.warning)
                        Text("Apple 地图与高德 Web 路线当前不提供该未来时刻的交通预测。未来出发的车程按当前路况估算，抵达时间仅供参考。")
                            .font(.caption)
                            .foregroundStyle(DriveTimeTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DriveTimeTheme.warning.opacity(0.08))
                    )

                    PrimaryButton(title: "应用出发时间", systemImage: "checkmark") {
                        onApply(resolvedChoice)
                        dismiss()
                    }
                    .accessibilityIdentifier("applyDeparture")

                    Spacer(minLength: 8)
                }
                .padding(DriveTimeTheme.contentPadding)
            }
            .background(DriveTimeTheme.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(DriveTimeTheme.canvas)
    }

    private var resolvedChoice: DepartureChoice {
        switch selection {
        case .now:
            return .now
        case .nextHour(let date):
            return .scheduled(date)
        case .tomorrowMorning(let date):
            return .scheduled(date)
        case .custom:
            return .scheduled(max(customDate, now))
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DriveTimeTheme.hairline.opacity(0.6))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }

    private func optionRow(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? DriveTimeTheme.accent : DriveTimeTheme.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(
                            isSelected
                                ? DriveTimeTheme.accent.opacity(0.12)
                                : DriveTimeTheme.canvas
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DriveTimeTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DriveTimeTheme.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? DriveTimeTheme.accent : DriveTimeTheme.hairline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import Foundation

enum TravelTimeFormatter {
    /// Human-readable driving duration. Input is always seconds from a routing
    /// provider; no synthetic speed/ETC adjustments are introduced.
    static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 分钟" }
        if seconds < 60 {
            return "不到 1 分钟"
        }
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes) 分钟"
        }
        if minutes == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    static func clockString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    static func compactString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 分" }
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) 分" }
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分"
    }

    /// A truthful difference label used between routes. The caller supplies
    /// the actual service values.
    static func differenceString(from seconds: TimeInterval) -> String {
        let magnitude = abs(seconds)
        let text = string(from: magnitude)
        if magnitude < 30 {
            return "与推荐路线用时接近"
        }
        return seconds > 0 ? "比推荐路线慢 \(text)" : "比推荐路线快 \(text)"
    }

    static func differenceShortString(from seconds: TimeInterval) -> String {
        let magnitude = abs(seconds)
        if magnitude < 30 { return "时间接近" }
        let prefix = seconds > 0 ? "+" : "−"
        return "\(prefix)\(compactString(from: magnitude))"
    }
}

enum DistanceFormatter {
    static func string(fromMeters meters: Double, unit: DistanceUnit) -> String {
        guard meters.isFinite, meters > 0 else { return "0 米" }
        switch unit {
        case .metric:
            if meters < 1_000 {
                return "\(Int(meters.rounded())) 米"
            }
            return "\(decimal(meters / 1_000, digits: 1)) 公里"
        case .imperial:
            let miles = meters / 1_609.344
            if miles < 0.1 {
                let feet = meters / 0.3048
                return "\(Int(feet.rounded())) 英尺"
            }
            return "\(decimal(miles, digits: 1)) 英里"
        }
    }

    static func compactString(fromMeters meters: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .metric:
            if meters < 1_000 { return "\(Int(meters.rounded())) m" }
            return "\(decimal(meters / 1_000, digits: 1)) km"
        case .imperial:
            let miles = meters / 1_609.344
            if miles < 0.1 { return "\(Int((meters / 0.3048).rounded())) ft" }
            return "\(decimal(miles, digits: 1)) mi"
        }
    }

    static func differenceString(fromMeters meters: Double, unit: DistanceUnit) -> String {
        let magnitude = abs(meters)
        if magnitude < 50 { return "距离接近" }
        let prefix = meters > 0 ? "多" : "少"
        return "\(prefix) \(string(fromMeters: magnitude, unit: unit))"
    }

    private static func decimal(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }
}

enum CurrencyFormatter {
    static func yuan(_ amount: Double) -> String {
        guard amount.isFinite, amount >= 0 else { return "暂无数据" }
        let rounded = amount.rounded()
        if abs(amount - rounded) < 0.01 {
            return "¥\(Int(rounded))"
        }
        return String(format: "¥%.2f", amount)
    }
}

enum ETAComputation {
    static func arrivalDate(departure: Date, expectedTravelTime: TimeInterval) -> Date {
        departure.addingTimeInterval(max(0, expectedTravelTime))
    }

    static func elapsedTime(from departure: Date, to arrival: Date) -> TimeInterval {
        max(0, arrival.timeIntervalSince(departure))
    }
}

struct DateDisplayFormatter: Sendable {
    var timeFormat: TimeFormatPreference
    var locale: Locale
    var timeZone: TimeZone
    var calendar: Calendar

    init(
        timeFormat: TimeFormatPreference = .system,
        locale: Locale = .current,
        timeZone: TimeZone = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.timeFormat = timeFormat
        self.locale = locale
        self.timeZone = timeZone
        var calendar = calendar
        calendar.timeZone = timeZone
        calendar.locale = locale
        self.calendar = calendar
    }

    func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        switch timeFormat {
        case .system:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .twentyFourHour:
            formatter.dateFormat = "HH:mm"
        case .twelveHour:
            formatter.dateFormat = "h:mm a"
        }
        return formatter.string(from: date)
    }

    func dateTimeString(for date: Date, includeYear: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.dateFormat = includeYear ? "yyyy年M月d日 HH:mm" : "M月d日 HH:mm"
        if timeFormat == .twelveHour {
            formatter.dateFormat = includeYear ? "yyyy年M月d日 h:mm a" : "M月d日 h:mm a"
        }
        return formatter.string(from: date)
    }

    /// "今天 16:45", "明天 08:10", "11月23日 14:00" based on calendar days in
    /// the configured time zone.
    func relativeArrivalString(arrival: Date, relativeTo departure: Date) -> String {
        let dayLabel = dayRelationshipString(arrival: arrival, relativeTo: departure)
        return "\(dayLabel) \(timeString(for: arrival))"
    }

    func dayRelationshipString(arrival: Date, relativeTo departure: Date) -> String {
        let departureDay = calendar.startOfDay(for: departure)
        let arrivalDay = calendar.startOfDay(for: arrival)
        let days = calendar.dateComponents([.day], from: departureDay, to: arrivalDay).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        default:
            if days < 0 {
                return dateTimeString(for: arrival)
            }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.calendar = calendar
            formatter.dateFormat = "M月d日"
            return formatter.string(from: arrival)
        }
    }

    func freshnessString(for queriedAt: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(queriedAt))
        if seconds < 45 { return "刚刚更新" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前更新" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) 小时前更新" }
        return dateTimeString(for: queriedAt)
    }

    func relativeDayString(for date: Date, relativeTo reference: Date = Date()) -> String {
        let day = calendar.startOfDay(for: date)
        let referenceDay = calendar.startOfDay(for: reference)
        let days = calendar.dateComponents([.day], from: referenceDay, to: day).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case -1: return "昨天"
        default: return dateTimeString(for: date)
        }
    }
}

enum TrafficSummaryText {
    static func summary(for traffic: TrafficInformation) -> String {
        guard traffic.hasUsableData else { return "暂无路况数据" }
        let congestedMeters = traffic.totalMeters(for: .congested)
            + traffic.totalMeters(for: .severelyCongested)
        let slowMeters = traffic.totalMeters(for: .slow)
        if congestedMeters > 0 {
            return "部分路段拥堵"
        }
        if slowMeters > 0 {
            return "部分路段缓行"
        }
        return "当前路线整体畅通"
    }
}

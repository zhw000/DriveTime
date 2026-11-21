import Foundation
import XCTest
@testable import DriveTime

final class FormattingTests: XCTestCase {
    func testTripDurationFormatting() {
        XCTAssertEqual(TravelTimeFormatter.string(from: 0), "0 分钟")
        XCTAssertEqual(TravelTimeFormatter.string(from: 30), "不到 1 分钟")
        XCTAssertEqual(TravelTimeFormatter.string(from: 60), "1 分钟")
        XCTAssertEqual(TravelTimeFormatter.string(from: 3_599), "1 小时")
        XCTAssertEqual(TravelTimeFormatter.string(from: 3_600), "1 小时")
        XCTAssertEqual(TravelTimeFormatter.string(from: 9_360), "2 小时 36 分钟")
        XCTAssertEqual(TravelTimeFormatter.string(from: 5_459), "1 小时 31 分钟")
        XCTAssertEqual(TravelTimeFormatter.compactString(from: 9_360), "2 小时 36 分")
        XCTAssertEqual(TravelTimeFormatter.clockString(from: 9_360), "2:36")
    }

    func testDistanceFormattingMetricAndImperial() {
        XCTAssertEqual(DistanceFormatter.string(fromMeters: 0, unit: .metric), "0 米")
        XCTAssertEqual(DistanceFormatter.string(fromMeters: 950, unit: .metric), "950 米")
        XCTAssertEqual(DistanceFormatter.string(fromMeters: 1_000, unit: .metric), "1 公里")
        XCTAssertTrue(
            DistanceFormatter.string(fromMeters: 12_400, unit: .metric).contains("公里")
        )
        XCTAssertTrue(
            DistanceFormatter.string(fromMeters: 1_609.344, unit: .imperial).contains("英里")
        )
        XCTAssertTrue(
            DistanceFormatter.string(fromMeters: 30, unit: .imperial).contains("英尺")
        )
    }

    func testTravelTimeDifferenceUsesServiceValues() {
        XCTAssertEqual(
            TravelTimeFormatter.differenceString(from: 720),
            "比推荐路线慢 12 分钟"
        )
        XCTAssertEqual(
            TravelTimeFormatter.differenceString(from: -660),
            "比推荐路线快 11 分钟"
        )
        XCTAssertEqual(
            TravelTimeFormatter.differenceString(from: 10),
            "与推荐路线用时接近"
        )
    }

    func testETAAddition() {
        let departure = Date(timeIntervalSince1970: 1_700_000_000)
        let arrival = ETAComputation.arrivalDate(departure: departure, expectedTravelTime: 8_100)
        XCTAssertEqual(arrival.timeIntervalSince(departure), 8_100, accuracy: 0.001)
        XCTAssertEqual(ETAComputation.elapsedTime(from: departure, to: arrival), 8_100, accuracy: 0.001)
    }

    func testCrossDayArrivalInShanghai() {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateDisplayFormatter(
            timeFormat: .twentyFourHour,
            locale: Locale(identifier: "zh_CN"),
            timeZone: timeZone,
            calendar: calendar
        )
        let departure = TestSupport.makeDate(
            DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 30),
            timeZone: timeZone
        )
        let arrival = ETAComputation.arrivalDate(departure: departure, expectedTravelTime: 2 * 3_600)
        XCTAssertEqual(formatter.timeString(for: arrival), "01:30")
        XCTAssertEqual(formatter.dayRelationshipString(arrival: arrival, relativeTo: departure), "明天")
        XCTAssertEqual(formatter.relativeArrivalString(arrival: arrival, relativeTo: departure), "明天 01:30")
    }

    func testDaylightSavingTransitionUsesElapsedDuration() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateDisplayFormatter(
            timeFormat: .twentyFourHour,
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone,
            calendar: calendar
        )
        // 2026-03-08 02:00 local does not exist in Los Angeles. Adding two
        // real hours to 01:30 correctly arrives at 04:30 PDT.
        let departure = TestSupport.makeDate(
            DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30),
            timeZone: timeZone
        )
        let arrival = ETAComputation.arrivalDate(departure: departure, expectedTravelTime: 2 * 3_600)
        XCTAssertEqual(formatter.timeString(for: arrival), "04:30")
        XCTAssertEqual(
            formatter.dayRelationshipString(arrival: arrival, relativeTo: departure),
            "今天"
        )
    }

    func testTimeFormatPreferences() {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = TestSupport.makeDate(
            DateComponents(year: 2026, month: 5, day: 20, hour: 16, minute: 45),
            timeZone: timeZone
        )

        let twentyFour = DateDisplayFormatter(
            timeFormat: .twentyFourHour,
            locale: Locale(identifier: "zh_CN"),
            timeZone: timeZone,
            calendar: calendar
        )
        XCTAssertEqual(twentyFour.timeString(for: date), "16:45")

        let twelve = DateDisplayFormatter(
            timeFormat: .twelveHour,
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone,
            calendar: calendar
        )
        XCTAssertTrue(twelve.timeString(for: date).contains("4:45"))
        XCTAssertTrue(twelve.timeString(for: date).uppercased().contains("PM"))
    }

    func testCurrencyFormatting() {
        XCTAssertEqual(CurrencyFormatter.yuan(0), "¥0")
        XCTAssertEqual(CurrencyFormatter.yuan(32), "¥32")
        XCTAssertEqual(CurrencyFormatter.yuan(12.5), "¥12.50")
    }
}

import XCTest
@testable import Cache_Out

// MARK: - Formatters
// Pure-logic tests — verify the helpers that determine what sizes are shown to
// users before they click "Clean". A wrong formatter = "2 KB" displayed when
// the real value is "2 MB". Highest-leverage tests in a disk-cleaning app.

final class FormattersTests: XCTestCase {

    func testFormatBytes_zero() {
        XCTAssertEqual(formatBytes(0), "Zero KB")
    }

    func testFormatBytes_kilobytes() {
        let result = formatBytes(512 * 1024)
        XCTAssertTrue(result.contains("512") || result.contains("KB"),
                      "Expected KB range, got: \(result)")
    }

    func testFormatBytes_megabytes() {
        let result = formatBytes(50 * 1024 * 1024)
        XCTAssertTrue(result.contains("50") && result.contains("MB"),
                      "Expected 50 MB, got: \(result)")
    }

    func testFormatBytes_gigabytes() {
        let result = formatBytes(6 * 1024 * 1024 * 1024)
        XCTAssertTrue(result.contains("6") && result.contains("GB"),
                      "Expected 6 GB, got: \(result)")
    }

    func testFormatBytes_negative_doesNotCrash() {
        // Negative byte counts must never crash; ByteCountFormatter clamps gracefully.
        XCTAssertFalse(formatBytes(-1024).isEmpty)
    }
}

// MARK: - relativeDaysAgo
final class RelativeDaysAgoTests: XCTestCase {
    func testToday()         { XCTAssertEqual(relativeDaysAgo(0),   "Today") }
    func testYesterday()     { XCTAssertEqual(relativeDaysAgo(1),   "Yesterday") }
    func testDaysRange()     { XCTAssertEqual(relativeDaysAgo(5),   "5 days ago") }
    func testWeekSingular()  { XCTAssertEqual(relativeDaysAgo(7),   "1 week ago") }
    func testWeeksPlural()   { XCTAssertEqual(relativeDaysAgo(14),  "2 weeks ago") }
    func testMonthSingular() { XCTAssertEqual(relativeDaysAgo(31),  "1 month ago") }
    func testMonthsPlural()  { XCTAssertEqual(relativeDaysAgo(60),  "2 months ago") }
    func testYearSingular()  { XCTAssertEqual(relativeDaysAgo(365), "1 year ago") }
    func testYearsPlural()   { XCTAssertEqual(relativeDaysAgo(730), "2 years ago") }
}

// MARK: - Int.nonZero
final class IntNonZeroTests: XCTestCase {
    func testZeroReturnsNil()    { XCTAssertNil(0.nonZero) }
    func testPositiveReturnsSelf() { XCTAssertEqual(7.nonZero, 7) }
    func testNegativeReturnsSelf() { XCTAssertEqual((-3).nonZero, -3) }
}

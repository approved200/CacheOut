import XCTest
@testable import Cache_Out

// MARK: - BackgroundCleanScheduler tests
// The actual NSBackgroundActivityScheduler callback can't fire in unit tests,
// but the routing logic (schedule vs no-op based on UserDefaults) and the
// invalidate/teardown behaviour are fully testable.

@MainActor
final class BackgroundCleanSchedulerTests: XCTestCase {

    override func tearDown() async throws {
        // Always reset UserDefaults keys touched by these tests
        UserDefaults.standard.removeObject(forKey: "autoCleanSchedule")
        UserDefaults.standard.removeObject(forKey: "scanOnLaunch")
        // Invalidate the shared scheduler so state doesn't leak between tests
        BackgroundCleanScheduler.shared.invalidate()
    }

    // scheduleIfNeeded with schedule=0 ("Never") must not crash.
    func testScheduleIfNeeded_never_isNoop() {
        UserDefaults.standard.set(0, forKey: "autoCleanSchedule")
        BackgroundCleanScheduler.shared.scheduleIfNeeded()
        // No assertion needed — the test passes if no crash occurs
        XCTAssertTrue(true)
    }

    // scheduleIfNeeded with schedule=1 ("Daily") must not crash.
    func testScheduleIfNeeded_daily_doesNotCrash() {
        UserDefaults.standard.set(1, forKey: "autoCleanSchedule")
        BackgroundCleanScheduler.shared.scheduleIfNeeded()
        XCTAssertTrue(true)
    }

    // scheduleIfNeeded called twice must not crash (cancel + recreate).
    func testScheduleIfNeeded_calledTwice_doesNotCrash() {
        UserDefaults.standard.set(2, forKey: "autoCleanSchedule")
        BackgroundCleanScheduler.shared.scheduleIfNeeded()
        BackgroundCleanScheduler.shared.scheduleIfNeeded()
        XCTAssertTrue(true)
    }

    // invalidate() called twice must not crash (idempotent).
    func testInvalidate_isIdempotent() {
        UserDefaults.standard.set(1, forKey: "autoCleanSchedule")
        BackgroundCleanScheduler.shared.scheduleIfNeeded()
        BackgroundCleanScheduler.shared.invalidate()
        BackgroundCleanScheduler.shared.invalidate()  // second call — must not crash
        XCTAssertTrue(true)
    }

    // scanVM injection: setting scanVM to nil must not crash scheduleIfNeeded.
    func testScheduleIfNeeded_nilScanVM_doesNotCrash() {
        BackgroundCleanScheduler.shared.scanVM = nil
        UserDefaults.standard.set(1, forKey: "autoCleanSchedule")
        BackgroundCleanScheduler.shared.scheduleIfNeeded()
        XCTAssertTrue(true)
    }

    // scanVM can be assigned and replaced without crashing.
    func testScanVMAssignment_doesNotCrash() {
        let vm = CleanViewModel()
        BackgroundCleanScheduler.shared.scanVM = vm
        BackgroundCleanScheduler.shared.scanVM = nil
        XCTAssertTrue(true)
    }
}

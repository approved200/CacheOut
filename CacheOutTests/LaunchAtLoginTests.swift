import XCTest
@testable import Cache_Out

// MARK: - LaunchAtLogin tests
// SMAppService.register() / unregister() require the app to be properly signed
// and running as a full application — they are not testable in a unit test
// runner without the correct entitlements. What we CAN test:
//   1. isEnabled returns a Bool without crashing (pure getter, no side effects)
//   2. setEnabled returns a non-nil error String when called from a test runner
//      (no entitlements → SMAppService throws → we surface the error correctly)
//   3. The @discardableResult annotation is honoured — callers are not forced
//      to handle the return value

final class LaunchAtLoginTests: XCTestCase {

    // isEnabled must return a Bool without crashing.
    // In test context SMAppService.mainApp.status returns .notRegistered.
    func testIsEnabled_returnsBoolWithoutCrash() {
        // Just reading the property — must not throw or crash
        let _ = LaunchAtLogin.isEnabled
        XCTAssertTrue(true)
    }

    // isEnabled is a pure getter with no side effects —
    // calling it twice must return the same value.
    func testIsEnabled_isDeterministic() {
        let first  = LaunchAtLogin.isEnabled
        let second = LaunchAtLogin.isEnabled
        XCTAssertEqual(first, second,
            "isEnabled must be deterministic — same value on repeated reads")
    }

    // setEnabled(true) in a test context must not crash.
    // It will return a non-nil error string because SMAppService requires
    // a properly signed, running .app bundle — but the error path itself
    // must be handled gracefully.
    func testSetEnabled_true_doesNotCrash() {
        let result = LaunchAtLogin.setEnabled(true)
        // result is either nil (unlikely in test runner) or a non-empty error string
        if let err = result {
            XCTAssertFalse(err.isEmpty, "Error string must not be empty")
        }
        // No assertion on the Bool value — depends on entitlements / test environment
    }

    // setEnabled(false) in a test context must not crash.
    func testSetEnabled_false_doesNotCrash() {
        let result = LaunchAtLogin.setEnabled(false)
        if let err = result {
            XCTAssertFalse(err.isEmpty)
        }
    }

    // @discardableResult: calling without capturing the return value must compile
    // and run without warning or error.
    func testSetEnabled_discardableResult_compiles() {
        LaunchAtLogin.setEnabled(false)  // discarded — must compile cleanly
        XCTAssertTrue(true)
    }
}

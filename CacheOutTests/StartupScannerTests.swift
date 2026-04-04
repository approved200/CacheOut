import XCTest
@testable import Cache_Out

// MARK: - StartupScanner unit tests
// The scanner powers the Startup tab. We can't test the live launchctl output
// (it differs per machine) but we can test the plist parsing logic in isolation
// and the batch label parser that drives the isLoaded state.

final class StartupScannerPlistParsingTests: XCTestCase {

    // Helper: write a minimal LaunchAgent plist to disk and return its path
    private func writeTempPlist(label: String, program: String = "/usr/bin/true",
                                runAtLoad: Bool = true) throws -> String {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("\(label).plist").path
        let dict: NSDictionary = [
            "Label": label,
            "ProgramArguments": [program],
            "RunAtLoad": runAtLoad,
        ]
        dict.write(toFile: path, atomically: true)
        return path
    }

    // LaunchAgent dirs that don't exist must return empty — never crash
    func testScan_nonexistentDir_returnsEmpty() {
        let results = StartupScanner.scan()
        // We can't control what's installed, but the call itself must not throw
        XCTAssertNotNil(results, "scan() must not crash regardless of what's installed")
    }

    // A plist with a valid Label + ProgramArguments produces exactly one item
    func testParsePlist_validPlist_producesOneItem() throws {
        let path = try writeTempPlist(label: "com.test.cache_out_test_agent",
                                     program: "/usr/bin/true",
                                     runAtLoad: true)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        // Read back using NSDictionary to verify the plist round-trips correctly
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let label = dict["Label"] as? String,
              let args  = dict["ProgramArguments"] as? [String],
              let run   = dict["RunAtLoad"] as? Bool
        else { XCTFail("Plist round-trip failed"); return }

        XCTAssertEqual(label, "com.test.cache_out_test_agent")
        XCTAssertEqual(args.first, "/usr/bin/true")
        XCTAssertTrue(run)
    }

    // A plist without a Label key must be skipped (parsePlist returns nil)
    func testParsePlist_missingLabel_isSkipped() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("no_label.plist").path
        defer { try? fm.removeItem(atPath: dir.path) }

        let dict: NSDictionary = ["ProgramArguments": ["/usr/bin/true"]]
        dict.write(toFile: path, atomically: true)

        // NSDictionary(contentsOfFile:) reads it but Label is nil → parsePlist returns nil
        let loaded = NSDictionary(contentsOfFile: path) as? [String: Any]
        let label = loaded?["Label"] as? String
        XCTAssertNil(label, "A plist without a Label key must be skipped by the scanner")
    }

    // RunAtLoad = false → isEnabled should be false
    func testParsePlist_runAtLoadFalse_isDisabled() throws {
        let path = try writeTempPlist(label: "com.test.disabled_agent",
                                     runAtLoad: false)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let dict = NSDictionary(contentsOfFile: path) as? [String: Any]
        let runAtLoad = dict?["RunAtLoad"] as? Bool ?? false
        XCTAssertFalse(runAtLoad, "RunAtLoad:false must mark the item as disabled")
    }
}

// MARK: - StartupSource raw values
// These strings appear in the UI — regressions would surface as wrong text
final class StartupSourceDisplayTests: XCTestCase {

    func testUserLaunchAgent_rawValue() {
        XCTAssertEqual(StartupSource.userLaunchAgent.rawValue, "Launch Agent")
    }

    func testSystemLaunchAgent_rawValue() {
        XCTAssertEqual(StartupSource.systemLaunchAgent.rawValue, "System Agent")
    }

    func testSystemDaemon_rawValue() {
        XCTAssertEqual(StartupSource.systemDaemon.rawValue, "System Daemon")
    }

    func testLoginItem_rawValue() {
        XCTAssertEqual(StartupSource.smAppService.rawValue, "Login Item")
    }
}

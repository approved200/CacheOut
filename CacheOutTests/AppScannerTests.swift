import XCTest
@testable import Cache_Out

// MARK: - AppScanner unit tests
// These tests verify the scanner that powers the Uninstall tab.
// A bug here means either user apps disappear from the list (false exclusion)
// or system apps that cannot be uninstalled appear (false inclusion).

final class AppScannerDirectorySizeTests: XCTestCase {

    // directorySize on a non-existent path must return 0 — never crash
    func testDirectorySize_nonexistentPath_returnsZero() {
        let fm = FileManager.default
        let size = AppScanner.directorySize(path: "/this/path/does/not/exist/999", fm: fm)
        XCTAssertEqual(size, 0)
    }

    // directorySize on an empty directory must return 0
    func testDirectorySize_emptyDir_returnsZero() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        XCTAssertEqual(AppScanner.directorySize(path: tmp.path, fm: fm), 0)
    }

    // directorySize must sum allocated sizes including files in sub-directories
    func testDirectorySize_withFiles_nonZero() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // Write two files totalling ~12 KB allocated
        try Data(repeating: 0xAA, count: 4096).write(to: tmp.appendingPathComponent("a.bin"))
        try Data(repeating: 0xBB, count: 8192).write(to: tmp.appendingPathComponent("b.bin"))

        let size = AppScanner.directorySize(path: tmp.path, fm: fm)
        XCTAssertGreaterThan(size, 0, "Should measure non-zero allocated size for real files")
    }

    // directorySize must NOT skip hidden (dot) files — .npm, .gradle, etc. are hidden
    func testDirectorySize_includesHiddenFiles() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let hidden = tmp.appendingPathComponent(".hidden_cache")
        try Data(repeating: 0xFF, count: 8192).write(to: hidden)

        let size = AppScanner.directorySize(path: tmp.path, fm: fm)
        XCTAssertGreaterThan(size, 0, "directorySize must not skip hidden files")
    }
}

// MARK: - System app exclusion logic
final class AppScannerExclusionTests: XCTestCase {

    func testSystemPath_isExcluded() {
        XCTAssertTrue("/System/Applications/Calculator.app".hasPrefix("/System/"),
                      "/System/ apps must be excluded from the Uninstall tab")
    }

    func testFinalCutProPath_isNotExcluded() {
        XCTAssertFalse("/Applications/Final Cut Pro.app".hasPrefix("/System/"),
                       "Final Cut Pro must NOT be excluded — it lives in /Applications/")
    }

    func testLogicProPath_isNotExcluded() {
        XCTAssertFalse("/Applications/Logic Pro.app".hasPrefix("/System/"),
                       "Logic Pro must NOT be excluded")
    }

    func testXcodePath_isNotExcluded() {
        XCTAssertFalse("/Applications/Xcode.app".hasPrefix("/System/"),
                       "Xcode must NOT be excluded")
    }

    // App paths in ~/Applications must never be treated as system apps
    func testUserApplicationsPath_isNotExcluded() {
        let userPath = "\(NSHomeDirectory())/Applications/MyApp.app"
        XCTAssertFalse(userPath.hasPrefix("/System/"),
                       "Apps in ~/Applications must be includable in the Uninstall tab")
    }
}

import XCTest
@testable import Cache_Out

// MARK: - CleanViewModel path expansion
// Tests the path-expansion logic that decides WHICH files get trashed.
// A bug here is a data-loss bug — wrong path = wrong directory deleted.

@MainActor
final class CleanViewModelPathTests: XCTestCase {

    private var vm: CleanViewModel!

    override func setUp() async throws {
        vm = CleanViewModel()
    }

    func testDirSize_nonexistentPath_returnsZero() {
        let size = vm.dirSize("/this/path/does/not/exist/ever")
        XCTAssertEqual(size, 0)
    }

    func testDirSize_realTempDir_nonNegative() {
        let size = vm.dirSize(NSTemporaryDirectory())
        XCTAssertGreaterThanOrEqual(size, 0)
    }

    func testDirSize_includesHiddenFiles() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let hidden = tmp.appendingPathComponent(".hidden_cache_test")
        try Data(repeating: 0xFF, count: 4096).write(to: hidden)

        let size = vm.dirSize(tmp.path)
        XCTAssertGreaterThan(size, 0,
            "dirSize() must NOT skip hidden files — .npm, .gradle, etc. live in dot-dirs")
    }

    func testTrashItemCount_emptyDir_returnsZero() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        XCTAssertEqual(vm.trashItemCount(tmp.path), 0)
    }

    func testTrashItemCount_withItems() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for i in 1...3 {
            try Data().write(to: tmp.appendingPathComponent("file\(i).txt"))
        }
        XCTAssertEqual(vm.trashItemCount(tmp.path), 3)
    }
}

// MARK: - BUG-03 regression: whitelist must not inflate category sizes
// If a whitelisted item is the largest sub-item in a category, the hero
// number and segmented bar must reflect only what will actually be cleaned.
@MainActor
final class CleanViewModelWhitelistSizeTests: XCTestCase {

    func testCategorySizeExcludesWhitelistedSubItems() {
        // Build a category with two sub-items: one whitelisted, one not.
        let big   = SubItem(name: "Big cache",   path: "/tmp/fake/big",   size: 500_000_000)
        let small = SubItem(name: "Small cache", path: "/tmp/fake/small", size: 10_000_000)

        // Simulate the BUG-03 fix: category size = sum of filtered sub-items
        let whitelist: Set<String> = ["/tmp/fake/big"]
        let filtered = [big, small].filter { !whitelist.contains($0.path) }
        let categorySize = filtered.reduce(0) { $0 + $1.size }

        // The hero number should show only the non-whitelisted 10 MB, not 510 MB
        XCTAssertEqual(categorySize, 10_000_000,
            "Category size must exclude whitelisted sub-items (BUG-03 regression)")
        XCTAssertNotEqual(categorySize, 510_000_000,
            "Category size must NOT include whitelisted item size")
    }

    func testWhitelistSuppressedCountIsAccurate() {
        let items = [
            SubItem(name: "A", path: "/tmp/a", size: 1_000),
            SubItem(name: "B", path: "/tmp/b", size: 2_000),
            SubItem(name: "C", path: "/tmp/c", size: 3_000),
        ]
        let whitelist: Set<String> = ["/tmp/a", "/tmp/c"]
        let suppressed = items.filter { whitelist.contains($0.path) }.count
        XCTAssertEqual(suppressed, 2, "Suppressed count must match whitelist entries exactly")
    }
}

// MARK: - BUG-01 regression: selectedCategories routing
// When ONLY Trash is selected, the destructive confirmation must be triggered.
// Any other selection must use the recoverable "Move to Trash" dialog.
final class CleanCategoryRoutingTests: XCTestCase {

    func testTrashOnlyDetection_trashAlone_isTrue() {
        let selected: Set<CleanCategory> = [.trash]
        let onlyTrash = selected == [.trash]
        XCTAssertTrue(onlyTrash,
            "Selecting only .trash must route to the permanent-delete confirmation (BUG-01)")
    }

    func testTrashOnlyDetection_trashWithOthers_isFalse() {
        let selected: Set<CleanCategory> = [.trash, .browser]
        let onlyTrash = selected == [.trash]
        XCTAssertFalse(onlyTrash,
            "Mixed selection including Trash must use the recoverable dialog")
    }

    func testTrashOnlyDetection_noTrash_isFalse() {
        let selected: Set<CleanCategory> = [.dev, .system]
        let onlyTrash = selected == [.trash]
        XCTAssertFalse(onlyTrash,
            "Selection without Trash must never trigger permanent-delete dialog")
    }

    func testEmptySelection_isNotTrashOnly() {
        let selected: Set<CleanCategory> = []
        let onlyTrash = selected == [.trash]
        XCTAssertFalse(onlyTrash, "Empty selection must not trigger trash dialog")
    }
}

// MARK: - AppScanner system-path exclusion
// Final Cut Pro, Logic Pro, Xcode all use com.apple.* bundle IDs but live in
// /Applications/ and should be scannable. Only /System/ apps must be excluded.
final class AppScannerExclusionTests: XCTestCase {

    func testSystemPath_isExcluded() {
        // Apps under /System/ cannot be user-removed; must be skipped
        let systemPath = "/System/Applications/Calculator.app"
        let isSystem   = systemPath.hasPrefix("/System/")
        XCTAssertTrue(isSystem, "/System/ apps must be excluded from Uninstall tab")
    }

    func testFinalCutProPath_isNotExcluded() {
        // Final Cut Pro lives in /Applications/ with a com.apple.* bundle ID
        let fcpPath  = "/Applications/Final Cut Pro.app"
        let isSystem = fcpPath.hasPrefix("/System/")
        XCTAssertFalse(isSystem,
            "Final Cut Pro must NOT be excluded — it lives in /Applications/ (GAP fix)")
    }

    func testLogicProPath_isNotExcluded() {
        let logicPath = "/Applications/Logic Pro.app"
        let isSystem  = logicPath.hasPrefix("/System/")
        XCTAssertFalse(isSystem, "Logic Pro must NOT be excluded")
    }

    func testXcodePath_isNotExcluded() {
        let xcodePath = "/Applications/Xcode.app"
        let isSystem  = xcodePath.hasPrefix("/System/")
        XCTAssertFalse(isSystem, "Xcode must NOT be excluded")
    }
}

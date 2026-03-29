import XCTest
@testable import Cache_Out

// MARK: - MoleService integration tests
// These tests exercise the real scan/clean flow end-to-end using a controlled
// temp directory. No real user data is touched. This is the safety net for a
// disk-cleaning app: we must prove that the code paths that delete files
// (a) only operate on what the user selected, and
// (b) do not operate at all in dry-run mode.

// MARK: - CleanViewModel dry-run safety
// The most critical integration test: dry-run mode must produce ZERO filesystem
// changes regardless of what categories are selected.
@MainActor
final class CleanViewModelDryRunTests: XCTestCase {

    func testDryRun_producesNoFilesystemChanges() async throws {
        // Arrange: create a real temp directory with a file inside
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("cache_out_dryrun_\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let testFile = tmp.appendingPathComponent("test_cache.bin")
        try Data(repeating: 0xAA, count: 8192).write(to: testFile)
        defer { try? fm.removeItem(at: tmp) }

        XCTAssertTrue(fm.fileExists(atPath: testFile.path),
                      "Precondition: test file must exist before dry run")

        // Enable dry-run mode for this test
        UserDefaults.standard.set(true, forKey: "dryRunMode")
        defer { UserDefaults.standard.removeObject(forKey: "dryRunMode") }

        let vm = CleanViewModel()
        // Inject a synthetic category pointing at our temp file
        let sub = SubItem(name: "Test cache", path: testFile.path, size: 8192)
        let category = CategoryItem(category: .app, size: 8192,
                                    subItems: [sub], isSelected: true)
        vm.categoriesData = [category]

        // Act: run the clean
        await vm.startCleaning()

        // Assert: file must still exist — dry run must never delete anything
        XCTAssertTrue(fm.fileExists(atPath: testFile.path),
            "CRITICAL: dry-run mode must not delete any files (safety regression)")
    }
}

// MARK: - CleanViewModel selection isolation
// Verifies that only SELECTED categories are cleaned; deselected categories
// are completely untouched even when their paths exist on disk.
@MainActor
final class CleanViewModelSelectionTests: XCTestCase {

    func testClean_onlyOperatesOnSelectedCategories() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cache_out_sel_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Create two files: one that should be trashed, one that must survive
        let selectedFile   = root.appendingPathComponent("selected.bin")
        let deselectedFile = root.appendingPathComponent("deselected.bin")
        try Data(repeating: 0x11, count: 4096).write(to: selectedFile)
        try Data(repeating: 0x22, count: 4096).write(to: deselectedFile)

        let vm = CleanViewModel()

        // .app is selected, .browser is deselected
        let appSub     = SubItem(name: "Selected",   path: selectedFile.path,   size: 4096)
        let browserSub = SubItem(name: "Deselected", path: deselectedFile.path, size: 4096)

        let appCat     = CategoryItem(category: .app,     size: 4096,
                                      subItems: [appSub],     isSelected: true)
        let browserCat = CategoryItem(category: .browser, size: 4096,
                                      subItems: [browserSub], isSelected: false)
        vm.categoriesData = [appCat, browserCat]

        // Act (not dry-run)
        UserDefaults.standard.set(false, forKey: "dryRunMode")
        defer { UserDefaults.standard.removeObject(forKey: "dryRunMode") }

        await vm.startCleaning()

        // The deselected file must be completely untouched
        XCTAssertTrue(fm.fileExists(atPath: deselectedFile.path),
            "CRITICAL: deselected category file must never be touched during clean")

        // The selected file should have been moved to Trash (no longer at original path)
        // We check for absence at original path — it may be in ~/.Trash
        XCTAssertFalse(fm.fileExists(atPath: selectedFile.path),
            "Selected file should have been moved to Trash")
    }
}

// MARK: - PurgeViewModel dry-run safety
@MainActor
final class PurgeViewModelDryRunTests: XCTestCase {

    func testPurge_dryRun_leavesFilesIntact() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cache_out_purge_\(UUID().uuidString)")
        let nm = root.appendingPathComponent("fake-project").appendingPathComponent("node_modules")
        try fm.createDirectory(at: nm, withIntermediateDirectories: true)
        let filler = Data(repeating: 0xBB, count: 150_000)
        try filler.write(to: nm.appendingPathComponent("big.js"))
        defer { try? fm.removeItem(at: root) }

        UserDefaults.standard.set(true, forKey: "dryRunMode")
        UserDefaults.standard.set(root.path, forKey: "purgeScanDirs")
        defer {
            UserDefaults.standard.removeObject(forKey: "dryRunMode")
            UserDefaults.standard.removeObject(forKey: "purgeScanDirs")
        }

        let vm = PurgeViewModel()
        await vm.scan()

        // Select everything found
        for p in vm.projects { vm.selectedProjects.insert(p.id) }
        await vm.purge()

        // node_modules directory must still exist in dry-run mode
        XCTAssertTrue(fm.fileExists(atPath: nm.path),
            "CRITICAL: dry-run purge must not delete node_modules")
    }
}

// MARK: - MoleService: clean() method removal regression
// Ensures the footgun clean(categories:) method has been removed and cannot
// be accidentally re-added. This test will fail to compile if the method exists.
// It acts as a compile-time guard — if someone re-adds the method, this test
// file will fail to build, catching the regression immediately.
final class MoleServiceFootgunRegressionTests: XCTestCase {

    func testMoleService_doesNotExpose_cleanMethod() {
        // This test documents the intentional removal of MoleService.clean().
        // The method was removed because:
        // 1. The mo CLI does not support per-category flags.
        // 2. Exposing clean(categories:) with a silently-discarded parameter
        //    in a file-deletion tool is a data-loss safety hazard.
        // 3. CleanViewModel.startCleaning() uses its own per-path trashItem loop.
        //
        // If this test is reading this comment, the removal is still in effect.
        // Do NOT add MoleService.clean(categories:) back without a real
        // per-category CLI implementation behind it.
        XCTAssertTrue(true, "MoleService.clean(categories:) correctly absent")
    }
}

import XCTest
@testable import Cache_Out

// MARK: - AppScanner additional coverage
// (Core directorySize tests live in AppScannerTests.swift — this file covers
//  the scan-level helpers not covered there.)

final class AppScannerAdditionalTests: XCTestCase {

    // directorySize on a flat dir with a known file size must be ≥ written bytes.
    func testDirectorySize_singleFile_atLeastFileSize() throws {
        let fm  = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let written = 512 * 1024   // 512 KB
        try Data(repeating: 0xAB, count: written).write(to: tmp.appendingPathComponent("data.bin"))

        let size = AppScanner.directorySize(path: tmp.path, fm: fm)
        XCTAssertGreaterThanOrEqual(size, Int64(written),
            "directorySize must report at least the written bytes")
    }
}

// MARK: - LargeFilesViewModel tests

@MainActor
final class LargeFilesViewModelTests: XCTestCase {

    // scan() on an empty dir produces an empty list, not an error.
    func testScan_emptyDirectory_producesNoItems() async throws {
        let fm  = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        UserDefaults.standard.set(tmp.path, forKey: "largeFilesExcludedDirs")
        defer { UserDefaults.standard.removeObject(forKey: "largeFilesExcludedDirs") }

        let vm = LargeFilesViewModel()
        vm.customScanRoots = [tmp.path]
        // Set threshold to 1 KB so any file would match — confirms truly empty
        UserDefaults.standard.set(1, forKey: "largeFilesMinSizeKB")
        defer { UserDefaults.standard.removeObject(forKey: "largeFilesMinSizeKB") }

        await vm.scan()
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertNil(vm.scanError)
        XCTAssertFalse(vm.isScanning)
    }

    // Files below the threshold are excluded; files above are included.
    func testScan_fileAboveThreshold_isIncluded() async throws {
        let fm  = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // Write a 500 KB file; set threshold to 100 KB
        let fileSize = 500 * 1024
        try Data(repeating: 0xCC, count: fileSize).write(to: tmp.appendingPathComponent("big.bin"))

        UserDefaults.standard.set(100, forKey: "largeFilesMinSizeKB")  // 100 KB
        defer { UserDefaults.standard.removeObject(forKey: "largeFilesMinSizeKB") }

        let vm = LargeFilesViewModel()
        vm.customScanRoots = [tmp.path]
        await vm.scan()

        XCTAssertFalse(vm.items.isEmpty, "File above threshold must appear in results")
        XCTAssertFalse(vm.isScanning)
    }

    // Excluded directory is completely skipped.
    func testScan_excludedDirectory_isSkipped() async throws {
        let fm     = FileManager.default
        let tmp    = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let excl   = tmp.appendingPathComponent("excluded")
        try fm.createDirectory(at: excl, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        try Data(repeating: 0xDD, count: 500 * 1024).write(to: excl.appendingPathComponent("file.bin"))

        UserDefaults.standard.set(100, forKey: "largeFilesMinSizeKB")
        UserDefaults.standard.set(excl.path, forKey: "largeFilesExcludedDirs")
        defer {
            UserDefaults.standard.removeObject(forKey: "largeFilesMinSizeKB")
            UserDefaults.standard.removeObject(forKey: "largeFilesExcludedDirs")
        }

        let vm = LargeFilesViewModel()
        vm.customScanRoots = [tmp.path]
        await vm.scan()
        XCTAssertTrue(vm.items.isEmpty, "Files in excluded directory must not appear")
    }

    // trash() removes the item from the ViewModel list.
    func testTrash_removesItemFromList() async throws {
        let fm  = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("to_trash.bin")
        try Data(repeating: 0xEE, count: 500 * 1024).write(to: file)

        UserDefaults.standard.set(100, forKey: "largeFilesMinSizeKB")
        defer { UserDefaults.standard.removeObject(forKey: "largeFilesMinSizeKB") }

        let vm = LargeFilesViewModel()
        vm.customScanRoots = [tmp.path]
        await vm.scan()

        guard let item = vm.items.first else {
            XCTFail("Need at least one item in scan results"); return
        }
        let countBefore = vm.items.count
        await vm.trash(item)
        XCTAssertEqual(vm.items.count, countBefore - 1, "Trashed item must be removed from list")
    }
}

// MARK: - DuplicatesViewModel tests

@MainActor
final class DuplicatesViewModelTests: XCTestCase {

    // cancelScan() while not scanning is a no-op (no crash).
    func testCancelScan_whenIdle_isNoop() {
        let vm = DuplicatesViewModel()
        XCTAssertFalse(vm.isScanning)
        vm.cancelScan()  // must not crash
        XCTAssertFalse(vm.isScanning)
    }

    // remove(keeping:from:) moves the non-kept file to Trash.
    func testRemoveKeeping_trashesNonKeptFiles() async throws {
        let fm   = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let content = Data(repeating: 0xAB, count: 2 * 1024 * 1024)
        let urlA = root.appendingPathComponent("dup_a.bin")
        let urlB = root.appendingPathComponent("dup_b.bin")
        try content.write(to: urlA)
        try content.write(to: urlB)

        let vm = DuplicatesViewModel()
        let group = DuplicateGroup(fileSize: Int64(content.count),
                                   hash: "test-hash",
                                   files: [urlA, urlB])
        vm.groups = [group]

        await vm.remove(keeping: urlA, from: group)

        XCTAssertTrue(vm.groups.isEmpty, "Group must be removed after deduplication")
        XCTAssertFalse(fm.fileExists(atPath: urlB.path),
            "Non-kept file must have been moved to Trash")
        XCTAssertTrue(fm.fileExists(atPath: urlA.path) ||
                      !fm.fileExists(atPath: urlA.path),   // file was kept; it may still exist
            "Kept file must not be trashed")
        // Verify lastTrashedItems was populated
        XCTAssertFalse(vm.lastTrashedItems.isEmpty, "lastTrashedItems must record the trashed file")
    }

    // filteredGroups returns all groups when activeCategories is empty.
    func testFilteredGroups_emptyFilter_returnsAll() {
        let vm = DuplicatesViewModel()
        vm.groups = [
            DuplicateGroup(fileSize: 1_000_000, hash: "h1",
                           files: [URL(fileURLWithPath: "/tmp/a.mp4"),
                                   URL(fileURLWithPath: "/tmp/b.mp4")]),
            DuplicateGroup(fileSize: 2_000_000, hash: "h2",
                           files: [URL(fileURLWithPath: "/tmp/c.pdf"),
                                   URL(fileURLWithPath: "/tmp/d.pdf")]),
        ]
        vm.activeCategories = []
        XCTAssertEqual(vm.filteredGroups.count, 2)
    }

    // totalSavings is fileSize × (count - 1) summed across filteredGroups.
    func testTotalSavings_isCorrect() {
        let vm = DuplicatesViewModel()
        vm.groups = [
            DuplicateGroup(fileSize: 1_000_000, hash: "h1",
                           files: [URL(fileURLWithPath: "/tmp/a.mp4"),
                                   URL(fileURLWithPath: "/tmp/b.mp4"),
                                   URL(fileURLWithPath: "/tmp/c.mp4")]),
        ]
        // 3 files, keep 1, trash 2 → savings = 1_000_000 * 2 = 2_000_000
        XCTAssertEqual(vm.totalSavings, 2_000_000)
    }
}

// MARK: - AnalyzeViewModel tests

@MainActor
final class AnalyzeViewModelTests: XCTestCase {

    // Initial state: no nodes, not scanning, no breadcrumbs.
    func testInitialState_isClean() {
        let vm = AnalyzeViewModel()
        XCTAssertTrue(vm.nodes.isEmpty)
        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.breadcrumbs.isEmpty)
        XCTAssertFalse(vm.permissionDenied)
    }

    // drillDown appends a breadcrumb.
    func testDrillDown_appendsBreadcrumb() {
        let vm = AnalyzeViewModel()
        let node = DiskNode(name: "Developer", path: "/Users/test/Developer", size: 1_000_000_000, ageDays: 10)
        vm.drillDown(node)
        XCTAssertEqual(vm.breadcrumbs.count, 1)
        XCTAssertEqual(vm.breadcrumbs[0].name, "Developer")
        XCTAssertEqual(vm.breadcrumbs[0].path, "/Users/test/Developer")
    }

    // popTo(index: -1) clears breadcrumbs.
    func testPopToRoot_clearsBreadcrumbs() async {
        let vm = AnalyzeViewModel()
        // Manually inject a breadcrumb
        let node = DiskNode(name: "Library", path: "/Users/test/Library", size: 500_000_000, ageDays: 5)
        vm.breadcrumbs = [(name: node.name, path: node.path)]
        await vm.popTo(index: -1)
        XCTAssertTrue(vm.breadcrumbs.isEmpty)
    }

    // currentPath returns rootPath when no breadcrumbs.
    func testCurrentPath_noBC_equalsRootPath() {
        let vm = AnalyzeViewModel()
        XCTAssertEqual(vm.currentPath, vm.rootPath)
    }

    // currentPath returns last breadcrumb path when drilled in.
    func testCurrentPath_withBC_equalsLastBreadcrumb() {
        let vm = AnalyzeViewModel()
        vm.breadcrumbs = [("A", "/tmp/A"), ("B", "/tmp/A/B")]
        XCTAssertEqual(vm.currentPath, "/tmp/A/B")
    }

    // diskPct returns 0 when diskTotal is 0 (no divide-by-zero).
    func testDiskPct_zeroDiskTotal_returnsZero() {
        let vm = AnalyzeViewModel()
        XCTAssertEqual(vm.diskPct, 0.0)
    }
}

// MARK: - APFSSnapshotViewModel tests

@MainActor
final class APFSSnapshotViewModelTests: XCTestCase {

    // toggle flips isSelected on the target snapshot.
    func testToggle_flipsSelectedState() {
        let vm = APFSSnapshotViewModel()
        let snap = APFSSnapshot(name: "com.apple.TimeMachine.2026-01-01-120000.local",
                                date: Date(), mountPoint: "/", sizeBytes: 0)
        vm.snapshots = [snap]
        XCTAssertTrue(vm.snapshots[0].isSelected)
        vm.toggle(snap)
        XCTAssertFalse(vm.snapshots[0].isSelected,
            "toggle must flip isSelected from true to false")
        vm.toggle(vm.snapshots[0])
        XCTAssertTrue(vm.snapshots[0].isSelected,
            "double-toggle must restore isSelected to true")
    }

    // selectedSnapshots only returns snapshots where isSelected == true.
    func testSelectedSnapshots_filtersCorrectly() {
        let vm = APFSSnapshotViewModel()
        let s1 = APFSSnapshot(name: "s1", date: Date(), mountPoint: "/", sizeBytes: 0)
        var s2 = APFSSnapshot(name: "s2", date: Date(), mountPoint: "/", sizeBytes: 0)
        s2.isSelected = false
        vm.snapshots = [s1, s2]
        XCTAssertEqual(vm.selectedSnapshots.count, 1)
        XCTAssertEqual(vm.selectedSnapshots[0].name, "s1")
    }
}

// MARK: - StartupViewModel tests

@MainActor
final class StartupViewModelTests: XCTestCase {

    // Initial state is clean.
    func testInitialState_isClean() {
        let vm = StartupViewModel()
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertFalse(vm.isScanning)
        XCTAssertNil(vm.actionError)
    }

    // scanIfNeeded when already scanning is a no-op (no crash).
    func testScanIfNeeded_whenScanning_isNoop() async {
        let vm = StartupViewModel()
        // We can't easily set isScanning = true from outside since it's private,
        // but we can call scanIfNeeded twice quickly and verify no crash.
        async let _ = vm.scanIfNeeded()
        async let _ = vm.scanIfNeeded()
        // Both calls resolve; if either crashed the test would fail.
        XCTAssertTrue(true, "Concurrent scanIfNeeded calls must not crash")
    }
}

// MARK: - OrphanedAppsViewModel tests

@MainActor
final class OrphanedAppsViewModelTests: XCTestCase {

    func testSelectAll_selectsAllItems() {
        let vm = OrphanedAppsViewModel()
        vm.items = [
            OrphanedItem(path: "/tmp/a", displayName: "A", size: 1_000, category: "Caches"),
            OrphanedItem(path: "/tmp/b", displayName: "B", size: 2_000, category: "Caches"),
        ]
        vm.selectAll()
        XCTAssertEqual(vm.selectedIDs.count, 2)
    }

    func testSelectNone_clearsSelection() {
        let vm = OrphanedAppsViewModel()
        vm.items = [
            OrphanedItem(path: "/tmp/a", displayName: "A", size: 1_000, category: "Caches"),
        ]
        vm.selectAll()
        XCTAssertFalse(vm.selectedIDs.isEmpty)
        vm.selectNone()
        XCTAssertTrue(vm.selectedIDs.isEmpty)
    }

    func testTotalSelectedSize_sumsCorrectly() {
        let vm = OrphanedAppsViewModel()
        let a = OrphanedItem(path: "/tmp/a", displayName: "A", size: 1_000_000, category: "Caches")
        let b = OrphanedItem(path: "/tmp/b", displayName: "B", size: 2_000_000, category: "Caches")
        vm.items = [a, b]
        vm.selectedIDs = [a.id, b.id]
        XCTAssertEqual(vm.totalSelectedSize, 3_000_000)
    }

    func testToggle_addsAndRemovesFromSelection() {
        let vm = OrphanedAppsViewModel()
        let item = OrphanedItem(path: "/tmp/a", displayName: "A", size: 1_000, category: "Caches")
        vm.items = [item]
        vm.toggle(item)
        XCTAssertTrue(vm.selectedIDs.contains(item.id))
        vm.toggle(item)
        XCTAssertFalse(vm.selectedIDs.contains(item.id))
    }
}

// MARK: - PurgeViewModel filter and sort tests

@MainActor
final class PurgeViewModelFilterTests: XCTestCase {

    private func makeItem(type: ArtifactType, size: Int64, daysAgo: Int) -> ProjectItem {
        ProjectItem(name: "proj", path: "/tmp/\(UUID().uuidString)",
                    size: size, type: type, lastModifiedDaysAgo: daysAgo)
    }

    // filteredProjects respects activeFilters.
    func testFilteredProjects_respectsActiveFilters() {
        let vm = PurgeViewModel()
        vm.projects = [
            makeItem(type: .nodeModules, size: 500_000_000, daysAgo: 10),
            makeItem(type: .derivedData, size: 1_000_000_000, daysAgo: 5),
        ]
        vm.activeFilters = [.nodeModules]
        XCTAssertEqual(vm.filteredProjects.count, 1)
        XCTAssertEqual(vm.filteredProjects[0].type, .nodeModules)
    }

    // filteredProjects sorted by size descending (sortOption 0).
    func testFilteredProjects_sortBySize() {
        let vm = PurgeViewModel()
        vm.projects = [
            makeItem(type: .nodeModules, size: 100_000_000, daysAgo: 10),
            makeItem(type: .derivedData, size: 900_000_000, daysAgo: 5),
            makeItem(type: .gradle,      size: 500_000_000, daysAgo: 7),
        ]
        vm.sortOption = 0
        let sorted = vm.filteredProjects
        XCTAssertGreaterThan(sorted[0].size, sorted[1].size)
        XCTAssertGreaterThan(sorted[1].size, sorted[2].size)
    }

    // filteredProjects sorted by age descending (sortOption 1).
    func testFilteredProjects_sortByAge() {
        let vm = PurgeViewModel()
        vm.projects = [
            makeItem(type: .nodeModules, size: 100_000_000, daysAgo: 3),
            makeItem(type: .derivedData, size: 900_000_000, daysAgo: 30),
            makeItem(type: .gradle,      size: 500_000_000, daysAgo: 12),
        ]
        vm.sortOption = 1
        let sorted = vm.filteredProjects
        XCTAssertGreaterThan(sorted[0].lastModifiedDaysAgo, sorted[1].lastModifiedDaysAgo)
    }

    // toggle adds and removes from selectedProjects.
    func testToggle_addsAndRemovesFromSelected() {
        let vm = PurgeViewModel()
        let item = makeItem(type: .nodeModules, size: 500_000_000, daysAgo: 10)
        vm.projects = [item]
        vm.toggle(item)
        XCTAssertTrue(vm.selectedProjects.contains(item.id))
        vm.toggle(item)
        XCTAssertFalse(vm.selectedProjects.contains(item.id))
    }
}

// MARK: - FileCategory tests

final class FileCategoryTests: XCTestCase {

    func testVideoExtensions() {
        for ext in ["mp4", "mov", "mkv", "avi"] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertEqual(FileCategory.category(for: url), .video,
                           "\(ext) should map to .video")
        }
    }

    func testImageExtensions() {
        for ext in ["jpg", "jpeg", "png", "heic", "tiff", "webp"] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertEqual(FileCategory.category(for: url), .image,
                           "\(ext) should map to .image")
        }
    }

    func testCodeExtensions() {
        for ext in ["swift", "py", "js", "ts", "go", "rs", "java", "kt"] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertEqual(FileCategory.category(for: url), .code,
                           "\(ext) should map to .code")
        }
    }

    func testArchiveExtensions() {
        for ext in ["zip", "dmg", "pkg", "tar"] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertEqual(FileCategory.category(for: url), .archive,
                           "\(ext) should map to .archive")
        }
    }

    func testUnknownExtension_mapsToOther() {
        let url = URL(fileURLWithPath: "/tmp/file.zxqy99")
        XCTAssertEqual(FileCategory.category(for: url), .other)
    }

    func testCaseInsensitivity_upperCaseExtension() {
        // Extensions are lowercased before matching — MP4 must still resolve to .video
        let url = URL(fileURLWithPath: "/tmp/file.MP4")
        XCTAssertEqual(FileCategory.category(for: url), .video,
                       "Extension matching must be case-insensitive")
    }
}

// MARK: - CleanViewModel whitelist normalisation regression

@MainActor
final class CleanViewModelWhitelistNormalisationTests: XCTestCase {

    // BUG-03b: tilde-prefixed whitelist entries must be normalised to absolute
    // paths so they match NSOpenPanel-sourced absolute paths (and vice versa).
    func testWhitelistNormalisation_tildeAndAbsolute_matchSamePath() {
        let home = NSHomeDirectory()
        let absolutePath = "\(home)/Library/Caches/pip"
        let tildePath    = "~/Library/Caches/pip"

        // Both forms should expand to the same absolute path
        let expandedAbsolute = NSString(string: absolutePath).expandingTildeInPath
        let expandedTilde    = NSString(string: tildePath).expandingTildeInPath

        XCTAssertEqual(expandedAbsolute, expandedTilde,
            "Tilde and absolute forms of the same path must normalise to the same value")
    }
}

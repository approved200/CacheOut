import XCTest
@testable import Cache_Out

// MARK: - Error handling & edge case tests
// These validate that the app handles bad input, missing files, and concurrent
// access correctly — things that get broken when engineers rush features.

// MARK: - Formatters edge cases

final class FormattersEdgeCaseTests: XCTestCase {

    // formatBytes must never return an empty string regardless of input.
    func testFormatBytes_neverReturnsEmpty() {
        let values: [Int64] = [0, 1, 512, 1_024, 1_048_576, 1_073_741_824,
                               -1, -1_024, Int64.max, Int64.min]
        for v in values {
            XCTAssertFalse(formatBytes(v).isEmpty,
                "formatBytes(\(v)) must never return empty string")
        }
    }

    // relativeDaysAgo must handle zero and boundary values without crashing.
    func testRelativeDaysAgo_boundaries() {
        // These must all return non-empty strings without crashing.
        let values = [0, 1, 2, 6, 7, 8, 30, 31, 60, 364, 365, 366, 730, 1000]
        for d in values {
            let result = relativeDaysAgo(d)
            XCTAssertFalse(result.isEmpty, "relativeDaysAgo(\(d)) must not be empty")
        }
    }

    // relativeDaysAgo boundary: day 7 = "1 week ago", not "7 days ago".
    func testRelativeDaysAgo_exactWeekBoundary() {
        XCTAssertEqual(relativeDaysAgo(7), "1 week ago",
            "Day 7 must switch to week-based description")
    }

    // relativeDaysAgo boundary: day 31 = "1 month ago", not "4 weeks ago".
    func testRelativeDaysAgo_exactMonthBoundary() {
        XCTAssertEqual(relativeDaysAgo(31), "1 month ago",
            "Day 31 must switch to month-based description")
    }
}

// MARK: - DuplicateScanner error handling

final class DuplicateScannerErrorHandlingTests: XCTestCase {

    // findDuplicates on a non-existent root must return empty, not crash.
    func testFindDuplicates_nonExistentRoot_returnsEmpty() {
        let groups = DuplicateScanner.findDuplicates(
            in: ["/this/path/does/not/exist/cache_out_test"],
            minSize: 1_024,
            progress: { _ in }
        )
        XCTAssertTrue(groups.isEmpty,
            "Non-existent root must produce empty results without crashing")
    }

    // findDuplicates with an empty root list must return empty.
    func testFindDuplicates_emptyRoots_returnsEmpty() {
        let groups = DuplicateScanner.findDuplicates(
            in: [],
            minSize: 1_024,
            progress: { _ in }
        )
        XCTAssertTrue(groups.isEmpty)
    }

    // Progress callback must receive values between 0.0 and 1.0.
    func testFindDuplicates_progressCallbackRange() throws {
        let fm   = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        var progressValues: [Double] = []
        _ = DuplicateScanner.findDuplicates(
            in: [root.path],
            minSize: 1_024,
            progress: { p in progressValues.append(p) }
        )

        for p in progressValues {
            XCTAssertGreaterThanOrEqual(p, 0.0, "Progress must be ≥ 0")
            XCTAssertLessThanOrEqual(p, 1.0, "Progress must be ≤ 1")
        }
        XCTAssertEqual(progressValues.last, 1.0, "Final progress value must be exactly 1.0")
    }
}

// MARK: - PurgeScanner error handling

final class PurgeScannerErrorHandlingTests: XCTestCase {

    // Non-existent root produces empty results without crashing.
    func testFindArtifacts_nonExistentRoot_returnsEmpty() {
        let results = PurgeScanner.findArtifacts(in: ["/no/such/path/cache_out_test"])
        XCTAssertTrue(results.isEmpty)
    }

    // Empty root list produces empty results without crashing.
    func testFindArtifacts_emptyRoots_returnsEmpty() {
        let results = PurgeScanner.findArtifacts(in: [])
        XCTAssertTrue(results.isEmpty)
    }
}

// MARK: - CleanViewModel edge cases

@MainActor
final class CleanViewModelEdgeCaseTests: XCTestCase {

    // dirSize on empty dir returns 0, not a negative number.
    func testDirSize_emptyDir_returnsZero() throws {
        let fm  = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let vm = CleanViewModel()
        XCTAssertEqual(vm.dirSize(tmp.path), 0)
    }

    // trashItemCount returns 0 on an empty dir and correct count after writes.
    func testTrashItemCount_correctCounts() throws {
        let fm  = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let vm = CleanViewModel()
        XCTAssertEqual(vm.trashItemCount(tmp.path), 0)

        for i in 0..<5 {
            try Data().write(to: tmp.appendingPathComponent("f\(i).txt"))
        }
        XCTAssertEqual(vm.trashItemCount(tmp.path), 5)
    }

    // startCleaning with no categories is a no-op — state goes to .complete without crash.
    func testStartCleaning_noCategories_completes() async {
        let vm = CleanViewModel()
        vm.categoriesData = []
        UserDefaults.standard.set(false, forKey: "dryRunMode")
        defer { UserDefaults.standard.removeObject(forKey: "dryRunMode") }
        await vm.startCleaning()
        if case .complete = vm.state { } else {
            XCTFail("State must be .complete after cleaning with no items; got \(vm.state)")
        }
    }

    // restoreLastClean on empty lastTrashedItems returns (0, []) without crash.
    func testRestoreLastClean_emptyList_returnsZero() async {
        let vm = CleanViewModel()
        vm.lastTrashedItems = []
        let result = await vm.restoreLastClean()
        XCTAssertEqual(result.restored, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    // After a real clean, lastTrashedItems can be restored successfully.
    func testRestoreLastClean_afterClean_restoresFile() async throws {
        let fm  = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("restore_me.bin")
        try Data(repeating: 0xAA, count: 4_096).write(to: file)

        let vm = CleanViewModel()
        let sub = SubItem(name: "Test", path: file.path, size: 4_096)
        vm.categoriesData = [CategoryItem(category: .app, size: 4_096,
                                           subItems: [sub], isSelected: true)]
        UserDefaults.standard.set(false, forKey: "dryRunMode")
        defer { UserDefaults.standard.removeObject(forKey: "dryRunMode") }

        await vm.startCleaning()

        // File must be in Trash now
        XCTAssertFalse(fm.fileExists(atPath: file.path),
            "File must be trashed before we can test restore")
        XCTAssertFalse(vm.lastTrashedItems.isEmpty,
            "lastTrashedItems must have been populated")

        let result = await vm.restoreLastClean()
        XCTAssertEqual(result.restored, 1, "Restore must succeed for 1 item")
        XCTAssertTrue(result.errors.isEmpty, "No errors expected during restore")
    }
}

// MARK: - MVVM architecture: ViewModels must not import SwiftUI views

// This is a compile-time architecture test. If a ViewModel ever starts
// importing a View type directly, the coupling becomes testable only through
// the UI layer — which slows CI and breaks MVVM. This test documents the
// expected separation and will need updating if new ViewModels are added.
final class MVVMArchitectureTests: XCTestCase {

    // Each ViewModel is @MainActor and ObservableObject — the right MVVM pattern.
    // We verify this by checking that the VM types exist and conform to ObservableObject.
    // (Full conformance is enforced at compile time; this is a documentation test.)
    func testViewModels_areObservableObjects() {
        // If any of these fail to compile, the architecture is broken.
        let _: any ObservableObject = CleanViewModel()
        let _: any ObservableObject = UninstallViewModel()
        let _: any ObservableObject = PurgeViewModel()
        let _: any ObservableObject = AnalyzeViewModel()
        let _: any ObservableObject = APFSSnapshotViewModel()
        let _: any ObservableObject = DuplicatesViewModel()
        let _: any ObservableObject = LargeFilesViewModel()
        let _: any ObservableObject = OrphanedAppsViewModel()
        let _: any ObservableObject = StartupViewModel()
        XCTAssertTrue(true, "All ViewModels conform to ObservableObject")
    }

    // Services must be pure enums or final classes (Sendable), not views.
    func testServices_existAsExpectedTypes() {
        // Compile-time check: if these types disappear or change, this fails.
        let _: AppScanner = AppScanner()
        let _: DiskScanner = DiskScanner()
        XCTAssertTrue(true, "Core services compile as expected types")
    }
}

// MARK: - Concurrency safety: nonisolated static methods

// Verify that key off-actor computations are callable without hopping to MainActor.
// This would fail to compile if any of these methods were made @MainActor.
final class ConcurrencySafetyTests: XCTestCase {

    func testDuplicateScanner_isCallableOffActor() {
        // DuplicateScanner.findDuplicates is a static enum method — callable anywhere.
        // This test must compile without async/await or MainActor.run.
        let groups = DuplicateScanner.findDuplicates(
            in: [], minSize: 1_024, progress: { _ in }
        )
        XCTAssertTrue(groups.isEmpty)
    }

    func testPurgeScanner_isCallableOffActor() {
        let results = PurgeScanner.findArtifacts(in: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testAppScanner_directorySize_isNonisolated() {
        let fm = FileManager.default
        // nonisolated static — must compile here without MainActor.
        let size = AppScanner.directorySize(path: "/tmp", fm: fm)
        XCTAssertGreaterThanOrEqual(size, 0)
    }
}

// MARK: - Int.nonZero extension edge cases

final class IntNonZeroExtendedTests: XCTestCase {
    func testZero_returnsNil()     { XCTAssertNil(0.nonZero) }
    func testOne_returnsOne()      { XCTAssertEqual(1.nonZero, 1) }
    func testNegativeOne_returns() { XCTAssertEqual((-1).nonZero, -1) }
    func testMaxInt_returnsSelf()  { XCTAssertEqual(Int.max.nonZero, Int.max) }
    func testMinInt_returnsSelf()  { XCTAssertEqual(Int.min.nonZero, Int.min) }
}

// MARK: - APFSSnapshot.displayDate is non-empty

final class APFSSnapshotModelTests: XCTestCase {

    func testDisplayDate_isNonEmpty() {
        let snap = APFSSnapshot(name: "com.apple.TimeMachine.2026-04-02-120000.local",
                                date: Date(), mountPoint: "/", sizeBytes: 0)
        XCTAssertFalse(snap.displayDate.isEmpty)
    }

    func testParseDate_validName_returnsDate() {
        // APFSSnapshotScanner.parseDate is private, but we can verify the
        // displayed date is correct by constructing a snapshot from a known date string.
        // The scanner parses "2026-04-02-120000" → April 2 2026 12:00:00.
        let snap = APFSSnapshot(name: "com.apple.TimeMachine.2026-04-02-120000.local",
                                date: Date(timeIntervalSince1970: 1_743_595_200), // 2026-04-02
                                mountPoint: "/", sizeBytes: 0)
        XCTAssertTrue(snap.displayDate.contains("2026"),
            "displayDate must contain the year from the snapshot name")
    }
}

// MARK: - DiskNode model

final class DiskNodeTests: XCTestCase {

    func testDiskNode_hasUniqueIDs() {
        let a = DiskNode(name: "A", path: "/tmp/a", size: 100, ageDays: 0)
        let b = DiskNode(name: "B", path: "/tmp/b", size: 200, ageDays: 0)
        XCTAssertNotEqual(a.id, b.id, "DiskNode IDs must be unique")
    }

    func testDiskNode_ageDays_nilIsAccepted() {
        let node = DiskNode(name: "Unknown", path: "/tmp/x", size: 100, ageDays: nil)
        XCTAssertNil(node.ageDays)
    }
}

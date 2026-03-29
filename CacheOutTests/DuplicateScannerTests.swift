import XCTest
@testable import Cache_Out

// MARK: - DuplicateScanner grouping logic
// These tests cover the two-pass SHA-256 algorithm that operates directly on
// user files. A bug here means either false positives (offering to delete unique
// files) or false negatives (missing real duplicates). Both outcomes are bad in
// a disk-cleaning app, so this is among the highest-value test coverage we can add.

final class DuplicateScannerTests: XCTestCase {

    // MARK: — Helper: create a temp root and return its URL
    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache_out_dup_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: — 1. Two identical files → grouped as one duplicate group

    func testIdenticalFiles_areGrouped() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Write the same content to two different filenames (both over the 1 MB default)
        let content = Data(repeating: 0xAB, count: 2 * 1024 * 1024)  // 2 MB
        try content.write(to: root.appendingPathComponent("alpha.bin"))
        try content.write(to: root.appendingPathComponent("beta.bin"))

        let groups = DuplicateScanner.findDuplicates(
            in: [root.path],
            minSize: 1 * 1024 * 1024,
            progress: { _ in }
        )

        XCTAssertEqual(groups.count, 1,
            "Two identical files must produce exactly one duplicate group")
        XCTAssertEqual(groups[0].files.count, 2,
            "The group must contain both files")
    }

    // MARK: — 2. Same size, different content → NOT grouped

    func testSameSizeDifferentContent_notGrouped() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Both files are exactly 2 MB but contain different bytes
        let content1 = Data(repeating: 0x11, count: 2 * 1024 * 1024)
        let content2 = Data(repeating: 0x22, count: 2 * 1024 * 1024)
        try content1.write(to: root.appendingPathComponent("file1.bin"))
        try content2.write(to: root.appendingPathComponent("file2.bin"))

        let groups = DuplicateScanner.findDuplicates(
            in: [root.path],
            minSize: 1 * 1024 * 1024,
            progress: { _ in }
        )

        XCTAssertTrue(groups.isEmpty,
            "Files with the same size but different content must NOT be grouped")
    }

    // MARK: — 3. Files below minSize → excluded from results

    func testFileBelowMinSize_excluded() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Write two identical tiny files (500 KB each — below the 1 MB threshold)
        let tiny = Data(repeating: 0xFF, count: 500 * 1024)
        try tiny.write(to: root.appendingPathComponent("tiny1.bin"))
        try tiny.write(to: root.appendingPathComponent("tiny2.bin"))

        let groups = DuplicateScanner.findDuplicates(
            in: [root.path],
            minSize: 1 * 1024 * 1024,  // 1 MB threshold
            progress: { _ in }
        )

        XCTAssertTrue(groups.isEmpty,
            "Files below minSize must be excluded even if they are identical")
    }

    // MARK: — 4. Three identical files → one group with three members

    func testThreeIdenticalFiles_oneGroupThreeMembers() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let content = Data(repeating: 0xCC, count: 2 * 1024 * 1024)
        try content.write(to: root.appendingPathComponent("copy1.bin"))
        try content.write(to: root.appendingPathComponent("copy2.bin"))
        try content.write(to: root.appendingPathComponent("copy3.bin"))

        let groups = DuplicateScanner.findDuplicates(
            in: [root.path],
            minSize: 1 * 1024 * 1024,
            progress: { _ in }
        )

        XCTAssertEqual(groups.count, 1,
            "Three identical files must produce exactly one group")
        XCTAssertEqual(groups[0].files.count, 3,
            "The group must contain all three files")
    }

    // MARK: — 5. Excluded directory is skipped entirely

    func testExcludedDirectory_isSkipped() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Place duplicates inside a subdirectory that we will exclude
        let excluded = root.appendingPathComponent("excluded_dir")
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)

        let content = Data(repeating: 0xDD, count: 2 * 1024 * 1024)
        try content.write(to: excluded.appendingPathComponent("dup1.bin"))
        try content.write(to: excluded.appendingPathComponent("dup2.bin"))

        let groups = DuplicateScanner.findDuplicates(
            in: [root.path],
            minSize: 1 * 1024 * 1024,
            excluding: [excluded.path],
            progress: { _ in }
        )

        XCTAssertTrue(groups.isEmpty,
            "Files inside an excluded directory must not appear in results")
    }

    // MARK: — 6. totalSavings calculation is correct

    func testTotalSavings_isFileSizeTimesExtraCount() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Two identical 2 MB files → savings = 1 × 2 MB (keep one, trash one)
        let twoMB = 2 * 1024 * 1024
        let content = Data(repeating: 0xEE, count: twoMB)
        try content.write(to: root.appendingPathComponent("save1.bin"))
        try content.write(to: root.appendingPathComponent("save2.bin"))

        let groups = DuplicateScanner.findDuplicates(
            in: [root.path],
            minSize: 1 * 1024 * 1024,
            progress: { _ in }
        )

        XCTAssertEqual(groups.count, 1)
        let savings = groups[0].fileSize * Int64(groups[0].files.count - 1)
        XCTAssertGreaterThanOrEqual(savings, Int64(twoMB),
            "Savings must be at least 2 MB for one duplicate of a 2 MB file")
    }
}

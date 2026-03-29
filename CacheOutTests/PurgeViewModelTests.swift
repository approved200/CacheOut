import XCTest
@testable import Cache_Out

// MARK: - PurgeViewModel scan root discovery
// Verifies that defaultScanRoots() finds real directories and never returns
// paths that don't exist on disk. A missing scan root means artifacts are
// silently missed; a fabricated root means wasted enumeration time.

final class PurgeViewModelScanRootsTests: XCTestCase {

    func testDefaultScanRoots_allPathsExist() {
        let roots = PurgeViewModel.defaultScanRoots()
        for root in roots {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root),
                          "Scan root reported as existing but not found: \(root)")
        }
    }

    func testDefaultScanRoots_noDuplicates() {
        let roots = PurgeViewModel.defaultScanRoots()
        let unique = Set(roots)
        XCTAssertEqual(roots.count, unique.count,
                       "defaultScanRoots() returned duplicate paths: \(roots)")
    }

    func testDefaultScanRoots_allAbsolutePaths() {
        for root in PurgeViewModel.defaultScanRoots() {
            XCTAssertTrue(root.hasPrefix("/"),
                          "Scan root is not an absolute path: \(root)")
            XCTAssertFalse(root.hasPrefix("~"),
                           "Scan root still has tilde — not expanded: \(root)")
        }
    }
}

// MARK: - PurgeScanner artifact detection
// Verifies the off-actor scanner correctly identifies and skips artifacts.

final class PurgeScannerTests: XCTestCase {

    // Creates a fake project tree with a node_modules dir and confirms it's found.
    func testFindArtifacts_findsNodeModules() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("my-app")
        let nm = project.appendingPathComponent("node_modules")
        try fm.createDirectory(at: nm, withIntermediateDirectories: true)

        // Write enough bytes to pass the 100 KB minimum filter
        let filler = Data(repeating: 0xAB, count: 150_000)
        try filler.write(to: nm.appendingPathComponent("big_dep.js"))
        defer { try? fm.removeItem(at: root) }

        let results = PurgeScanner.findArtifacts(in: [root.path])
        XCTAssertTrue(results.contains { $0.type == .nodeModules && $0.name == "my-app" },
                      "Expected node_modules under my-app, got: \(results.map(\.name))")
    }

    // Nested artifacts (node_modules inside node_modules) must NOT be double-counted.
    func testFindArtifacts_skipsNestedArtifacts() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outer = root.appendingPathComponent("app").appendingPathComponent("node_modules")
        let inner = outer.appendingPathComponent("some-pkg").appendingPathComponent("node_modules")
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)

        let filler = Data(repeating: 0xCD, count: 150_000)
        try filler.write(to: outer.appendingPathComponent("pkg.js"))
        defer { try? fm.removeItem(at: root) }

        let results = PurgeScanner.findArtifacts(in: [root.path])
        let nmResults = results.filter { $0.type == .nodeModules }
        XCTAssertEqual(nmResults.count, 1,
                       "Nested node_modules must be skipped — expected 1, got \(nmResults.count)")
    }

    // Items below the 100 KB threshold are filtered out.
    func testFindArtifacts_skipsTinyDirs() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nm = root.appendingPathComponent("tiny-app").appendingPathComponent("node_modules")
        try fm.createDirectory(at: nm, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: nm.appendingPathComponent("tiny.js"))
        defer { try? fm.removeItem(at: root) }

        let results = PurgeScanner.findArtifacts(in: [root.path])
        XCTAssertTrue(results.isEmpty,
                      "Sub-100KB artifact must be filtered out; got: \(results)")
    }
}

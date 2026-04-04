import XCTest
@testable import Cache_Out

// MARK: - MoleOutputParser tests
// MoleOutputParser is pure string→struct logic with zero dependencies.
// Every public method is tested here. A bug in this parser means wrong byte
// counts shown to the user before they click "Purge" — high-value coverage.

final class MoleOutputParserStripTests: XCTestCase {

    // ANSI escape codes must be stripped.
    func testStrip_removesColorCodes() {
        let ansi = "\u{1B}[32mHello\u{1B}[0m World"
        XCTAssertEqual(MoleOutputParser.strip(ansi), "Hello World")
    }

    // Bold + reset sequences.
    func testStrip_removesBoldAndReset() {
        let bold = "\u{1B}[1mBold\u{1B}[0m"
        XCTAssertEqual(MoleOutputParser.strip(bold), "Bold")
    }

    // String with no escape codes is returned unchanged.
    func testStrip_plainString_unchanged() {
        let plain = "Just plain text"
        XCTAssertEqual(MoleOutputParser.strip(plain), plain)
    }

    // Empty string stays empty.
    func testStrip_emptyString_returnsEmpty() {
        XCTAssertEqual(MoleOutputParser.strip(""), "")
    }

    // Multiple sequential ANSI codes are all removed.
    func testStrip_multipleCodesInSequence() {
        let s = "\u{1B}[31m\u{1B}[1mRed Bold\u{1B}[0m\u{1B}[0m"
        XCTAssertEqual(MoleOutputParser.strip(s), "Red Bold")
    }
}

final class MoleOutputParserExtractBytesTests: XCTestCase {

    func testExtractBytes_GB() {
        XCTAssertEqual(MoleOutputParser.extractBytes(from: "24.2 GB"),
                       Int64(24.2 * 1_000_000_000))
    }

    func testExtractBytes_MB() {
        XCTAssertEqual(MoleOutputParser.extractBytes(from: "512 MB"),
                       512_000_000)
    }

    func testExtractBytes_KB() {
        XCTAssertEqual(MoleOutputParser.extractBytes(from: "100 KB"),
                       100_000)
    }

    func testExtractBytes_B() {
        XCTAssertEqual(MoleOutputParser.extractBytes(from: "4096 B"),
                       4096)
    }

    func testExtractBytes_TB() {
        XCTAssertEqual(MoleOutputParser.extractBytes(from: "1.5 TB"),
                       Int64(1.5 * 1_000_000_000_000))
    }

    func testExtractBytes_commaDecimalSeparator() {
        // European locale uses comma — parser must handle both
        let result = MoleOutputParser.extractBytes(from: "1,5 GB")
        XCTAssertEqual(result, Int64(1.5 * 1_000_000_000))
    }

    func testExtractBytes_noMatch_returnsZero() {
        XCTAssertEqual(MoleOutputParser.extractBytes(from: "no size here"), 0)
    }

    func testExtractBytes_embeddedInLine() {
        // Typical mo output: path then size separated by spaces
        let line = "~/Developer/MyApp/node_modules  1.2 GB"
        XCTAssertGreaterThan(MoleOutputParser.extractBytes(from: line), 0)
    }
}

final class MoleOutputParserCleanDryRunTests: XCTestCase {

    // Non-empty output produces non-zero totalBytes and non-empty items.
    func testParseCleanDryRun_typicalOutput_hasItems() {
        let raw = """
        Caches: 2.4 GB
        Logs: 340 MB
        Browser data: 890 MB
        """
        let result = MoleOutputParser.parseCleanDryRun(raw)
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertGreaterThan(result.totalBytes, 0)
    }

    // Empty input falls back to non-zero totalBytes (so CleanViewModel shows .ready).
    func testParseCleanDryRun_emptyOutput_fallbackNonZero() {
        let result = MoleOutputParser.parseCleanDryRun("")
        XCTAssertGreaterThan(result.totalBytes, 0,
            "Empty output must fall back to non-zero so CleanViewModel shows ready state")
    }

    // ANSI-escaped output is parsed correctly after stripping.
    func testParseCleanDryRun_ansiOutput_parsedCorrectly() {
        let ansi = "\u{1B}[32mCaches: 1.0 GB\u{1B}[0m"
        let result = MoleOutputParser.parseCleanDryRun(ansi)
        XCTAssertFalse(result.items.isEmpty)
    }

    // Blank lines in output are ignored.
    func testParseCleanDryRun_blankLines_skipped() {
        let raw = "\nCaches: 500 MB\n\nLogs: 100 MB\n"
        let result = MoleOutputParser.parseCleanDryRun(raw)
        XCTAssertEqual(result.items.count, 2)
    }
}

final class MoleOutputParserPurgeTests: XCTestCase {

    // Standard purge output produces correctly named and sized artifacts.
    func testParsePurge_typicalOutput_producesArtifacts() {
        let raw = """
        ~/Developer/MyApp/node_modules  1.2 GB
        ~/Developer/BackendAPI/target  890 MB
        ~/Developer/iOSProject/DerivedData  2.1 GB
        """
        let artifacts = MoleOutputParser.parsePurge(raw)
        XCTAssertEqual(artifacts.count, 3)
        XCTAssertTrue(artifacts.contains { $0.name == "node_modules" })
        XCTAssertTrue(artifacts.contains { $0.name == "target" })
        XCTAssertTrue(artifacts.contains { $0.name == "DerivedData" })
    }

    // Each artifact has a non-zero size parsed from the size column.
    func testParsePurge_sizesAreNonZero() {
        let raw = "~/Developer/MyApp/node_modules  1.2 GB"
        let artifacts = MoleOutputParser.parsePurge(raw)
        XCTAssertFalse(artifacts.isEmpty)
        XCTAssertGreaterThan(artifacts[0].size, 0)
    }

    // Empty input produces empty array — no crash.
    func testParsePurge_emptyInput_returnsEmpty() {
        XCTAssertTrue(MoleOutputParser.parsePurge("").isEmpty)
    }

    // Blank-only input returns empty.
    func testParsePurge_blankLines_returnsEmpty() {
        XCTAssertTrue(MoleOutputParser.parsePurge("\n\n\n").isEmpty)
    }

    // Artifact name is derived from the last path component.
    func testParsePurge_artifactName_isLastPathComponent() {
        let raw = "/Users/alex/Projects/webapp/.next  340 MB"
        let artifacts = MoleOutputParser.parsePurge(raw)
        XCTAssertEqual(artifacts.first?.name, ".next")
    }

    // Path field is preserved correctly.
    func testParsePurge_pathIsPreserved() {
        let raw = "~/Developer/MyApp/node_modules  1.2 GB"
        let artifacts = MoleOutputParser.parsePurge(raw)
        XCTAssertEqual(artifacts.first?.path, "~/Developer/MyApp/node_modules")
    }
}

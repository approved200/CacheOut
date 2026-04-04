import XCTest
@testable import Cache_Out

// MARK: - SystemMonitor unit tests
// SystemMonitor wraps low-level sysctl/mach APIs. We can't mock kernel state,
// but we can verify the derived computations and display helpers that sit on top.

@MainActor
final class SystemMonitorComputationTests: XCTestCase {

    // healthScore must always be in [0, 100]
    func testHealthScore_isInRange_afterStart() async {
        let monitor = SystemMonitor()
        monitor.startMonitoring()
        // Give one timer tick time to fire
        try? await Task.sleep(nanoseconds: 250_000_000)
        monitor.stopMonitoring()

        XCTAssertGreaterThanOrEqual(monitor.healthScore, 0)
        XCTAssertLessThanOrEqual(monitor.healthScore, 100)
    }

    // memoryTotal must be greater than 0 on any real machine
    func testMemoryTotal_greaterThanZero() async {
        let monitor = SystemMonitor()
        monitor.startMonitoring()
        try? await Task.sleep(nanoseconds: 250_000_000)
        monitor.stopMonitoring()

        XCTAssertGreaterThan(monitor.memoryTotal, 0,
                             "memoryTotal must be > 0 on any real Mac")
    }

    // diskTotal must be greater than 0 on any real machine
    func testDiskTotal_greaterThanZero() async {
        let monitor = SystemMonitor()
        monitor.startMonitoring()
        try? await Task.sleep(nanoseconds: 250_000_000)
        monitor.stopMonitoring()

        XCTAssertGreaterThan(monitor.diskTotal, 0,
                             "diskTotal must be > 0 on any real Mac")
    }

    // memoryUsed must never exceed memoryTotal
    func testMemoryUsed_doesNotExceedTotal() async {
        let monitor = SystemMonitor()
        monitor.startMonitoring()
        try? await Task.sleep(nanoseconds: 250_000_000)
        monitor.stopMonitoring()

        if monitor.memoryTotal > 0 {
            XCTAssertLessThanOrEqual(monitor.memoryUsed, monitor.memoryTotal,
                                     "memoryUsed must never exceed memoryTotal")
        }
    }

    // diskUsed must never exceed diskTotal
    func testDiskUsed_doesNotExceedTotal() async {
        let monitor = SystemMonitor()
        monitor.startMonitoring()
        try? await Task.sleep(nanoseconds: 250_000_000)
        monitor.stopMonitoring()

        if monitor.diskTotal > 0 {
            XCTAssertLessThanOrEqual(monitor.diskUsed, monitor.diskTotal,
                                     "diskUsed must never exceed diskTotal")
        }
    }

    // cpuUsage must be in [0, 100]
    func testCpuUsage_isInValidRange() async {
        let monitor = SystemMonitor()
        monitor.startMonitoring()
        // Two ticks needed: first establishes prevUser/sys/idle, second computes delta
        try? await Task.sleep(nanoseconds: 500_000_000)
        monitor.stopMonitoring()

        XCTAssertGreaterThanOrEqual(monitor.cpuUsage, 0,
                                    "cpuUsage must be >= 0")
        XCTAssertLessThanOrEqual(monitor.cpuUsage, 100,
                                 "cpuUsage must be <= 100 — min() clamp must hold")
    }

    // stopMonitoring must be idempotent — calling it twice must not crash
    func testStopMonitoring_isIdempotent() {
        let monitor = SystemMonitor()
        monitor.startMonitoring()
        monitor.stopMonitoring()
        monitor.stopMonitoring()   // second call — must not throw or crash
    }
}

// MARK: - ProcessItem helpers
final class ProcessItemTests: XCTestCase {

    func testMemoryString_formatsBytesCorrectly() {
        let item = ProcessItem(pid: 1, name: "test", cpu: 0, memoryBytes: 100 * 1024 * 1024)
        // 100 MB — formatBytes should produce something containing "100" and "MB"
        let str = item.memoryString
        XCTAssertTrue(str.contains("100") && str.contains("MB"),
                      "Expected ~100 MB, got: \(str)")
    }

    func testMemoryString_zeroBytes() {
        let item = ProcessItem(pid: 1, name: "idle", cpu: 0, memoryBytes: 0)
        XCTAssertFalse(item.memoryString.isEmpty, "memoryString must not be empty for 0 bytes")
    }
}

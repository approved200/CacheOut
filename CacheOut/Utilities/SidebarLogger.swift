import Foundation

/// Debug-only file logger used to diagnose the macOS 26 NavigationSplitView
/// sidebar selection bug. All calls are compiled out in Release builds.
///
/// In Debug builds, logs are written to:
///   /tmp/cache_out_sidebar_debug.log
///
/// The file lives in /tmp (not the repo directory) so it is never accidentally
/// committed and is cleaned up automatically by macOS.
///
/// Usage: SidebarLogger.log("...") — no-op in Release, file write in Debug.
enum SidebarLogger {

#if DEBUG
    private static let logURL = URL(fileURLWithPath: "/tmp/cache_out_sidebar_debug.log")

    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let fh = try? FileHandle(forWritingTo: logURL) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            }
        } else {
            try? data.write(to: logURL)
        }
    }

    static func clear() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }

#else
    // Release build: all calls are compiled away — zero disk I/O, zero overhead.
    @inline(__always) static func log(_ message: String) {}
    @inline(__always) static func clear() {}
#endif
}

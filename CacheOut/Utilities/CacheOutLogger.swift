import Foundation
import OSLog

// MARK: — CacheOutLogger
// Provides structured OSLog subsystems for the app.
// Verbose (debug-level) messages are only emitted when the user has enabled
// "Debug logging" in Settings → Advanced. Standard error/fault messages are
// always emitted regardless of the toggle.
//
// Usage:
//   CacheOutLogger.clean.debug("Scanning \(path)")   // gated by debugLogging
//   CacheOutLogger.clean.error("Scan failed: \(err)") // always emitted
//
// In Console.app, filter by subsystem "com.cacheout.CacheOut" to see all logs.
// Toggle the Action menu → "Include Debug Messages" to see debug-level output.

enum CacheOutLogger {
    // One logger per functional domain — keeps Console.app filtering clean.
    static let clean    = Logger(subsystem: subsystem, category: "clean")
    static let purge    = Logger(subsystem: subsystem, category: "purge")
    static let uninstall = Logger(subsystem: subsystem, category: "uninstall")
    static let analyze  = Logger(subsystem: subsystem, category: "analyze")
    static let status   = Logger(subsystem: subsystem, category: "status")
    static let updater  = Logger(subsystem: subsystem, category: "updater")
    static let sparkle  = Logger(subsystem: subsystem, category: "sparkle")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")

    private static let subsystem = "com.cacheout.CacheOut"

    // MARK: — Debug gate
    // Call this before emitting verbose messages. Skips the log call entirely
    // when debug logging is disabled, keeping production log noise at zero.
    //   if CacheOutLogger.isDebugEnabled { CacheOutLogger.clean.debug("…") }
    // Or use the convenience helper on Logger itself (see extension below).
    static var isDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugLogging")
    }
}

// MARK: — Logger convenience extension
extension Logger {
    /// Emits a debug message only when the user has enabled debug logging.
    /// Accepts a plain String — the guard short-circuits before any I/O when
    /// debug logging is off, keeping production overhead at a single bool read.
    func debugIfEnabled(_ message: String) {
        guard CacheOutLogger.isDebugEnabled else { return }
        debug("\(message, privacy: .public)")
    }
}

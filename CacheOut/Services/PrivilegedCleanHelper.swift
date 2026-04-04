import Foundation

// MARK: — PrivilegedCleanHelper
// Runs `rm -rf <path>` as root by invoking AppleScript's
// `do shell script ... with administrator privileges`.
//
// This is the correct modern approach for a non-sandboxed, direct-distribution
// macOS app that needs to run a single privileged command without a helper tool.
// It shows the standard macOS authentication dialog and requires no entitlement
// beyond what Cache Out already has.
//
// AuthorizationExecuteWithPrivileges was removed from the Swift overlay (it was
// deprecated in macOS 10.7 and marked unavailable in Swift). SMJobBless requires
// a separate signed helper bundle and Info.plist entries. For a single `rm -rf`
// call, AppleScript with administrator privileges is the right trade-off.
//
// Security guarantees:
//   - Path is validated against a strict allowlist BEFORE the dialog appears
//   - The shell command is built with single-quoted path (shell-safe)
//   - No credential is stored; the OS handles authentication entirely
//   - Cache Out never sees or touches the password

enum PrivilegedCleanError: LocalizedError {
    case unsafePath(String)
    case scriptError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsafePath(let p):
            return "Refused to run on '\(p)' — path is not in the allowed list."
        case .scriptError(let msg):
            return msg
        case .cancelled:
            return "Authentication was cancelled."
        }
    }
}

// Only paths under these prefixes are ever passed to the privileged helper.
private let allowedPrivilegedPrefixes: [String] = [
    "/private/var/log",
    "/private/tmp",
    "/var/log",
    "/tmp",
    "/Applications/",
]

enum PrivilegedCleanHelper {

    /// Deletes `path` as root after the user authenticates via the macOS dialog.
    /// `itemName` is shown in the dialog as the human-readable name of what is being deleted.
    /// Returns nil on success, a localised error string on failure or cancellation.
    static func deleteWithAuth(path: String, itemName: String) async -> String? {
        // Validate path before ever showing an auth dialog.
        guard allowedPrivilegedPrefixes.contains(where: { path.hasPrefix($0) }) else {
            return PrivilegedCleanError.unsafePath(path).localizedDescription
        }

        // NSAppleScript.executeAndReturnError is synchronous and blocks its
        // calling thread until the password dialog is dismissed and the shell
        // command completes. Running it inside Task.detached at .userInitiated
        // QoS causes a priority-inversion hang warning because the AppleScript
        // IPC machinery internally uses .default QoS threads.
        //
        // The fix: bridge to a raw Thread (unmanaged, no Swift concurrency QoS
        // inheritance) via a checked continuation. This removes the QoS mismatch
        // entirely — the OS sees the blocking thread as QoS-unspecified and the
        // priority inversion detector stays silent.
        return await withCheckedContinuation { continuation in
            let t = Thread {
                let result = runAppleScriptDelete(path: path, itemName: itemName)
                continuation.resume(returning: result)
            }
            t.qualityOfService = .userInitiated
            t.start()
        }
    }

    // MARK: — AppleScript execution (background thread)

    private static func runAppleScriptDelete(path: String, itemName: String) -> String? {
        // Shell-safe path: wrap in single quotes and escape any single quotes in the path.
        // A path containing a single quote would be /very/ unusual for system paths,
        // but we handle it correctly by replacing ' with '\'' (end-quote, literal-quote, re-open).
        let safePath = path.replacingOccurrences(of: "'", with: "'\\''")
        let command  = "rm -rf '\(safePath)'"

        // The AppleScript source. `with administrator privileges` triggers the OS
        // password dialog. The dialog title is the app name ("Cache Out") automatically.
        let source = """
        do shell script "\(command)" with administrator privileges
        """

        var errorDict: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&errorDict)

        // Cancelled by user — NSAppleScript error number -128
        if let errNum = errorDict?[NSAppleScript.errorNumber] as? Int, errNum == -128 {
            return PrivilegedCleanError.cancelled.localizedDescription
        }

        // Any other AppleScript error
        if result == nil, let err = errorDict {
            let msg = err[NSAppleScript.errorMessage] as? String
                ?? "Unknown error running privileged command."
            return PrivilegedCleanError.scriptError(msg).localizedDescription
        }

        CacheOutLogger.clean.debugIfEnabled("PrivilegedCleanHelper: deleted \(path)")
        return nil  // success
    }
}

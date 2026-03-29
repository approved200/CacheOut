import Foundation
import AppKit

// MARK: — Models

enum StartupSource: String {
    case userLaunchAgent   = "Launch Agent"
    case systemLaunchAgent = "System Agent"
    case systemDaemon      = "System Daemon"
    case smAppService      = "Login Item"
}

struct StartupItem: Identifiable {
    let id                 = UUID()
    let label              : String
    let executablePath     : String
    let source             : StartupSource
    let plistPath          : String?   // nil for SMAppService items
    var isLoaded           : Bool
    var isEnabled          : Bool
    let associatedAppName  : String?
    let associatedAppIcon  : NSImage?
}

// MARK: — Scanner (runs off-actor)

enum StartupScanner {

    static func scan() -> [StartupItem] {
        var items: [StartupItem] = []
        let home = NSHomeDirectory()

        // Run `launchctl list` ONCE and parse all loaded labels into a Set.
        // Previously we called `launchctl list <label>` once per plist — N
        // serial subprocesses. One batch call is O(1) regardless of item count.
        let loadedLabels = batchLoadedLabels()

        // 1. User launch agents
        let userAgentsDir = (home as NSString)
            .appendingPathComponent("Library/LaunchAgents")
        items += scanPlistDir(userAgentsDir, source: .userLaunchAgent,
                              loadedLabels: loadedLabels)

        // 2. System-wide launch agents (read-only)
        items += scanPlistDir("/Library/LaunchAgents", source: .systemLaunchAgent,
                              loadedLabels: loadedLabels)

        // 3. System daemons (read-only)
        items += scanPlistDir("/Library/LaunchDaemons", source: .systemDaemon,
                              loadedLabels: loadedLabels)

        return items.sorted { a, b in
            // User items first, then by label
            if a.source == .userLaunchAgent && b.source != .userLaunchAgent { return true }
            if a.source != .userLaunchAgent && b.source == .userLaunchAgent { return false }
            return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
        }
    }

    // MARK: — Private helpers

    /// Runs `launchctl list` once and returns the set of all currently-loaded labels.
    /// Lines have the format "PID\tStatus\tLabel" — we only need the third field.
    /// Read pipe BEFORE waitUntilExit to avoid pipe-buffer deadlock on large output.
    private static func batchLoadedLabels() -> Set<String> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["list"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = Pipe()   // suppress stderr noise
        guard (try? proc.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return [] }
        var labels = Set<String>()
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 {
                labels.insert(parts[2].trimmingCharacters(in: .whitespaces))
            }
        }
        return labels
    }

    private static func scanPlistDir(_ dir: String, source: StartupSource,
                                     loadedLabels: Set<String>) -> [StartupItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var result: [StartupItem] = []
        for entry in entries where entry.hasSuffix(".plist") {
            let fullPath = (dir as NSString).appendingPathComponent(entry)
            guard let item = parsePlist(at: fullPath, source: source,
                                        loadedLabels: loadedLabels) else { continue }
            result.append(item)
        }
        return result
    }

    private static func parsePlist(at path: String, source: StartupSource,
                                   loadedLabels: Set<String>) -> StartupItem? {
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let label = dict["Label"] as? String
        else { return nil }

        // Extract executable path from ProgramArguments or Program
        let execPath: String
        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            execPath = first
        } else if let prog = dict["Program"] as? String {
            execPath = prog
        } else {
            execPath = ""
        }

        // O(1) set lookup — no subprocess per item
        let isLoaded  = loadedLabels.contains(label)
        let runAtLoad = dict["RunAtLoad"] as? Bool ?? false

        // Try to resolve the associated app from the executable path
        let (appName, appIcon) = resolveApp(executablePath: execPath)

        return StartupItem(
            label: label,
            executablePath: execPath,
            source: source,
            plistPath: path,
            isLoaded: isLoaded,
            isEnabled: runAtLoad,
            associatedAppName: appName,
            associatedAppIcon: appIcon
        )
    }

    private static func resolveApp(executablePath: String) -> (String?, NSImage?) {
        guard !executablePath.isEmpty else { return (nil, nil) }

        // Walk up the path looking for a .app bundle
        var path = executablePath as NSString
        for _ in 0..<8 {
            let candidate = path as String
            if candidate.hasSuffix(".app") {
                let name = (candidate as NSString).lastPathComponent
                    .replacingOccurrences(of: ".app", with: "")
                let icon = NSWorkspace.shared.icon(forFile: candidate)
                return (name, icon)
            }
            let parent = path.deletingLastPathComponent
            if parent == candidate { break }
            path = parent as NSString
        }

        // Fallback: try the executable's icon directly
        let icon = FileManager.default.fileExists(atPath: executablePath)
            ? NSWorkspace.shared.icon(forFile: executablePath)
            : nil
        let name = (executablePath as NSString).lastPathComponent
        return (name.isEmpty ? nil : name, icon)
    }
}

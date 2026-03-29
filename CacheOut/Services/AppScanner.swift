import AppKit
import Foundation

struct AppItem: Identifiable, Hashable {
    let id        = UUID()
    let name      : String
    let path      : String
    let version   : String
    let lastUsed  : Date
    let size      : Int64
    let isUnused  : Bool

    var appSize           : Int64 = 0
    var cacheSize         : Int64 = 0
    var supportSize       : Int64 = 0
    var prefsSize         : Int64 = 0
    var containerSize     : Int64 = 0
    var groupContainerSize: Int64 = 0
    var savedStateSize    : Int64 = 0
    var webKitSize        : Int64 = 0
    // Launch agent plists registered by this app in ~/Library/LaunchAgents/
    // Stored as (absolutePath, isCurrentlyLoaded) tuples.
    var launchAgents      : [(path: String, isLoaded: Bool)] = []

    /// Convenience: total byte size of all launch agent plists.
    var launchAgentSize: Int64 {
        let fm = FileManager.default
        return launchAgents.reduce(0) {
            $0 + (Int64((try? fm.attributesOfItem(atPath: $1.path)[.size] as? Int) ?? 0))
        }
    }

    static func == (l: AppItem, r: AppItem) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// AppScanner — enumerates /Applications concurrently via withTaskGroup.
// makeItem is nonisolated static so each app scans in parallel on the thread pool.
// Sendable because it holds no mutable state — all methods are static or pure.
final class AppScanner: Sendable {

    func scanApplications(unusedDays: Int = 90) async -> [AppItem] {
        let searchPaths: [String] = [
            "/Applications",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        ]

        // Collect all .app paths first (fast directory read)
        var appPaths: [String] = []
        let fm = FileManager.default
        for dir in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                appPaths.append((dir as NSString).appendingPathComponent(entry))
            }
        }

        // Scan all apps concurrently — each makeItem does 4 I/O ops in parallel
        var items: [AppItem] = []
        await withTaskGroup(of: AppItem?.self) { group in
            for path in appPaths {
                group.addTask {
                    AppScanner.makeItem(path: path, unusedDays: unusedDays)
                }
            }
            for await item in group {
                if let i = item { items.append(i) }
            }
        }

        items.sort { $0.size > $1.size }
        return items
    }

    // nonisolated static — safe for Task.detached and withTaskGroup
    nonisolated static func makeItem(path: String, unusedDays: Int = 90) -> AppItem? {
        let fm   = FileManager.default
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any]
        else { return nil }

        let bundleID = dict["CFBundleIdentifier"] as? String ?? ""
        // Skip true system apps that live in /System — they can't be uninstalled
        // and their data directories are managed by macOS.
        // Do NOT skip all com.apple.* apps: Final Cut Pro, Logic Pro, and Xcode
        // all use com.apple.* bundle IDs but live in /Applications/ and are user-removable.
        let isSystemApp = path.hasPrefix("/System/")
        if isSystemApp { return nil }

        let version: String = (dict["CFBundleShortVersionString"] as? String)
            ?? (dict["CFBundleVersion"] as? String) ?? "—"

        let lastUsed: Date = mdLastUsed(path: path) ?? Date.distantPast
        let appSize  = directorySize(path: path, fm: fm)
        guard appSize > 0 else { return nil }

        let cacheSize        = cacheBytes(bundleID: bundleID, fm: fm)
        let supportSize      = supportBytes(name: name, fm: fm)
        let prefsSize        = prefsBytes(bundleID: bundleID, fm: fm)
        let containerSize    = containerBytes(bundleID: bundleID, fm: fm)
        let groupContSize    = groupContainerBytes(bundleID: bundleID, fm: fm)
        let savedStateSize   = savedStateBytes(bundleID: bundleID, fm: fm)
        let webKitSize       = webKitBytes(bundleID: bundleID, fm: fm)
        let agents           = launchAgentEntries(bundleID: bundleID, fm: fm)
        let agentSize        = agents.reduce(0) {
            $0 + Int64((try? fm.attributesOfItem(atPath: $1.path)[.size] as? Int) ?? 0)
        }
        let totalSize        = appSize + cacheSize + supportSize + prefsSize
                             + containerSize + groupContSize + savedStateSize + webKitSize + agentSize

        let threshold: TimeInterval = Double(unusedDays) * 24 * 3600
        let isUnused = Date().timeIntervalSince(lastUsed) > threshold

        var item = AppItem(name: name, path: path, version: version,
                           lastUsed: lastUsed, size: totalSize, isUnused: isUnused)
        item.appSize           = appSize
        item.cacheSize         = cacheSize
        item.supportSize       = supportSize
        item.prefsSize         = prefsSize
        item.containerSize     = containerSize
        item.groupContainerSize = groupContSize
        item.savedStateSize    = savedStateSize
        item.webKitSize        = webKitSize
        item.launchAgents      = agents
        return item
    }

    // internal (not private) so AppDetailView can reuse it for group container measurement
    nonisolated static func directorySize(path: String, fm: FileManager) -> Int64 {
        guard let e = fm.enumerator(at: URL(fileURLWithPath: path),
              includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
              options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        while let url = e.nextObject() as? URL {
            let s = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                .totalFileAllocatedSize
                ?? (try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]))?
                .fileAllocatedSize ?? 0
            total += Int64(s)
        }
        return total
    }

    nonisolated private static func mdLastUsed(path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    nonisolated private static func cacheBytes(bundleID: String, fm: FileManager) -> Int64 {
        guard !bundleID.isEmpty else { return 0 }
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Caches/\(bundleID)")
        return directorySize(path: dir, fm: fm)
    }

    nonisolated private static func containerBytes(bundleID: String, fm: FileManager) -> Int64 {
        guard !bundleID.isEmpty else { return 0 }
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Containers/\(bundleID)")
        return directorySize(path: dir, fm: fm)
    }

    nonisolated private static func groupContainerBytes(bundleID: String, fm: FileManager) -> Int64 {
        guard !bundleID.isEmpty else { return 0 }
        // Group containers use a prefix match — enumerate and sum matches
        let base = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Group Containers")
        guard let entries = try? fm.contentsOfDirectory(atPath: base) else { return 0 }
        // Match entries that contain the bundle ID's domain (e.g. "group.com.vendor.app")
        let domain = bundleID.components(separatedBy: ".").prefix(3).joined(separator: ".")
        return entries
            .filter { $0.contains(domain) }
            .reduce(0) { $0 + directorySize(path: (base as NSString).appendingPathComponent($1), fm: fm) }
    }

    nonisolated private static func savedStateBytes(bundleID: String, fm: FileManager) -> Int64 {
        guard !bundleID.isEmpty else { return 0 }
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Saved Application State/\(bundleID).savedState")
        return directorySize(path: dir, fm: fm)
    }

    nonisolated private static func webKitBytes(bundleID: String, fm: FileManager) -> Int64 {
        guard !bundleID.isEmpty else { return 0 }
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/WebKit/\(bundleID)")
        return directorySize(path: dir, fm: fm)
    }

    nonisolated private static func supportBytes(name: String, fm: FileManager) -> Int64 {
        // These Apple first-party app support dirs should not be touched —
        // either they're OS-managed or the app isn't user-removable.
        let blocked: Set<String> = [
            "Photos","Music","TV","Podcasts","News","Mail",
            "Contacts","Calendar","Reminders","Notes","Safari",
            "Messages","FaceTime","Maps","Wallet","Finder",
            "SystemPreferences","SystemSettings"
        ]
        guard !blocked.contains(name) else { return 0 }
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/\(name)")
        return directorySize(path: dir, fm: fm)
    }

    nonisolated private static func prefsBytes(bundleID: String, fm: FileManager) -> Int64 {
        let pref = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Preferences/\(bundleID).plist")
        return (try? fm.attributesOfItem(atPath: pref)[.size] as? Int64) ?? 0
    }

    /// Finds launch agent plists in ~/Library/LaunchAgents/ whose filename
    /// contains the app's bundle ID (the standard macOS naming convention:
    /// e.g. "com.vendor.app.plist" or "com.vendor.app.helper.plist").
    /// Also checks whether launchctl currently has the agent loaded, so the
    /// UI can warn the user that a restart may be needed after removal.
    nonisolated private static func launchAgentEntries(
        bundleID: String, fm: FileManager
    ) -> [(path: String, isLoaded: Bool)] {
        guard !bundleID.isEmpty, !bundleID.hasPrefix("com.apple.") else { return [] }

        let agentsDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/LaunchAgents")
        guard let entries = try? fm.contentsOfDirectory(atPath: agentsDir) else { return [] }

        // Match any plist whose base name starts with the bundle ID.
        // This catches "com.vendor.app.plist" and "com.vendor.app.agent.plist".
        let matches = entries.filter {
            $0.hasSuffix(".plist") && $0.hasPrefix(bundleID)
        }
        guard !matches.isEmpty else { return [] }

        // Ask launchctl whether each agent is loaded (one fast subprocess call total).
        // `launchctl list` returns lines like: "PID\tStatus\tLabel"
        // We only care about the third column (Label), so we parse it once.
        let loadedLabels = loadedLaunchAgentLabels()

        return matches.map { filename in
            let path  = (agentsDir as NSString).appendingPathComponent(filename)
            let label = (filename as NSString).deletingPathExtension
            return (path: path, isLoaded: loadedLabels.contains(label))
        }
    }

    /// Runs `launchctl list` once and returns the set of currently-loaded agent labels.
    /// Kept nonisolated/static so it can run freely on any thread inside withTaskGroup.
    nonisolated private static func loadedLaunchAgentLabels() -> Set<String> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["list"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = Pipe()   // suppress stderr
        guard (try? proc.run()) != nil else { return [] }
        // Read BEFORE waitUntilExit to avoid pipe-buffer deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return [] }
        // Lines: "PID\tStatus\tLabel" — label is the third tab-delimited field
        var labels = Set<String>()
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 { labels.insert(parts[2].trimmingCharacters(in: .whitespaces)) }
        }
        return labels
    }
}

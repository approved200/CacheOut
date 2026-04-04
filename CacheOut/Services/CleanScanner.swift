import Foundation

// MARK: — CleanScanner
// Pure filesystem scanner — no SwiftUI, no @MainActor, no ObservableObject.
// Extracted from CleanViewModel so the ViewModel stays thin (state + actions)
// and this type stays testable in isolation.
//
// All methods are nonisolated static — safe for Task.detached and withTaskGroup.
enum CleanScanner {

    // MARK: — Pre-computed expanded paths (Sendable value type, safe for Task.detached)
    struct ScanPaths: Sendable {
        let derivedData, gradleCache, cocoapods, npmCache, yarnCache: String
        let pipCache, cargoCache, goModCache: String
        let chrome, safari, firefox, edge: String
        let logs, tmp, crashReports: String
        let docker, slack, spotify, trash: String
        let iosBackup, iosUpdates: String

        init(home: String) {
            func e(_ p: String) -> String { p.hasPrefix("~/") ? home + p.dropFirst(1) : p }
            derivedData  = e("~/Library/Developer/Xcode/DerivedData")
            gradleCache  = e("~/.gradle/caches")
            cocoapods    = e("~/Library/Caches/CocoaPods")
            npmCache     = e("~/.npm")
            yarnCache    = e("~/.yarn/cache")
            pipCache     = e("~/Library/Caches/pip")
            cargoCache   = e("~/.cargo/registry/cache")
            goModCache   = e("~/go/pkg/mod/cache")
            chrome       = e("~/Library/Caches/Google/Chrome")
            safari       = e("~/Library/Caches/com.apple.Safari")
            firefox      = e("~/Library/Caches/Firefox")
            edge         = e("~/Library/Caches/com.microsoft.edgemac")
            logs         = "/private/var/log"
            tmp          = "/private/tmp"
            crashReports = e("~/Library/Logs/DiagnosticReports")
            docker       = e("~/Library/Containers/com.docker.docker/Data")
            slack        = e("~/Library/Application Support/Slack/Cache")
            spotify      = e("~/Library/Caches/com.spotify.client")
            trash        = e("~/.Trash")
            iosBackup    = e("~/Library/Application Support/MobileSync/Backup")
            iosUpdates   = e("~/Library/iTunes/iPhone Software Updates")
        }
    }

    // MARK: — node_modules discovery
    // Mirrors PurgeViewModel.scanRoots logic — checks common dev folder names
    // and one level inside ~/Documents and ~/Desktop.
    static func countNodeModules(home: String) async -> (count: Int, size: Int64) {
        let devNames = ["Projects","Developer","dev","GitHub","github",
                        "code","src","work","repos","Repos","Code","Dev"]
        let fm = FileManager.default
        var roots: [String] = []

        for name in devNames {
            let path = (home as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: path) { roots.append(path) }
        }
        for container in ["Documents", "Desktop"] {
            let containerPath = (home as NSString).appendingPathComponent(container)
            guard let entries = try? fm.contentsOfDirectory(atPath: containerPath) else { continue }
            for entry in entries where devNames.contains(entry) {
                let path = (containerPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    if !roots.contains(path) { roots.append(path) }
                }
            }
        }
        if roots.isEmpty {
            for name in ["Documents", "Desktop"] {
                let path = (home as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: path) { roots.append(path) }
            }
        }

        var count = 0; var total: Int64 = 0
        for root in roots {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: root),
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]) else { continue }
            let urls = e.compactMap { $0 as? URL }
            for url in urls {
                if url.lastPathComponent == "node_modules",
                   (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    count += 1
                    total += FileSystemUtils.allocatedSize(path: url.path)
                    e.skipDescendants()
                }
            }
        }
        return (count, total)
    }

    // MARK: — Dynamic app cache discovery
    // Enumerates ~/Library/Caches/ for subdirectories not already covered by
    // hardcoded entries. Filters to >10 MB, caps at 10 results sorted by size desc.
    static func discoverDynamicAppCaches(home: String, alreadyCovered: [String]) -> [SubItem] {
        let fm = FileManager.default
        let cachesDir = (home as NSString).appendingPathComponent("Library/Caches")

        let coveredPaths = Set(alreadyCovered.map { ($0 as NSString).standardizingPath })
        let skipPrefixes = ["com.apple.", "org.mozilla.", "com.google.Chrome",
                            "com.microsoft.edgemac", "com.spotify."]

        guard let entries = try? fm.contentsOfDirectory(atPath: cachesDir) else { return [] }

        let minSize: Int64 = 10 * 1024 * 1024
        let cap = 10
        var candidates: [(name: String, path: String, size: Int64)] = []

        for entry in entries {
            if skipPrefixes.contains(where: { entry.hasPrefix($0) }) { continue }
            let fullPath = (cachesDir as NSString).appendingPathComponent(entry)
            let normPath = (fullPath as NSString).standardizingPath
            if coveredPaths.contains(normPath) { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let sz = FileSystemUtils.allocatedSize(path: fullPath)
            guard sz >= minSize else { continue }

            let displayName = resolveAppDisplayName(bundleID: entry, home: home, fm: fm)
            candidates.append((name: "\(displayName) cache", path: fullPath, size: sz))
        }

        return candidates
            .sorted { $0.size > $1.size }
            .prefix(cap)
            .map { SubItem(name: $0.name, path: $0.path, size: $0.size) }
    }

    // Looks up a human-readable name for a bundle ID by scanning installed apps.
    private static func resolveAppDisplayName(bundleID: String, home: String,
                                               fm: FileManager) -> String {
        let searchDirs = ["/Applications", (home as NSString).appendingPathComponent("Applications")]
        for dir in searchDirs {
            guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let plist = "\(dir)/\(app)/Contents/Info.plist"
                guard let dict = NSDictionary(contentsOfFile: plist) as? [String: Any],
                      let bid = dict["CFBundleIdentifier"] as? String,
                      bid == bundleID,
                      let name = dict["CFBundleDisplayName"] as? String
                              ?? dict["CFBundleName"] as? String
                else { continue }
                return name
            }
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    // MARK: — Trash item count
    static func trashItemCount(_ path: String) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.count ?? 0
    }
}

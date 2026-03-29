import Foundation
import SwiftUI
import UserNotifications
import OSLog

enum CleanState: Equatable {
    case idle
    case scanning
    case refreshing       // has data, silently re-scanning in background
    case ready
    case cleaning(progress: Double)
    case complete
    case systemClean
    case permissionDenied // Full Disk Access not granted
}

struct CategoryItem: Identifiable {
    let id = UUID()
    var category: CleanCategory
    var size: Int64
    var subItems: [SubItem]
    var isSelected: Bool = true
    var isExpanded: Bool = false
}

struct SubItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
}

@MainActor
class CleanViewModel: ObservableObject {
    @Published var state: CleanState = .idle
    @Published var categoriesData: [CategoryItem] = []
    @Published var cleanedSize: Int64 = 0
    @Published var lastScanned: Date? = nil
    /// Number of sub-items suppressed by the whitelist during the last scan.
    /// Used by CleanView to show the "N items hidden by whitelist" footer chip.
    @Published var whitelistSuppressedCount: Int = 0
    /// Errors from the last clean pass — items that could not be moved to Trash.
    /// Displayed as a banner in CleanView after cleaning completes.
    @Published var cleanErrors: [String] = []

    var totalSelectedSize: Int64 {
        categoriesData.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }
    var selectedCategories: Set<CleanCategory> {
        Set(categoriesData.filter(\.isSelected).map(\.category))
    }

    // How stale before a background refresh triggers (5 minutes)
    private let staleDuration: TimeInterval = 5 * 60

    // MARK: — Smart scan entry point
    // If we already have data and it's fresh: do nothing.
    // If we have data but it's stale: show old data + refresh silently.
    // If we have no data: full blocking scan.
    func scanIfNeeded() async {
        switch state {
        case .scanning, .refreshing, .cleaning: return   // already working
        case .ready, .systemClean:
            guard let last = lastScanned,
                  Date().timeIntervalSince(last) > staleDuration else { return }
            await backgroundRefresh()
        case .idle, .complete, .permissionDenied:
            // .permissionDenied: user may have granted FDA since last attempt —
            // always retry so ⌘R works after they return from System Settings.
            await startScan()
        }
    }

    // MARK: — Force scan (Cmd+R or "Scan again" button)
    func startScan() async {
        // POLISH-01: guard against double-scan race when "Scan again" is tapped rapidly.
        guard state != .scanning else { return }
        CacheOutLogger.clean.debugIfEnabled("startScan() triggered")
        whitelistSuppressedCount = 0
        state = .scanning
        await performScan()
    }

    // MARK: — Silent background refresh — keeps existing data visible
    private func backgroundRefresh() async {
        state = .refreshing
        await performScan()
    }

    // MARK: — Core scan work — all paths measured concurrently via async let
    private func performScan() async {
        let home = NSHomeDirectory()
        let p = ScanPaths(home: home)

        // TCC permission probe — use the FileManager URL API so the read actually
        // exercises the TCC gate rather than just checking whether the path exists.
        // contentsOfDirectory(atPath:) can succeed on the path string alone even
        // when TCC blocks the real directory read; url(for:in:) goes through the
        // same code path the scanner uses and returns nil when FDA is denied.
        let fm = FileManager.default
        let libraryURL = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
        let cachesURL  = libraryURL?.appendingPathComponent("Caches")
        let hasAccess  = cachesURL.flatMap {
            try? fm.contentsOfDirectory(at: $0,
                                        includingPropertiesForKeys: nil,
                                        options: .skipsHiddenFiles)
        } != nil
        guard hasAccess else {
            state = .permissionDenied
            return
        }

        // Read whitelist once up-front (main actor is fine here).
        // Normalise every stored entry to its absolute path so that tilde-prefixed
        // entries ("~/Library/Caches/pip") added programmatically and absolute paths
        // ("/Users/alice/Library/Caches/pip") added via NSOpenPanel both resolve to
        // the same key. Without this, NSOpenPanel-sourced paths never matched the
        // tilde-keyed sub-item paths and the whitelist was silently bypassed.
        let whitelistRaw = UserDefaults.standard.string(forKey: "cleanWhitelist") ?? ""
        let whitelist = Set(
            whitelistRaw.split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
                .map { NSString(string: $0).expandingTildeInPath }
        )

        // Launch all filesystem measurements concurrently
        async let _derivedData = Task.detached(priority: .userInitiated) { self.dirSize(p.derivedData) }.value
        async let _gradleCache = Task.detached(priority: .userInitiated) { self.dirSize(p.gradleCache) }.value
        async let _cocoapods   = Task.detached(priority: .userInitiated) { self.dirSize(p.cocoapods) }.value
        async let _npmCache    = Task.detached(priority: .userInitiated) { self.dirSize(p.npmCache) }.value
        async let _yarnCache   = Task.detached(priority: .userInitiated) { self.dirSize(p.yarnCache) }.value
        async let _pipCache    = Task.detached(priority: .userInitiated) { self.dirSize(p.pipCache) }.value
        async let _cargoCache  = Task.detached(priority: .userInitiated) { self.dirSize(p.cargoCache) }.value
        async let _goModCache  = Task.detached(priority: .userInitiated) { self.dirSize(p.goModCache) }.value
        async let _nodeResult  = countNodeModules(home: home)
        async let _chromeSz    = Task.detached(priority: .userInitiated) { self.dirSize(p.chrome) }.value
        async let _safariSz    = Task.detached(priority: .userInitiated) { self.dirSize(p.safari) }.value
        async let _firefoxSz   = Task.detached(priority: .userInitiated) { self.dirSize(p.firefox) }.value
        async let _edgeSz      = Task.detached(priority: .userInitiated) { self.dirSize(p.edge) }.value
        async let _logsSz      = Task.detached(priority: .userInitiated) { self.dirSize(p.logs) }.value
        async let _tmpSz       = Task.detached(priority: .userInitiated) { self.dirSize(p.tmp) }.value
        async let _crashSz     = Task.detached(priority: .userInitiated) { self.dirSize(p.crashReports) }.value
        async let _dockerSz    = Task.detached(priority: .userInitiated) { self.dirSize(p.docker) }.value
        async let _slackSz     = Task.detached(priority: .userInitiated) { self.dirSize(p.slack) }.value
        async let _spotifySz   = Task.detached(priority: .userInitiated) { self.dirSize(p.spotify) }.value
        async let _trashSz     = Task.detached(priority: .userInitiated) { self.dirSize(p.trash) }.value
        async let _trashCount  = Task.detached(priority: .userInitiated) { self.trashItemCount(p.trash) }.value
        async let _iosBackupSz = Task.detached(priority: .userInitiated) { self.dirSize(p.iosBackup) }.value
        async let _iosUpdateSz = Task.detached(priority: .userInitiated) { self.dirSize(p.iosUpdates) }.value
        // FEATURE-04: discover additional app caches dynamically
        async let _dynamicAppSubs = Task.detached(priority: .userInitiated) {
            self.discoverDynamicAppCaches(
                home: home,
                alreadyCovered: [p.docker, p.slack, p.spotify]
            )
        }.value

        // Await all — total time = slowest single path, not sum
        let (derivedData, gradleCache, cocoapods, npmCache, yarnCache,
             pipCache, cargoCache, goModCache, nodeResult,
             chromeSz, safariSz, firefoxSz, edgeSz,
             logsSz, tmpSz, crashSz,
             dockerSz, slackSz, spotifySz,
             trashSz, trashCount, dynamicAppSubs,
             iosBackupSz, iosUpdateSz) = await (
            _derivedData, _gradleCache, _cocoapods, _npmCache, _yarnCache,
            _pipCache, _cargoCache, _goModCache, _nodeResult,
            _chromeSz, _safariSz, _firefoxSz, _edgeSz,
            _logsSz, _tmpSz, _crashSz,
            _dockerSz, _slackSz, _spotifySz,
            _trashSz, _trashCount, _dynamicAppSubs,
            _iosBackupSz, _iosUpdateSz
        )
        let (nodeCount, nodeSize) = nodeResult

        // Helper: suppress a SubItem if its path is in the whitelist.
        // Both sides are normalised to absolute paths (whitelist above, path here).
        func allowed(_ path: String) -> Bool {
            !whitelist.contains(NSString(string: path).expandingTildeInPath)
        }

        // Build sub-item arrays twice — once unfiltered (to count suppressed items),
        // once filtered (what the user actually sees). Defined as closures so we
        // don't duplicate the path/size logic below.
        let allDevSubs: [SubItem] = [
            SubItem(name: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData", size: derivedData),
            SubItem(name: "node_modules (\(nodeCount) projects)", path: "~/Projects/**/node_modules", size: nodeSize),
            SubItem(name: "Gradle cache",      path: "~/.gradle/caches",           size: gradleCache),
            SubItem(name: "CocoaPods cache",   path: "~/Library/Caches/CocoaPods", size: cocoapods),
            SubItem(name: "npm cache",         path: "~/.npm",                     size: npmCache),
            SubItem(name: "yarn cache",        path: "~/.yarn/cache",              size: yarnCache),
            SubItem(name: "pip cache",         path: "~/Library/Caches/pip",       size: pipCache),
            SubItem(name: "Cargo registry",    path: "~/.cargo/registry/cache",    size: cargoCache),
            SubItem(name: "Go module cache",   path: "~/go/pkg/mod/cache",         size: goModCache),
        ].filter { $0.size > 0 }
        let allBrowserSubs: [SubItem] = [
            SubItem(name: "Chrome cache",  path: "~/Library/Caches/Google/Chrome",         size: chromeSz),
            SubItem(name: "Safari cache",  path: "~/Library/Caches/com.apple.Safari",      size: safariSz),
            SubItem(name: "Firefox cache", path: "~/Library/Caches/Firefox",               size: firefoxSz),
            SubItem(name: "Edge cache",    path: "~/Library/Caches/com.microsoft.edgemac", size: edgeSz),
        ].filter { $0.size > 0 }
        let allSystemSubs: [SubItem] = [
            SubItem(name: "System logs",      path: "/private/var/log",                        size: logsSz),
            SubItem(name: "Temp files",       path: "/private/tmp",                            size: tmpSz),
            SubItem(name: "Crash reports",    path: "~/Library/Logs/DiagnosticReports",        size: crashSz),
            SubItem(name: "iOS backups",      path: "~/Library/Application Support/MobileSync/Backup", size: iosBackupSz),
            SubItem(name: "iOS device updates", path: "~/Library/iTunes/iPhone Software Updates", size: iosUpdateSz),
        ].filter { $0.size > 0 }
        let allAppSubs: [SubItem] = ([
            SubItem(name: "Docker data",   path: "~/Library/Containers/com.docker.docker/Data", size: dockerSz),
            SubItem(name: "Slack cache",   path: "~/Library/Application Support/Slack/Cache",   size: slackSz),
            SubItem(name: "Spotify cache", path: "~/Library/Caches/com.spotify.client",         size: spotifySz),
        ] + dynamicAppSubs).filter { $0.size > 0 }
        let allTrashSubs: [SubItem] = trashSz > 0 ? [
            SubItem(name: "Trash contents (\(trashCount) items)", path: "~/.Trash", size: trashSz)
        ] : []

        // Count how many sub-items the whitelist suppresses this scan
        let allSubs = allDevSubs + allBrowserSubs + allSystemSubs + allAppSubs + allTrashSubs
        whitelistSuppressedCount = allSubs.filter { !allowed($0.path) }.count

        // BUG-03 fix: compute category sizes from the FILTERED sub-items only, so the
        // hero number and segmented bar reflect what the user will actually clean —
        // not the raw totals that include whitelist-suppressed items.
        let devSubs     = allDevSubs.filter     { allowed($0.path) }
        let browserSubs = allBrowserSubs.filter { allowed($0.path) }
        let systemSubs  = allSystemSubs.filter  { allowed($0.path) }
        let appSubs     = allAppSubs.filter     { allowed($0.path) }
        let trashSubs   = allTrashSubs.filter   { allowed($0.path) }

        let newData: [CategoryItem] = [
            CategoryItem(category: .dev,
                size: devSubs.reduce(0) { $0 + $1.size },
                subItems: devSubs),
            CategoryItem(category: .browser,
                size: browserSubs.reduce(0) { $0 + $1.size },
                subItems: browserSubs),
            CategoryItem(category: .system,
                size: systemSubs.reduce(0) { $0 + $1.size },
                subItems: systemSubs),
            CategoryItem(category: .app,
                size: appSubs.reduce(0) { $0 + $1.size },
                subItems: appSubs),
            CategoryItem(category: .trash,
                size: trashSubs.reduce(0) { $0 + $1.size },
                subItems: trashSubs),
        ].filter { $0.size > 0 && !$0.subItems.isEmpty }

        // Preserve user's checkbox selections across refreshes
        let prevSelected = Set(categoriesData.filter(\.isSelected).map(\.category))
        categoriesData = newData.map { item in
            var m = item
            // Keep deselected state if user unchecked it before; default = selected
            m.isSelected = prevSelected.isEmpty ? true : prevSelected.contains(item.category)
            return m
        }

        lastScanned = Date()
        let total = categoriesData.reduce(0) { $0 + $1.size }
        CacheOutLogger.clean.debugIfEnabled("Scan complete — \(categoriesData.count) categories, \(total) bytes reclaimable")
        state = total < 1_000_000 ? .systemClean : .ready
    }

    // MARK: — Clean
    func startCleaning() async {
        cleanedSize = totalSelectedSize
        cleanErrors = []
        CacheOutLogger.clean.debugIfEnabled("startCleaning() — \(selectedCategories.count) categories, \(cleanedSize) bytes, dryRun=\(UserDefaults.standard.bool(forKey: "dryRunMode"))")
        state = .cleaning(progress: 0)
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let dryRun = UserDefaults.standard.bool(forKey: "dryRunMode")
        func expand(_ p: String) -> String { p.hasPrefix("~/") ? home + p.dropFirst(1) : p }

        var errors: [String] = []
        let selectedItems = categoriesData.filter(\.isSelected).flatMap(\.subItems)
        for (idx, item) in selectedItems.enumerated() {
            if Task.isCancelled { break }
            let url = URL(fileURLWithPath: expand(item.path))
            if !dryRun && fm.fileExists(atPath: url.path) {
                do {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    errors.append("\(item.name): \(error.localizedDescription)")
                    CacheOutLogger.clean.error("trashItem failed for \(item.path): \(error.localizedDescription)")
                }
            }
            let progress = Double(idx + 1) / Double(selectedItems.count)
            state = .cleaning(progress: progress)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if !dryRun && selectedCategories.contains(.trash) {
            try? fm.removeItem(at: URL(fileURLWithPath: expand("~/.Trash")))
            try? fm.createDirectory(atPath: expand("~/.Trash"), withIntermediateDirectories: true)
        }
        cleanErrors = errors
        lastScanned = nil
        state = .complete
        NotificationCenter.default.post(name: .diskFreed, object: nil)
        postCleanNotification(dryRun: dryRun)
    }

    private func postCleanNotification(dryRun: Bool = false) {
        guard UserDefaults.standard.bool(forKey: "notifyOnComplete") else { return }
        let content = UNMutableNotificationContent()
        content.title = dryRun ? "Dry run complete" : "Clean complete"
        content.body  = dryRun
            ? "\(formatBytes(cleanedSize)) would have been moved to Trash (dry run)."
            : "\(formatBytes(cleanedSize)) moved to Trash."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "clean-complete",
                                  content: content, trigger: nil))
    }

    func toggleSelection(for category: CleanCategory) {
        guard let i = categoriesData.firstIndex(where: { $0.category == category }) else { return }
        categoriesData[i].isSelected.toggle()
        objectWillChange.send()
    }

    func reset() { categoriesData = []; state = .idle; lastScanned = nil }

    // MARK: — Filesystem helpers
    // NOTE: .skipsHiddenFiles is intentionally NOT set — many caches (.npm, .gradle,
    // .cargo, etc.) live inside hidden dot-directories. Skipping them understates sizes.
    // .skipsPackageDescendants is kept so we don't recurse into .app bundles.
    nonisolated func dirSize(_ path: String) -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: URL(fileURLWithPath: path),
              includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
              options: [.skipsPackageDescendants]) else { return 0 }
        var total: Int64 = 0
        while let url = e.nextObject() as? URL {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    nonisolated func trashItemCount(_ path: String) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.count ?? 0
    }

    nonisolated func countNodeModules(home: String) async -> (count: Int, size: Int64) {
        // Mirror PurgeViewModel.defaultScanRoots() — check ~ directly AND
        // one level inside ~/Documents and ~/Desktop for dev folder names.
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
                    count += 1; total += dirSize(url.path); e.skipDescendants()
                }
            }
        }
        return (count, total)
    }

    // MARK: — FEATURE-04: Dynamic app cache discovery
    // Enumerates ~/Library/Caches/ for subdirectories not already covered by
    // hardcoded entries, resolves their app name from installed bundles,
    // filters to >10 MB, caps at 10 results sorted by size descending.
    nonisolated func discoverDynamicAppCaches(home: String, alreadyCovered: [String]) -> [SubItem] {
        let fm = FileManager.default
        let cachesDir = (home as NSString).appendingPathComponent("Library/Caches")

        // Build a set of already-covered cache paths (normalised, no trailing slash)
        let coveredPaths = Set(alreadyCovered.map {
            ($0 as NSString).standardizingPath
        })
        // Also skip com.apple.* system caches and known browser caches
        let skipPrefixes = ["com.apple.", "org.mozilla.", "com.google.Chrome",
                            "com.microsoft.edgemac", "com.spotify."]

        guard let entries = try? fm.contentsOfDirectory(atPath: cachesDir) else { return [] }

        let minSize: Int64 = 10 * 1024 * 1024  // 10 MB
        let cap = 10

        var candidates: [(name: String, path: String, size: Int64)] = []

        for entry in entries {
            // Skip known prefixes
            if skipPrefixes.contains(where: { entry.hasPrefix($0) }) { continue }

            let fullPath = (cachesDir as NSString).appendingPathComponent(entry)
            let normPath = (fullPath as NSString).standardizingPath

            // Skip already covered paths
            if coveredPaths.contains(normPath) { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue
            else { continue }

            let sz = dirSize(fullPath)
            guard sz >= minSize else { continue }

            // Resolve a friendly display name from the bundle identifier
            let displayName = resolveAppDisplayName(bundleID: entry, home: home, fm: fm)
            candidates.append((name: "\(displayName) cache", path: fullPath, size: sz))
        }

        return candidates
            .sorted { $0.size > $1.size }
            .prefix(cap)
            .map { SubItem(name: $0.name, path: $0.path, size: $0.size) }
    }

    // Looks up a human-readable name for a bundle ID by scanning installed apps.
    // Falls back to the raw bundle ID if no match is found.
    nonisolated private func resolveAppDisplayName(bundleID: String, home: String,
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
        // Strip bundle-ID suffix noise: "com.vendor.AppName" → "AppName"
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }
}  // end CleanViewModel

// MARK: — Pre-computed expanded paths (Sendable value type, safe for Task.detached)
private struct ScanPaths: Sendable {
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

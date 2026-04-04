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
    /// True for system-owned paths under /private that cannot be trashed
    /// by a user process even with Full Disk Access.
    var isReadOnly: Bool = false
}

@MainActor
class CleanViewModel: ObservableObject {
    @Published var state: CleanState = .idle
    @Published var categoriesData: [CategoryItem] = []
    @Published var cleanedSize: Int64 = 0
    @Published var lastScanned: Date? = nil
    @Published var whitelistSuppressedCount: Int = 0
    @Published var cleanErrors: [String] = []

    // MARK: — Undo: tracks original→trash-destination pairs from the last clean.
    // Populated by startCleaning() using the resultingItemURL from trashItem(at:resultingItemURL:).
    // Cleared at the start of every new clean so it only reflects the most recent operation.
    // Each tuple is (originalPath, pathInTrash) so we can move the item back exactly.
    @Published var lastTrashedItems: [(original: URL, inTrash: URL)] = []

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
        let p = CleanScanner.ScanPaths(home: home)

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
        async let _nodeResult  = CleanScanner.countNodeModules(home: home)
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
        async let _trashCount  = Task.detached(priority: .userInitiated) { CleanScanner.trashItemCount(p.trash) }.value
        async let _iosBackupSz = Task.detached(priority: .userInitiated) { self.dirSize(p.iosBackup) }.value
        async let _iosUpdateSz = Task.detached(priority: .userInitiated) { self.dirSize(p.iosUpdates) }.value
        async let _dynamicAppSubs = Task.detached(priority: .userInitiated) {
            CleanScanner.discoverDynamicAppCaches(
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
            SubItem(name: "System logs",        path: "/private/var/log",                        size: logsSz,      isReadOnly: true),
            SubItem(name: "Temp files",         path: "/private/tmp",                            size: tmpSz,       isReadOnly: true),
            SubItem(name: "Crash reports",      path: "~/Library/Logs/DiagnosticReports",        size: crashSz),
            SubItem(name: "iOS backups",        path: "~/Library/Application Support/MobileSync/Backup", size: iosBackupSz),
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
        lastTrashedItems = []   // reset undo list for this clean pass
        CacheOutLogger.clean.debugIfEnabled("startCleaning() — \(selectedCategories.count) categories, \(cleanedSize) bytes, dryRun=\(UserDefaults.standard.bool(forKey: "dryRunMode"))")
        state = .cleaning(progress: 0)
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let dryRun = UserDefaults.standard.bool(forKey: "dryRunMode")
        func expand(_ p: String) -> String { p.hasPrefix("~/") ? home + p.dropFirst(1) : p }

        var errors: [String] = []
        var trashed: [(original: URL, inTrash: URL)] = []

        let selectedItems = categoriesData.filter(\.isSelected).flatMap(\.subItems)
        for (idx, item) in selectedItems.enumerated() {
            if Task.isCancelled { break }
            let expandedPath = expand(item.path)
            let url = URL(fileURLWithPath: expandedPath)

            if !dryRun && fm.fileExists(atPath: url.path) {
                // System-owned paths under /private cannot be trashed by a user
                // process — even with Full Disk Access, macOS only grants read
                // permission to these paths. Skip them with an honest message
                // rather than surfacing a cryptic permission error.
                if isSystemOwnedPath(expandedPath) {
                    errors.append("\(item.name): owned by macOS — cannot be moved to Trash by a user app. Use Disk Utility or Terminal with sudo to clear this path.")
                    CacheOutLogger.clean.debugIfEnabled("Skipped system-owned path: \(expandedPath)")
                } else {
                    do {
                        var resultURL: NSURL? = nil
                        try fm.trashItem(at: url, resultingItemURL: &resultURL)
                        if let dest = resultURL as URL? {
                            trashed.append((original: url, inTrash: dest))
                        }
                    } catch {
                        errors.append("\(item.name): \(error.localizedDescription)")
                        CacheOutLogger.clean.error("trashItem failed for \(item.path): \(error.localizedDescription)")
                    }
                }
            }
            let progress = Double(idx + 1) / Double(selectedItems.count)
            state = .cleaning(progress: progress)
        }
        if !dryRun && selectedCategories.contains(.trash) {
            try? fm.removeItem(at: URL(fileURLWithPath: expand("~/.Trash")))
            try? fm.createDirectory(atPath: expand("~/.Trash"), withIntermediateDirectories: true)
        }
        lastTrashedItems = trashed
        cleanErrors = errors
        lastScanned = nil
        state = .complete
        NotificationCenter.default.post(name: .diskFreed, object: nil)
        postCleanNotification(dryRun: dryRun)
    }

    private func isSystemOwnedPath(_ path: String) -> Bool {
        // Uses privilegedPathPrefixes from PrivilegedCleanHelper — single source of truth.
        // System-owned paths get a PrivilegedItemCard in completeState instead of a
        // silent skip, so the user can authenticate and delete them if desired.
        privilegedPathPrefixes.contains { path.hasPrefix($0) }
            && !path.hasPrefix("/Applications/")  // app bundles: handled by AppDetailView
    }

    // MARK: — Restore last clean (put back from Trash)
    // Moves each item from its current Trash location back to its original path.
    // Creates any missing intermediate directories (e.g. if the parent was also
    // trashed and then emptied by the OS — in that case we restore what we can).
    // Returns the count of successfully restored items and any error messages.
    @discardableResult
    func restoreLastClean() async -> (restored: Int, errors: [String]) {
        let fm = FileManager.default
        var restored = 0
        var errors: [String] = []

        for pair in lastTrashedItems {
            // Verify the item still exists in Trash (user may have emptied it)
            guard fm.fileExists(atPath: pair.inTrash.path) else {
                errors.append("\(pair.original.lastPathComponent): no longer in Trash")
                continue
            }
            do {
                // Recreate parent directory if it was also cleaned
                let parent = pair.original.deletingLastPathComponent()
                if !fm.fileExists(atPath: parent.path) {
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                // If something already exists at the original path, don't clobber it
                if fm.fileExists(atPath: pair.original.path) {
                    errors.append("\(pair.original.lastPathComponent): destination already exists")
                    continue
                }
                try fm.moveItem(at: pair.inTrash, to: pair.original)
                restored += 1
            } catch {
                errors.append("\(pair.original.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if restored > 0 {
            // Clear the undo list — can't undo twice
            lastTrashedItems = []
            NotificationCenter.default.post(name: .diskFreed, object: nil)
        }
        return (restored, errors)
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

    // NOTE: skipHidden=false is intentional — many caches (.npm, .gradle, .cargo, etc.)
    // live inside hidden dot-directories. Skipping them understates sizes.
    // skipPackages=false: we want to count inside .app bundles for App cache rows.
    nonisolated func dirSize(_ path: String) -> Int64 {
        FileSystemUtils.allocatedSize(path: path, skipHidden: false, skipPackages: false)
    }

}  // end CleanViewModel

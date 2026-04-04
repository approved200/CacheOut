import SwiftUI
import Foundation
import OSLog

enum ArtifactType: String, CaseIterable, Identifiable {
    case nodeModules = "node_modules"
    case derivedData = "DerivedData"
    case gradle      = ".gradle"
    case target      = "target"
    case buildDist   = "build"
    case venv        = "venv"
    case pods        = "Pods"
    case dotNext     = ".next"
    case dotNuxt     = ".nuxt"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .nodeModules: return .purple
        case .derivedData: return .blue
        case .gradle:      return .green
        case .target:      return .orange
        case .buildDist:   return .teal
        case .venv:        return .yellow
        case .pods:        return .red
        case .dotNext:     return .indigo
        case .dotNuxt:     return .mint
        }
    }
}

struct ProjectItem: Identifiable {
    let id = UUID()
    let name               : String   // parent project folder
    let path               : String   // full path to the artifact dir
    let size               : Int64
    let type               : ArtifactType
    let lastModifiedDaysAgo: Int
}

@MainActor
class PurgeViewModel: ObservableObject {
    @Published var projects: [ProjectItem] = []
    @Published var selectedProjects: Set<UUID> = []
    @Published var activeFilters: Set<ArtifactType> = Set(ArtifactType.allCases)
    @Published var sortOption: Int = 0
    @Published var isScanning = false
    @Published var isRefreshing = false
    /// 0.0–1.0 progress during a foreground scan; shown in PurgeView.
    /// Only meaningful while isScanning == true.
    @Published var scanProgress: Double = 0
    @Published var totalSize: Int64 = 0
    @Published var lastScanned: Date? = nil

    private let staleDuration: TimeInterval = 5 * 60

    // Scan roots — read from Settings at scan time so user changes take effect immediately.
    // Default (no custom dirs): the entire home directory. Artifact directories like
    // node_modules and DerivedData can live anywhere on a machine — guessing common
    // folder names always produces false negatives. We scan ~ and let PurgeScanner's
    // .skipsPackageDescendants + artifact-name matching do the filtering efficiently.
    // Users who want to narrow the scope can add specific roots in Settings → Dev purge.
    var scanRoots: [String] {
        let customRaw = UserDefaults.standard.string(forKey: "purgeScanDirs") ?? ""
        let custom = customRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if !custom.isEmpty {
            return custom.map { NSString(string: $0).expandingTildeInPath }
                         .filter { FileManager.default.fileExists(atPath: $0) }
        }
        // Default: scan the entire home directory
        return [NSHomeDirectory()]
    }

    // defaultScanRoots() kept as a static helper for callers that still reference it
    // (DevPurgeSettingsTab). Returns the same single-root default used by scanRoots.
    static func defaultScanRoots() -> [String] { [NSHomeDirectory()] }

    var filteredProjects: [ProjectItem] {
        var items = projects.filter { activeFilters.contains($0.type) }
        switch sortOption {
        case 0: items.sort { $0.size > $1.size }
        case 1: items.sort { $0.lastModifiedDaysAgo > $1.lastModifiedDaysAgo }
        case 2: items.sort { $0.type.rawValue < $1.type.rawValue }
        default: break
        }
        return items
    }

    // MARK: — Smart entry point
    func scanIfNeeded() async {
        if isScanning || isRefreshing { return }
        if projects.isEmpty {
            await scan()
        } else if let last = lastScanned,
                  Date().timeIntervalSince(last) > staleDuration {
            await backgroundRefresh()
        }
    }

    // MARK: — Force full scan
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        // Capture paths BEFORE clearing — used to restore selections after rescan
        let prevPaths = Set(projects.filter { selectedProjects.contains($0.id) }.map(\.path))
        projects = []
        selectedProjects = []

        let roots = scanRoots
        let rootCount = max(roots.count, 1)

        // PurgeScanner.findArtifacts runs synchronously on the detached thread.
        // We bridge progress back to the main actor via an AsyncStream so the
        // UI updates mid-scan without blocking the scanner thread.
        let found: [ProjectItem] = await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var results: [ProjectItem] = []
                for (idx, root) in roots.enumerated() {
                    let partial = PurgeScanner.findArtifacts(in: [root])
                    results.append(contentsOf: partial)
                    let progress = Double(idx + 1) / Double(rootCount)
                    await MainActor.run { self.scanProgress = progress }
                }
                continuation.resume(returning: results)
            }
        }

        projects = found
        if prevPaths.isEmpty {
            // First scan — auto-select stale items based on user's threshold setting
            let skipDays = UserDefaults.standard.integer(forKey: "purgeSkipRecentDays").nonZero ?? 7
            for p in projects where p.lastModifiedDaysAgo >= skipDays {
                selectedProjects.insert(p.id)
            }
        } else {
            // Rescan — restore selections by path (IDs regenerate each scan)
            for p in projects where prevPaths.contains(p.path) {
                selectedProjects.insert(p.id)
            }
        }
        updateTotalSize()
        lastScanned = Date()
        isScanning = false
        scanProgress = 0
        CacheOutLogger.purge.debugIfEnabled("Scan complete — \(projects.count) artifacts, \(totalSize) bytes, \(selectedProjects.count) selected")
    }

    // MARK: — Silent background refresh
    private func backgroundRefresh() async {
        isRefreshing = true
        let prevPaths = Set(projects.filter { selectedProjects.contains($0.id) }.map(\.path))

        let found = await Task.detached(priority: .background) { [roots = scanRoots] in
            PurgeScanner.findArtifacts(in: roots)
        }.value

        projects = found
        selectedProjects = []
        for p in projects where prevPaths.contains(p.path) {
            selectedProjects.insert(p.id)
        }
        updateTotalSize()
        lastScanned = Date()
        isRefreshing = false
    }

    // MARK: — Purge selected items
    @Published var purgeErrors: [String] = []

    func purge() async {
        let toDelete = projects.filter { selectedProjects.contains($0.id) }
        let dryRun = UserDefaults.standard.bool(forKey: "dryRunMode")
        CacheOutLogger.purge.debugIfEnabled("purge() — \(toDelete.count) items, dryRun=\(dryRun)")
        let fm = FileManager.default
        var errors: [String] = []
        if !dryRun {
            for item in toDelete {
                let url = URL(fileURLWithPath: item.path)
                do {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    let msg = "\(item.name): \(error.localizedDescription)"
                    errors.append(msg)
                    CacheOutLogger.purge.error("Trash failed for \(item.path): \(error.localizedDescription)")
                }
            }
        }
        purgeErrors = errors
        // Re-scan after purge (or after dry run so counts refresh)
        await scan()
        NotificationCenter.default.post(name: .diskFreed, object: nil)
    }

    func toggle(_ project: ProjectItem) {
        if selectedProjects.contains(project.id) {
            selectedProjects.remove(project.id)
        } else {
            selectedProjects.insert(project.id)
        }
        updateTotalSize()
    }

    private func updateTotalSize() {
        totalSize = projects
            .filter { selectedProjects.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }
}

// MARK: — Off-actor scanner (runs on background thread)
enum PurgeScanner {
    static func findArtifacts(in roots: [String]) -> [ProjectItem] {
        var results: [ProjectItem] = []
        let fm = FileManager.default

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }

                let dirName = url.lastPathComponent
                guard let type = ArtifactType(rawValue: dirName) else { continue }

                // Skip if this is nested inside another artifact dir
                let pathComponents = url.pathComponents
                let isNested = ArtifactType.allCases.contains { t in
                    pathComponents.dropLast().contains(t.rawValue)
                }
                guard !isNested else { enumerator.skipDescendants(); continue }

                enumerator.skipDescendants() // don't recurse inside artifacts

                let size = allocatedSize(url: url, fm: fm)
                guard size > 100_000 else { continue } // skip tiny dirs

                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date.distantPast
                let daysAgo = Int(Date().timeIntervalSince(modDate) / 86400)

                // Project name = parent folder of the artifact
                let projectName = url.deletingLastPathComponent().lastPathComponent

                results.append(ProjectItem(
                    name: projectName,
                    path: url.path,
                    size: size,
                    type: type,
                    lastModifiedDaysAgo: daysAgo
                ))
            }
        }
        return results.sorted { $0.size > $1.size }
    }

    private static func allocatedSize(url: URL, fm: FileManager) -> Int64 {
        FileSystemUtils.allocatedSize(path: url.path, skipHidden: true, fm: fm)
    }
}

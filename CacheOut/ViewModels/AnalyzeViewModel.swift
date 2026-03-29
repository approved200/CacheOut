import Foundation
import SwiftUI

@MainActor
class AnalyzeViewModel: ObservableObject {
    @Published var nodes: [DiskNode] = []
    @Published var breadcrumbs: [(name: String, path: String)] = []
    @Published var isScanning = false
    @Published var diskUsed: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var lastScanned: Date? = nil
    @Published var permissionDenied = false

    // Default to the boot volume root so users see a full-disk view on first open,
    // matching DaisyDisk's behaviour. Previously defaulted to ~/Library which was
    // confusing for anyone expecting whole-disk analysis.
    var rootPath: String = "/"

    /// The human-readable name for the root breadcrumb button.
    /// Shows the volume name at the root, the folder name when drilled in.
    var rootLabel: String {
        if rootPath == "/" {
            // Read the volume name; fall back to "Macintosh HD" if unavailable
            let url = URL(fileURLWithPath: "/")
            return (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
                ?? "Macintosh HD"
        }
        return (rootPath as NSString).lastPathComponent
    }

    private let scanner = DiskScanner()
    private let staleDuration: TimeInterval = 5 * 60

    var currentPath: String {
        breadcrumbs.last?.path ?? rootPath
    }

    var diskPct: Double {
        diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0
    }

    // Smart entry point — instant if fresh, rescan if stale
    func scanIfNeeded() async {
        if isScanning { return }
        if nodes.isEmpty {
            await loadDisk()
            await scan(currentPath)
        } else if let last = lastScanned,
                  Date().timeIntervalSince(last) > staleDuration {
            let path = currentPath
            isScanning = true
            let isVolumeRoot = (path as NSString).pathComponents.count <= 3
            let limit = isVolumeRoot ? 50 : 20
            let fresh = await scanner.topChildren(of: path, limit: limit)
            nodes = fresh
            lastScanned = Date()
            isScanning = false
        }
        // Fresh — do nothing, return immediately
    }

    // Explicit rescan (⌘R)
    func rescan() async {
        await scan(currentPath)
    }

    func scan(_ path: String) async {
        let hasAccess = (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/Library/Caches")) != nil
        guard hasAccess else {
            permissionDenied = true
            isScanning = false
            return
        }
        permissionDenied = false
        isScanning = true
        // Use a larger cap at the volume root so full-disk scans show enough detail
        let isVolumeRoot = (path as NSString).pathComponents.count <= 3
        let limit = isVolumeRoot ? 50 : 20
        nodes = await scanner.topChildren(of: path, limit: limit)
        lastScanned = Date()
        isScanning = false
    }

    func drillDown(_ node: DiskNode) {
        breadcrumbs.append((name: node.name, path: node.path))
        Task { await scan(node.path) }
    }

    func popTo(index: Int) async {
        if index == -1 {
            breadcrumbs = []
            await scan(rootPath)
        } else {
            let crumb = breadcrumbs[index]
            breadcrumbs = Array(breadcrumbs.prefix(index + 1))
            await scan(crumb.path)
        }
    }

    func loadDisk() async {
        guard let a = try? FileManager.default
            .attributesOfFileSystem(forPath: NSHomeDirectory()) else { return }
        diskTotal = (a[.systemSize]     as? UInt64) ?? 0
        diskUsed  = diskTotal - ((a[.systemFreeSize] as? UInt64) ?? 0)
    }
}

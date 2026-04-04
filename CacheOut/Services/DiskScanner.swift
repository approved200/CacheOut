import SwiftUI

// MARK: — Disk node model
struct DiskNode: Identifiable {
    let id      = UUID()
    let name    : String
    let path    : String
    let size    : Int64
    let ageDays : Int?   // days since last modification (nil = unknown)
}

// MARK: — Off-main-thread disk scanner
// Stateless enum — all methods are static. Callers dispatch to a background task
// themselves (see AnalyzeViewModel). There is no mutable state to protect, so
// `actor` isolation provided no real guarantee and was removed.
enum DiskScanner {

    // Returns up to `limit` largest visible children of `path`, sorted by size desc.
    // At volume root we pass limit: 0 (unlimited) to match DaisyDisk behaviour — show all
    // top-level directories. For drilled-in subdirectory views, limit: 20 is enough.
    static func scanChildren(of path: String, limit: Int = 20) -> [DiskNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var nodes: [DiskNode] = []
        for entry in entries where !entry.hasPrefix(".") {
            let full = (path as NSString).appendingPathComponent(entry)
            let sz   = allocatedSize(path: full, fm: fm)
            guard sz > 0 else { continue }
            nodes.append(DiskNode(name: entry, path: full, size: sz,
                                  ageDays: modAge(path: full, fm: fm)))
        }
        let sorted = nodes.sorted { $0.size > $1.size }
        // limit == 0 means unlimited (used at volume root)
        return limit > 0 ? Array(sorted.prefix(limit)) : sorted
    }

    static func allocatedSize(path: String, fm: FileManager = .default) -> Int64 {
        // Treemap use case: skip hidden files and treat .app bundles as atomic.
        FileSystemUtils.allocatedSize(path: path, skipHidden: true, skipPackages: true, fm: fm)
    }

    private static func modAge(path: String, fm: FileManager) -> Int? {
        guard let d = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return nil }
        return Int(Date().timeIntervalSince(d) / 86400)
    }
}

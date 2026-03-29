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
// Heavy enumeration runs in a detached task so the actor stays free during scanning.
actor DiskScanner {

    // Returns up to `limit` largest visible children of `path`, sorted by size desc.
    // Default limit of 20 is enough for ~/Library. Pass limit: 50 for full-volume scans.
    func topChildren(of path: String, limit: Int = 20) async -> [DiskNode] {
        await Task.detached(priority: .userInitiated) {
            DiskScanner.scanChildren(of: path, limit: limit)
        }.value
    }

    nonisolated static func scanChildren(of path: String, limit: Int = 20) -> [DiskNode] {
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
        // Top `limit` — configurable so full-volume scans (/) can show more
        return nodes.sorted { $0.size > $1.size }.prefix(limit).map { $0 }
    }

    private nonisolated static func allocatedSize(path: String, fm: FileManager) -> Int64 {
        guard let e = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        var total: Int64 = 0
        while let url = e.nextObject() as? URL {
            total += Int64(
                (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                    .totalFileAllocatedSize ?? 0
            )
        }
        return total
    }

    private nonisolated static func modAge(path: String, fm: FileManager) -> Int? {
        guard let d = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return nil }
        return Int(Date().timeIntervalSince(d) / 86400)
    }
}

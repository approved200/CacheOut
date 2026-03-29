import Foundation
import SwiftUI
import AppKit

// MARK: — Model
struct OrphanedItem: Identifiable {
    let id         = UUID()
    let path       : String
    let displayName: String
    let size       : Int64
    let category   : String   // "Caches", "Application Support", "Containers"
}

// MARK: — ViewModel
@MainActor
class OrphanedAppsViewModel: ObservableObject {
    @Published var items: [OrphanedItem] = []
    @Published var isScanning = false
    @Published var scanError: String? = nil
    @Published var selectedIDs: Set<UUID> = []

    var totalSelectedSize: Int64 {
        items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private var lastScanned: Date? = nil
    private let staleDuration: TimeInterval = 5 * 60

    func scanIfNeeded() async {
        if isScanning { return }
        if items.isEmpty { await scan() }
        else if let last = lastScanned, Date().timeIntervalSince(last) > staleDuration {
            await scan()
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanError = nil
        items = []
        selectedIDs = []

        let home = NSHomeDirectory()
        let found = await Task.detached(priority: .userInitiated) {
            OrphanScanner.findOrphans(home: home)
        }.value

        items = found
        selectedIDs = []   // default to none — orphan detection is heuristic
        lastScanned = Date()
        isScanning = false
    }

    func toggle(_ item: OrphanedItem) {
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
        else { selectedIDs.insert(item.id) }
    }

    func selectAll()  { selectedIDs = Set(items.map(\.id)) }
    func selectNone() { selectedIDs = [] }

    func trashSelected() async {
        let toTrash = items.filter { selectedIDs.contains($0.id) }
        var errors: [String] = []
        for item in toTrash {
            do {
                try FileManager.default.trashItem(
                    at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                items.removeAll { $0.id == item.id }
                selectedIDs.remove(item.id)
            } catch {
                errors.append("\(item.displayName): \(error.localizedDescription)")
            }
        }
        if !errors.isEmpty { scanError = errors.joined(separator: "\n") }
        NotificationCenter.default.post(name: .diskFreed, object: nil)
    }
}

// MARK: — Scanner
enum OrphanScanner {
    static func findOrphans(home: String) -> [OrphanedItem] {
        let fm = FileManager.default
        let installedBundleIDs = collectInstalledBundleIDs(fm: fm)
        let installedAppNames  = collectInstalledAppNames(fm: fm)
        // Build a set of bundle-ID prefixes for Application Support matching.
        // e.g. "net.shinyfrog.bear" → "net.shinyfrog" covers "net.shinyfrog.bear"
        // stored as "Bear" in Application Support (matched by name above) but
        // ALSO covers folders stored under their bundle ID or a prefix thereof.
        let installedIDPrefixes = bundleIDPrefixes(from: installedBundleIDs)
        var results: [OrphanedItem] = []

        // Directories to scan and their category labels
        let targets: [(subpath: String, category: String, matchByID: Bool)] = [
            ("Library/Caches",                "Caches",              true),
            ("Library/Application Support",   "Application Support", false),
            ("Library/Containers",            "Containers",          true),
        ]

        for target in targets {
            let dir = (home as NSString).appendingPathComponent(target.subpath)
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }

            for entry in entries {
                let full = (dir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue
                else { continue }

                // Check if still installed
                let isOrphaned: Bool
                if target.matchByID {
                    // Bundle-ID based: e.g. com.vendor.app in Caches/Containers
                    isOrphaned = !installedBundleIDs.contains(entry)
                        && !entry.hasPrefix("com.apple.")
                } else {
                    // Application Support: match by display name AND by bundle-ID prefix.
                    // Many apps store support data under their bundle ID rather than
                    // their display name (e.g. "net.shinyfrog.bear" not "Bear"), so
                    // name-only matching produces false positives.
                    let matchedByName   = installedAppNames.contains(entry)
                    let matchedByPrefix = installedIDPrefixes.contains(where: {
                        entry.hasPrefix($0)
                    })
                    let matchedByFullID = installedBundleIDs.contains(entry)
                    isOrphaned = !matchedByName
                        && !matchedByPrefix
                        && !matchedByFullID
                        && !entry.hasPrefix(".")
                        && !entry.hasPrefix("com.apple.")
                        && !["AddressBook","CallHistoryDB","Dock","iCloud",
                             "Knowledge","MobileSync","SyncServices"].contains(entry)
                }
                guard isOrphaned else { continue }

                let sz = dirSize(full, fm: fm)
                // Raised from 1 MB to 10 MB: name-based matching is heuristic and
                // false-positive rate at the low end is high. 10 MB filters out
                // tiny leftover plists and preference fragments that are harmless.
                guard sz > 10 * 1024 * 1024 else { continue }

                results.append(OrphanedItem(
                    path: full,
                    displayName: entry,
                    size: sz,
                    category: target.category
                ))
            }
        }
        return results.sorted { $0.size > $1.size }
    }

    /// Returns the two-component prefix of each bundle ID.
    /// "net.shinyfrog.bear" → "net.shinyfrog"
    /// Used to match Application Support folders stored under a bundle ID prefix.
    private static func bundleIDPrefixes(from ids: Set<String>) -> Set<String> {
        var prefixes = Set<String>()
        for id in ids {
            let parts = id.components(separatedBy: ".")
            if parts.count >= 2 {
                prefixes.insert(parts.prefix(2).joined(separator: "."))
            }
        }
        return prefixes
    }

    private static func collectInstalledBundleIDs(fm: FileManager) -> Set<String> {
        var ids = Set<String>()
        let searchDirs = ["/Applications",
                          (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        for dir in searchDirs {
            guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let plist = "\(dir)/\(app)/Contents/Info.plist"
                if let dict = NSDictionary(contentsOfFile: plist) as? [String: Any],
                   let bid = dict["CFBundleIdentifier"] as? String {
                    ids.insert(bid)
                }
            }
        }
        return ids
    }

    private static func collectInstalledAppNames(fm: FileManager) -> Set<String> {
        var names = Set<String>()
        let searchDirs = ["/Applications",
                          (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        for dir in searchDirs {
            guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let name = (app as NSString).deletingPathExtension
                names.insert(name)
                // Also try CFBundleName/CFBundleDisplayName for name-variant matching
                let plist = "\(dir)/\(app)/Contents/Info.plist"
                if let dict = NSDictionary(contentsOfFile: plist) as? [String: Any] {
                    if let dn = dict["CFBundleDisplayName"] as? String { names.insert(dn) }
                    if let bn = dict["CFBundleName"] as? String { names.insert(bn) }
                }
            }
        }
        return names
    }

    private static func dirSize(_ path: String, fm: FileManager) -> Int64 {
        guard let e = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        while let url = e.nextObject() as? URL {
            total += Int64((try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

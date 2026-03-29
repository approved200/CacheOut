import Foundation
import SwiftUI

struct LargeFileItem: Identifiable {
    let id       = UUID()
    let url      : URL
    let size     : Int64
    let ageDays  : Int
}

@MainActor
class LargeFilesViewModel: ObservableObject {
    @Published var items: [LargeFileItem] = []
    @Published var isScanning = false
    @Published var scanError: String? = nil
    @Published var filesScanned = 0

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
        filesScanned = 0
        items = []

        let roots = [NSHomeDirectory()]

        // Read user-configured minimum size (default 100 MB = 102400 KB)
        let minSizeKB = UserDefaults.standard.integer(forKey: "largeFilesMinSizeKB")
        let minBytes: Int64 = Int64(minSizeKB > 0 ? minSizeKB : 102_400) * 1024

        // Read excluded directories, expanding tilde to absolute paths
        let excludedRaw = UserDefaults.standard.string(forKey: "largeFilesExcludedDirs") ?? ""
        let excludedDirs = excludedRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { NSString(string: $0).expandingTildeInPath }

        let found = await Task.detached(priority: .userInitiated) {
            Self.findLargeFiles(in: roots, minSize: minBytes, excluding: excludedDirs)
        }.value

        items = found
        filesScanned = found.count
        lastScanned = Date()
        isScanning = false
    }

    func trash(_ item: LargeFileItem) async {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            items.removeAll { $0.id == item.id }
            NotificationCenter.default.post(name: .diskFreed, object: nil)
        } catch {
            scanError = error.localizedDescription
        }
    }

    private nonisolated static func findLargeFiles(
        in roots: [String],
        minSize: Int64,
        excluding excludedDirs: [String] = []
    ) -> [LargeFileItem] {
        let fm = FileManager.default

        // Pre-normalise excluded paths with a trailing "/" for safe prefix matching
        let excludedPrefixes = excludedDirs.map { path -> String in
            let norm = (path as NSString).standardizingPath
            return norm.hasSuffix("/") ? norm : norm + "/"
        }
        func isExcluded(_ url: URL) -> Bool {
            guard !excludedPrefixes.isEmpty else { return false }
            let p = url.path
            return excludedPrefixes.contains { p.hasPrefix($0) }
        }

        var results: [LargeFileItem] = []

        for root in roots {
            guard let e = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [
                    .totalFileAllocatedSizeKey,
                    .isRegularFileKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let url = e.nextObject() as? URL {
                guard let vals = try? url.resourceValues(forKeys: [
                    .isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
                ]),
                      vals.isRegularFile == true
                else { continue }

                if isExcluded(url) { continue }

                let sz = Int64(vals.totalFileAllocatedSize ?? 0)
                guard sz >= minSize else { continue }

                let mod = vals.contentModificationDate ?? Date()
                let age = Int(Date().timeIntervalSince(mod) / 86400)
                results.append(LargeFileItem(url: url, size: sz, ageDays: age))
            }
        }
        return results.sorted { $0.size > $1.size }.prefix(200).map { $0 }
    }
}

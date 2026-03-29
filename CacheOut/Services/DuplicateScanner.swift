import Foundation
import CryptoKit

// MARK: — Models

struct DuplicateGroup: Identifiable {
    let id       = UUID()
    let fileSize : Int64
    let hash     : String
    var files    : [URL]     // first entry = "keep" suggestion
}

// MARK: — Scanner (runs entirely off-actor)

enum DuplicateScanner {

    static func findDuplicates(
        in roots: [String],
        minSize: Int64 = 1 * 1024 * 1024,
        excluding excludedDirs: [String] = [],
        progress: @escaping (Double) -> Void
    ) -> [DuplicateGroup] {

        let fm = FileManager.default

        // Pre-normalise excluded paths once so every file check is a fast prefix test.
        // Append "/" so "/foo/bar" doesn't accidentally exclude "/foo/barsomething".
        let excludedPrefixes = excludedDirs.map { path -> String in
            let norm = (path as NSString).standardizingPath
            return norm.hasSuffix("/") ? norm : norm + "/"
        }

        func isExcluded(_ url: URL) -> Bool {
            guard !excludedPrefixes.isEmpty else { return false }
            let p = url.path
            return excludedPrefixes.contains { p.hasPrefix($0) }
        }

        // Phase 1 — collect all files, group by size (progress 0 → 0.3)
        var filesBySize: [Int64: [URL]] = [:]
        var totalFiles = 0

        for root in roots {
            let opts: FileManager.DirectoryEnumerationOptions = [
                .skipsHiddenFiles,
                .skipsPackageDescendants
            ]
            guard let e = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                options: opts
            ) else { continue }

            while let url = e.nextObject() as? URL {
                guard let vals = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]),
                      vals.isRegularFile == true
                else { continue }

                // Skip ~/Library — caches handled by Clean tab
                if url.path.contains("/Library/") { continue }

                // Skip user-excluded directories
                if isExcluded(url) { continue }

                let sz = Int64(vals.totalFileAllocatedSize ?? 0)
                guard sz >= minSize else { continue }
                filesBySize[sz, default: []].append(url)
                totalFiles += 1
            }
        }
        progress(0.3)

        // Phase 2a — partial SHA-256 (first 64 KB) within size buckets (0.3 → 0.6)
        var candidatesByPartialHash: [String: [URL]] = [:]
        let buckets = filesBySize.filter { $0.value.count > 1 }

        for (_, urls) in buckets {
            for url in urls {
                if let ph = partialHash(url) {
                    candidatesByPartialHash[ph, default: []].append(url)
                }
            }
        }
        progress(0.6)

        // Phase 2b — full SHA-256 for groups that still have 2+ matches (0.6 → 1.0)
        var groups: [DuplicateGroup] = []
        let partialMatches = candidatesByPartialHash.filter { $0.value.count > 1 }

        for (_, urls) in partialMatches {
            var byFullHash: [String: [URL]] = [:]
            for url in urls {
                if let fh = fullHash(url) {
                    byFullHash[fh, default: []].append(url)
                }
            }
            for (hash, dupes) in byFullHash where dupes.count > 1 {
                let sz = Int64((try? dupes[0].resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
                groups.append(DuplicateGroup(fileSize: sz, hash: hash, files: dupes))
            }
        }
        progress(1.0)

        // Sort largest savings first
        return groups.sorted { ($0.fileSize * Int64($0.files.count - 1))
                              > ($1.fileSize * Int64($1.files.count - 1)) }
    }

    // MARK: — Hashing helpers

    private static func partialHash(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        let data = fh.readData(ofLength: 65536)
        try? fh.close()
        guard !data.isEmpty else { return nil }
        return SHA256.hash(data: data).hexString
    }

    /// Streaming full SHA-256 — reads in 4 MB chunks so arbitrarily large files
    /// (e.g. 4 GB video files) never cause an OOM. This replaces the previous
    /// Data(contentsOf:) approach which mapped the entire file into memory.
    private static func fullHash(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        let chunkSize = 4 * 1024 * 1024  // 4 MB per chunk
        while true {
            let chunk = fh.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

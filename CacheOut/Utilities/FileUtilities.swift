import Foundation

// MARK: — Shared filesystem utilities
// Single source of truth for directory size measurement used across
// CleanViewModel, AppScanner, DiskScanner, OrphanScanner, and PurgeScanner.
//
// Two variants:
//   allocatedSize  — counts totalFileAllocatedSize (disk blocks actually used).
//                    Used everywhere sizes are shown to the user.
//   logicalSize    — counts totalFileSize (logical byte count, ignores APFS
//                    clones/sparse files). Kept for future use; not currently called.
//
// Both skip package descendants (.app bundles) so bundle sizes are their
// container size, not the sum of every framework inside.
// Hidden files are intentionally included — many caches (.npm, .gradle, etc.)
// live inside hidden directories.

enum FileUtilities {

    /// Returns the total allocated disk space of all files under `path`, in bytes.
    /// Uses `totalFileAllocatedSizeKey` (disk blocks × block size) which matches
    /// what Finder's "Get Info" shows and what DaisyDisk reports.
    ///
    /// - Parameters:
    ///   - path: Absolute path to a file or directory.
    ///   - fm:   `FileManager` instance to use. Pass the caller's instance to
    ///           avoid repeated `FileManager.default` lookups in hot paths.
    ///   - skipPackageDescendants: When `true` (default), stops recursing into
    ///     `.app`, `.framework`, and other package bundles so their size is
    ///     measured as a unit rather than summed from internals.
    @discardableResult
    nonisolated static func allocatedSize(
        of path: String,
        fm: FileManager = .default,
        skipPackageDescendants: Bool = true
    ) -> Int64 {
        var opts: FileManager.DirectoryEnumerationOptions = []
        if skipPackageDescendants { opts.insert(.skipsPackageDescendants) }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: opts
        ) else { return 0 }

        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                .totalFileAllocatedSize
                ?? (try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]))?
                .fileAllocatedSize
                ?? 0
            total += Int64(size)
        }
        return total
    }
}

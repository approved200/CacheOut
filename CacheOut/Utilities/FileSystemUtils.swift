import Foundation

// MARK: — Shared filesystem helpers
// Single source of truth for directory size measurement and related utilities.
// Previously duplicated across CleanViewModel, AppScanner, OrphanScanner, and
// DiskScanner with subtle behavioral differences. All callers now use these.

enum FileSystemUtils {

    /// Returns the total allocated on-disk size of `path` in bytes.
    ///
    /// Options:
    /// - `skipHidden`: when true, skips dot-files and dot-directories (default false).
    ///   Caches such as .npm, .gradle, .cargo live inside hidden dirs — callers that
    ///   need to measure them must pass false (the default).
    /// - `skipPackages`: when true, stops recursing at .app bundle boundaries so
    ///   .app bundles are counted as atomic units (default false). Pass true when
    ///   building disk-usage treemaps where package contents are opaque.
    static func allocatedSize(
        path: String,
        skipHidden: Bool = false,
        skipPackages: Bool = false,
        fm: FileManager = .default
    ) -> Int64 {
        var opts: FileManager.DirectoryEnumerationOptions = []
        if skipHidden   { opts.insert(.skipsHiddenFiles) }
        if skipPackages { opts.insert(.skipsPackageDescendants) }

        guard let e = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: opts
        ) else { return 0 }

        var total: Int64 = 0
        while let url = e.nextObject() as? URL {
            let s = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                        .totalFileAllocatedSize
                    ?? (try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]))?
                        .fileAllocatedSize ?? 0
            total += Int64(s)
        }
        return total
    }

    /// Returns the number of immediate children in `path`, or 0 if unreadable.
    static func itemCount(at path: String, fm: FileManager = .default) -> Int {
        (try? fm.contentsOfDirectory(atPath: path))?.count ?? 0
    }
}

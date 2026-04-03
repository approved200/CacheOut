import Foundation
import SwiftUI

// MARK: — File category for type-based filtering
enum FileCategory: String, CaseIterable, Identifiable {
    case video    = "Video"
    case image    = "Image"
    case audio    = "Audio"
    case document = "Document"
    case archive  = "Archive"
    case code     = "Code"
    case other    = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .video:    return "film"
        case .image:    return "photo"
        case .audio:    return "music.note"
        case .document: return "doc.text"
        case .archive:  return "archivebox"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .other:    return "doc"
        }
    }

    var color: Color {
        switch self {
        case .video:    return .purple
        case .image:    return .pink
        case .audio:    return .orange
        case .document: return .blue
        case .archive:  return .brown
        case .code:     return .green
        case .other:    return Color(nsColor: .secondaryLabelColor)
        }
    }

    // Extensions that belong to each category
    static func category(for url: URL) -> FileCategory {
        switch url.pathExtension.lowercased() {
        case "mp4","mov","m4v","avi","mkv","wmv","webm","hevc","m2ts","vob","3gp","flv":
            return .video
        case "jpg","jpeg","png","gif","heic","heif","tiff","tif","bmp","webp","raw","cr2","nef","arw","svg","psd","ai":
            return .image
        case "mp3","aac","flac","wav","aiff","m4a","ogg","wma","alac","opus":
            return .audio
        case "pdf","doc","docx","xls","xlsx","ppt","pptx","pages","numbers","key","txt","rtf","md","csv","odt","epub":
            return .document
        case "zip","tar","gz","bz2","xz","7z","rar","dmg","iso","pkg","app":
            return .archive
        case "swift","py","js","ts","jsx","tsx","rb","go","java","kt","rs","c","cpp","h","cs","php","html","css","sh","bash","zsh","json","xml","yaml","yml","toml","sql","r","lua","dart","vue","svelte":
            return .code
        default:
            return .other
        }
    }
}

struct LargeFileItem: Identifiable {
    let id       = UUID()
    let url      : URL
    let size     : Int64
    let ageDays  : Int
    let category : FileCategory   // derived once at scan time
}

@MainActor
class LargeFilesViewModel: ObservableObject {
    @Published var items: [LargeFileItem] = []
    @Published var isScanning = false
    @Published var scanError: String? = nil
    @Published var filesScanned = 0
    /// True when the scan found more than 500 files and results were capped.
    /// The view uses this to show a "Showing top 500 by size" notice.
    @Published var isTruncated = false
    /// Active category filters — all on by default. Empty set = show all.
    @Published var activeCategories: Set<FileCategory> = []
    /// Custom scan roots added via the "Scan this folder…" button in-view.
    /// Stored separately from largeFilesExcludedDirs so the user can add
    /// roots without opening Settings.
    @Published var customScanRoots: [String] = []

    private var lastScanned: Date? = nil
    private let staleDuration: TimeInterval = 5 * 60

    var filteredItems: [LargeFileItem] {
        guard !activeCategories.isEmpty else { return items }
        return items.filter { activeCategories.contains($0.category) }
    }

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

        // Use custom roots if set, otherwise fall back to home
        let roots: [String] = customScanRoots.isEmpty
            ? [NSHomeDirectory()]
            : customScanRoots

        let minSizeKB = UserDefaults.standard.integer(forKey: "largeFilesMinSizeKB")
        let minBytes: Int64 = Int64(minSizeKB > 0 ? minSizeKB : 102_400) * 1024

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
        isTruncated = found.count >= 500
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
                results.append(LargeFileItem(
                    url: url, size: sz, ageDays: age,
                    category: FileCategory.category(for: url)
                ))
            }
        }
        return results.sorted { $0.size > $1.size }.prefix(500).map { $0 }
    }
}

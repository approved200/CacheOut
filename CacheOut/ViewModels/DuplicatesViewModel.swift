import Foundation
import SwiftUI

@MainActor
class DuplicatesViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var phaseLabel: String = ""
    @Published var filesScanned: Int = 0
    @Published var scanError: String? = nil

    var totalSavings: Int64 {
        groups.reduce(0) { $0 + ($1.fileSize * Int64($1.files.count - 1)) }
    }

    private var scanTask: Task<Void, Never>? = nil
    private var lastScanned: Date? = nil
    private let staleDuration: TimeInterval = 5 * 60

    // MARK: — Smart entry point (mirrors every other tab's pattern)
    func scanIfNeeded() async {
        if isScanning { return }
        if groups.isEmpty {
            await scan(roots: PurgeViewModel.defaultScanRoots())
        } else if let last = lastScanned,
                  Date().timeIntervalSince(last) > staleDuration {
            await scan(roots: PurgeViewModel.defaultScanRoots())
        }
    }

    // MARK: — Scan
    func scan(roots: [String]) async {
        guard !isScanning else { return }
        scanTask?.cancel()
        isScanning = true
        scanError = nil
        groups = []
        progress = 0
        phaseLabel = "Grouping by size…"

        // Read the user's configured minimum size (default 1 MB = 1024 KB)
        let minSizeKB = UserDefaults.standard.integer(forKey: "duplicatesMinSizeKB")
        let minBytes: Int64 = Int64(minSizeKB > 0 ? minSizeKB : 1024) * 1024

        // Read excluded directories, expanding any tilde paths to absolute paths
        let excludedRaw = UserDefaults.standard.string(forKey: "duplicatesExcludedDirs") ?? ""
        let excludedDirs = excludedRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { NSString(string: $0).expandingTildeInPath }

        let progressActor = ProgressReporter(owner: self)

        let result = await Task.detached(priority: .userInitiated) { [roots, minBytes, excludedDirs] in
            DuplicateScanner.findDuplicates(in: roots, minSize: minBytes, excluding: excludedDirs) { p in
                Task { @MainActor in progressActor.report(p) }
            }
        }.value

        groups = result
        lastScanned = Date()
        isScanning = false
        phaseLabel = ""
    }

    // MARK: — Remove duplicates keeping one file
    func remove(keeping keepURL: URL, from group: DuplicateGroup) async {
        let toTrash = group.files.filter { $0 != keepURL }
        let fm = FileManager.default
        var errors: [String] = []

        for url in toTrash {
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } catch {
                errors.append(url.lastPathComponent + ": " + error.localizedDescription)
            }
        }

        // Remove the group regardless (even if some failed, the rest are gone)
        groups.removeAll { $0.id == group.id }
        NotificationCenter.default.post(name: .diskFreed, object: nil)

        if !errors.isEmpty {
            scanError = errors.joined(separator: "\n")
        }
    }

    // MARK: — Remove all duplicates (keep first in each group)
    func removeAll() async {
        let snapshot = groups
        for group in snapshot {
            guard let keep = group.files.first else { continue }
            await remove(keeping: keep, from: group)
        }
    }
}

// MARK: — Progress reporter
// A simple Sendable wrapper that lets the off-actor scanner report progress
// back to the MainActor ViewModel without a weak reference pattern.
@MainActor
private final class ProgressReporter {
    private weak var owner: DuplicatesViewModel?
    init(owner: DuplicatesViewModel) { self.owner = owner }

    func report(_ p: Double) {
        guard let vm = owner else { return }
        vm.progress = p
        if p < 0.31      { vm.phaseLabel = "Grouping by size…" }
        else if p < 0.61 { vm.phaseLabel = "Computing partial hashes…" }
        else             { vm.phaseLabel = "Verifying duplicates…" }
    }
}

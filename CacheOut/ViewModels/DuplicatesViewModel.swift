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
    /// Active category filters. Empty = show all.
    @Published var activeCategories: Set<FileCategory> = []
    /// Custom scan roots added via the in-view "Scan this folder…" button.
    /// Persisted to UserDefaults so roots survive app restarts.
    @Published var customScanRoots: [String] = [] {
        didSet {
            let joined = customScanRoots.joined(separator: "\n")
            UserDefaults.standard.set(joined, forKey: "duplicatesScanRoots")
        }
    }
    /// Tracks every (original path → path in Trash) pair from the last remove operation.
    /// Populated by remove(keeping:from:) and removeAll(). Used to drive "Put back" restore.
    /// Cleared at the start of each new scan so it only reflects the most recent session.
    @Published var lastTrashedItems: [(original: URL, inTrash: URL)] = []

    var totalSavings: Int64 {
        filteredGroups.reduce(0) { $0 + ($1.fileSize * Int64($1.files.count - 1)) }
    }

    var filteredGroups: [DuplicateGroup] {
        guard !activeCategories.isEmpty else { return groups }
        return groups.filter { group in
            guard let first = group.files.first else { return false }
            return activeCategories.contains(FileCategory.category(for: first))
        }
    }

    private var scanTask: Task<Void, Never>? = nil
    private var lastScanned: Date? = nil
    private let staleDuration: TimeInterval = 5 * 60

    init() {
        // Restore persisted scan roots
        let raw = UserDefaults.standard.string(forKey: "duplicatesScanRoots") ?? ""
        customScanRoots = raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    // MARK: — Smart entry point
    func scanIfNeeded() async {
        if isScanning { return }
        let roots: [String] = customScanRoots.isEmpty
            ? PurgeViewModel.defaultScanRoots()
            : customScanRoots
        if groups.isEmpty {
            await scan(roots: roots)
        } else if let last = lastScanned,
                  Date().timeIntervalSince(last) > staleDuration {
            await scan(roots: roots)
        }
    }

    // MARK: — Cancel in-flight scan
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning {
            isScanning = false
            phaseLabel = ""
            progress = 0
        }
    }

    // MARK: — Scan
    func scan(roots: [String]) async {
        guard !isScanning else { return }
        scanTask?.cancel()
        isScanning = true
        scanError = nil
        groups = []
        lastTrashedItems = []   // new scan = new session, clear undo history
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

        let innerTask = Task.detached(priority: .userInitiated) { [roots, minBytes, excludedDirs] in
            DuplicateScanner.findDuplicates(in: roots, minSize: minBytes, excluding: excludedDirs) { p in
                Task { @MainActor in progressActor.report(p) }
            }
        }
        // Store so cancelScan() / onDisappear can terminate mid-scan
        scanTask = Task {
            let result = await innerTask.value
            groups = result
            lastScanned = Date()
            isScanning = false
            phaseLabel = ""
        }
        await scanTask?.value
        // If we were cancelled mid-flight, reset scanning state cleanly
        if Task.isCancelled {
            innerTask.cancel()
            isScanning = false
            phaseLabel = ""
        }
    }

    // MARK: — Remove duplicates keeping one chosen file
    // keepURL is the file the user designated to keep — all other files in the
    // group are moved to Trash. The original→trash pairs are appended to
    // lastTrashedItems so the user can restore them via "Put back".
    func remove(keeping keepURL: URL, from group: DuplicateGroup) async {
        let toTrash = group.files.filter { $0 != keepURL }
        let fm = FileManager.default
        var errors: [String] = []

        for url in toTrash {
            do {
                var resultURL: NSURL? = nil
                try fm.trashItem(at: url, resultingItemURL: &resultURL)
                if let dest = resultURL as URL? {
                    lastTrashedItems.append((original: url, inTrash: dest))
                }
            } catch {
                errors.append(url.lastPathComponent + ": " + error.localizedDescription)
            }
        }

        groups.removeAll { $0.id == group.id }
        NotificationCenter.default.post(name: .diskFreed, object: nil)

        if !errors.isEmpty {
            scanError = errors.joined(separator: "\n")
        }
    }

    // MARK: — Remove all duplicates visible under the current filter (keep first in each group)
    func removeAll() async {
        let snapshot = filteredGroups
        for group in snapshot {
            guard let keep = group.files.first else { continue }
            await remove(keeping: keep, from: group)
        }
    }

    // MARK: — Restore trashed items back to their original locations
    @discardableResult
    func restoreLastClean() async -> (restored: Int, errors: [String]) {
        let fm = FileManager.default
        var restored = 0
        var errors: [String] = []

        for pair in lastTrashedItems {
            guard fm.fileExists(atPath: pair.inTrash.path) else {
                errors.append("\(pair.original.lastPathComponent): no longer in Trash")
                continue
            }
            do {
                let parent = pair.original.deletingLastPathComponent()
                if !fm.fileExists(atPath: parent.path) {
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                guard !fm.fileExists(atPath: pair.original.path) else {
                    errors.append("\(pair.original.lastPathComponent): destination already exists")
                    continue
                }
                try fm.moveItem(at: pair.inTrash, to: pair.original)
                restored += 1
            } catch {
                errors.append("\(pair.original.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if restored > 0 {
            lastTrashedItems = []
            NotificationCenter.default.post(name: .diskFreed, object: nil)
        }
        return (restored, errors)
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

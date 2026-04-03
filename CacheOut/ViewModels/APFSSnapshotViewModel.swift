import Foundation
import SwiftUI

// MARK: — Model

struct APFSSnapshot: Identifiable {
    let id          = UUID()
    let name        : String   // e.g. "com.apple.TimeMachine.2026-03-26-091542"
    let date        : Date
    let mountPoint  : String   // volume it lives on, e.g. "/"
    var sizeBytes   : Int64    // 0 = not yet measured (tmutil doesn't report size)
    var isSelected  : Bool = true

    /// Friendly display date derived from the snapshot name timestamp.
    var displayDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: — ViewModel

@MainActor
class APFSSnapshotViewModel: ObservableObject {
    @Published var snapshots: [APFSSnapshot] = []
    @Published var isScanning  = false
    @Published var isDeleting  = false
    @Published var deleteError : String? = nil
    @Published var purgeableBytes: Int64 = 0

    var selectedSnapshots: [APFSSnapshot] { snapshots.filter(\.isSelected) }

    func scanIfNeeded() async {
        // Skip if we already have data or are already scanning
        guard snapshots.isEmpty, !isScanning else {
            if !snapshots.isEmpty { isScanning = false }
            return
        }
        await scan()
    }

    func scan() async {
        guard !isDeleting else { return }
        deleteError = nil
        SidebarLogger.log("APFSSnapshotViewModel.scan() started")

        isScanning = true

        async let snaps = Task.detached(priority: .userInitiated) {
            await APFSSnapshotScanner.listSnapshots()
        }.value

        async let purgeable = Task.detached(priority: .userInitiated) {
            APFSSnapshotScanner.purgeableSpace(mountPoint: "/")
        }.value

        let (found, purge) = await (snaps, purgeable)
        SidebarLogger.log("APFSSnapshotViewModel.scan() complete — found \(found.count) snapshots, purgeableBytes=\(purge)")
        snapshots = found
        purgeableBytes = purge
        isScanning = false
    }

    func toggle(_ snapshot: APFSSnapshot) {
        guard let i = snapshots.firstIndex(where: { $0.id == snapshot.id }) else { return }
        snapshots[i].isSelected.toggle()
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil
        var errors: [String] = []

        for snapshot in selectedSnapshots {
            let result = await Task.detached(priority: .userInitiated) {
                await APFSSnapshotScanner.deleteSnapshot(name: snapshot.name)
            }.value
            if let err = result {
                errors.append("\(snapshot.name): \(err)")
            } else {
                snapshots.removeAll { $0.id == snapshot.id }
            }
        }

        if !errors.isEmpty { deleteError = errors.joined(separator: "\n") }
        isDeleting = false
        NotificationCenter.default.post(name: .diskFreed, object: nil)
        // Refresh purgeable space after deletion
        let fresh = await Task.detached(priority: .userInitiated) {
            APFSSnapshotScanner.purgeableSpace(mountPoint: "/")
        }.value
        purgeableBytes = fresh
    }
}

// MARK: — Scanner (nonisolated, runs off-actor)

enum APFSSnapshotScanner {

    /// Lists all local Time Machine snapshots across all APFS volumes.
    /// Uses `tmutil listlocalsnapshots /` which works without sudo.
    static func listSnapshots() async -> [APFSSnapshot] {
        // Get snapshots on the boot volume
        let output = await run(["/usr/bin/tmutil", "listlocalsnapshots", "/"])
        var results: [APFSSnapshot] = []

        for line in output.components(separatedBy: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            // Name format: com.apple.TimeMachine.2026-03-26-091542.local
            let date = parseDate(from: name)
            results.append(APFSSnapshot(
                name: name,
                date: date ?? Date(),
                mountPoint: "/",
                sizeBytes: 0
            ))
        }
        return results.sorted { $0.date > $1.date }  // newest first
    }

    /// Returns the purgeable space on a volume in bytes.
    /// This is the space APFS can reclaim from snapshots + cached files.
    static func purgeableSpace(mountPoint: String) -> Int64 {
        guard let vals = try? URL(fileURLWithPath: mountPoint)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                       .volumeAvailableCapacityKey]) else { return 0 }
        let importantFree = vals.volumeAvailableCapacityForImportantUsage ?? 0
        let actualFree    = Int64(vals.volumeAvailableCapacity ?? 0)
        // Purgeable = space available for important usage minus what's truly free
        // This reveals snapshot + cached data the Finder hides
        let purgeable = importantFree - actualFree
        return max(0, purgeable)
    }

    /// Deletes a snapshot by name. Returns nil on success, error string on failure.
    static func deleteSnapshot(name: String) async -> String? {
        // Extract date component: com.apple.TimeMachine.2026-03-26-091542.local → 2026-03-26-091542
        let parts = name.components(separatedBy: ".")
        // Find the date-like component (contains dashes with digits)
        guard let datePart = parts.first(where: {
            $0.count >= 15 && $0.first?.isNumber == true
        }) else {
            return "Could not parse snapshot date from name: \(name)"
        }

        let output = await run(["/usr/bin/tmutil", "deletelocalsnapshots", datePart])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // tmutil exits 0 on success; any error message on stderr means failure
        if trimmed.lowercased().contains("error") || trimmed.lowercased().contains("failed") {
            return trimmed.isEmpty ? "Unknown error deleting \(name)" : trimmed
        }
        return nil
    }

    // MARK: — Helpers

    private static func parseDate(from name: String) -> Date? {
        // Extract "2026-03-26-091542" from "com.apple.TimeMachine.2026-03-26-091542.local"
        let parts = name.components(separatedBy: ".")
        guard let datePart = parts.first(where: {
            $0.count >= 15 && $0.first?.isNumber == true
        }) else { return nil }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: datePart)
    }

    // CRITICAL: pipes are drained BEFORE waitUntilExit to prevent deadlock.
    // If the process writes more than ~65 KB to stdout/stderr and we wait first,
    // the pipe buffer fills, the child blocks on write, and waitUntilExit hangs.
    // terminationHandler has the same bug — the handler fires after the process
    // exits, but the pipe buffer may already be full before exit. Always read first.
    private static func run(_ args: [String]) async -> String {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: args[0])
            task.arguments = Array(args.dropFirst())
            let pipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = pipe
            task.standardError  = errPipe

            do { try task.run() } catch {
                continuation.resume(returning: "")
                return
            }

            // Read pipes on a background thread FIRST, then wait for exit.
            DispatchQueue.global(qos: .utility).async {
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: errStr.isEmpty ? outStr : errStr + outStr)
            }
        }
    }
}

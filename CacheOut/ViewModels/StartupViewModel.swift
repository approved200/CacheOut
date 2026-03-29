import Foundation
import AppKit
import OSLog

@MainActor
class StartupViewModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var isScanning = false
    @Published var actionError: String? = nil

    private let staleDuration: TimeInterval = 5 * 60
    private var lastScanned: Date? = nil

    // MARK: — Smart entry point
    func scanIfNeeded() async {
        if isScanning { return }
        if items.isEmpty {
            await scan()
        } else if let last = lastScanned,
                  Date().timeIntervalSince(last) > staleDuration {
            await scan()
        }
    }

    // MARK: — Full scan
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        actionError = nil
        items = await Task.detached(priority: .userInitiated) {
            StartupScanner.scan()
        }.value
        lastScanned = Date()
        isScanning = false
    }

    // MARK: — Toggle enabled state
    // For user launch agents: load/unload via launchctl.
    // For system items: not supported — caller should show the System Settings banner.
    func toggle(_ item: StartupItem) async {
        guard item.source == .userLaunchAgent,
              let plistPath = item.plistPath else { return }

        actionError = nil
        let shouldLoad = !item.isLoaded

        let result = await Task.detached(priority: .userInitiated) {
            Self.runLaunchctl(args: shouldLoad
                              ? ["load", "-w", plistPath]
                              : ["unload", "-w", plistPath])
        }.value

        if let err = result {
            actionError = err
        } else {
            // Update the item's isLoaded/isEnabled state in-place
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].isLoaded  = shouldLoad
                items[idx].isEnabled = shouldLoad
            }
        }
    }

    // MARK: — Remove a user launch agent plist
    func remove(_ item: StartupItem) async {
        guard item.source == .userLaunchAgent,
              let plistPath = item.plistPath else { return }

        actionError = nil

        // Unload first if it's running
        if item.isLoaded {
            _ = await Task.detached(priority: .userInitiated) {
                Self.runLaunchctl(args: ["unload", "-w", plistPath])
            }.value
        }

        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: plistPath), resultingItemURL: nil)
            items.removeAll { $0.id == item.id }
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: — Private helpers

    // nonisolated so it can be called from Task.detached without hopping back to MainActor
    private nonisolated static func runLaunchctl(args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        let errPipe = Pipe()
        task.standardError = errPipe
        let outPipe = Pipe()
        task.standardOutput = outPipe
        do { try task.run() } catch { return error.localizedDescription }
        outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "launchctl failed"
            return msg.isEmpty ? "launchctl exited with code \(task.terminationStatus)" : msg
        }
        return nil
    }
}

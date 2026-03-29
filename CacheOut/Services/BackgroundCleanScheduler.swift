import Foundation
import UserNotifications

// MARK: — BackgroundCleanScheduler
// Uses NSBackgroundActivityScheduler — the correct macOS API for periodic background
// work. BGTaskScheduler is iOS/tvOS only and unavailable on macOS.
//
// Schedule values (autoCleanSchedule UserDefaults key):
//   0 = Never
//   1 = Daily     (interval: 24h)
//   2 = Weekly    (interval: 7d)
//   3 = Monthly   (interval: 30d)
//
// Call BackgroundCleanScheduler.shared.scheduleIfNeeded() on launch and whenever
// the setting changes. Calling it again cancels and recreates the scheduler so
// the new interval takes effect immediately.

@MainActor
final class BackgroundCleanScheduler {
    static let shared = BackgroundCleanScheduler()
    private static let activityIdentifier = "com.cacheout.autoClean"

    private var activity: NSBackgroundActivityScheduler?
    private var activeScanTask: Task<Void, Never>?

    // The ViewModel used for background scans. Injected from ContentView so that
    // scan state is visible to the user — avoids a hidden ghost VM that silently
    // scans without any UI feedback.
    var scanVM: CleanViewModel?

    private init() {}

    // MARK: — Tear down completely (call on applicationWillTerminate)
    func invalidate() {
        // Cancel any in-flight scan first — this signals Task.isCancelled
        // so the ViewModel's async loops exit cleanly at the next suspension point.
        activeScanTask?.cancel()
        activeScanTask = nil

        activity?.invalidate()
        activity = nil
    }

    // MARK: — Schedule or cancel based on current setting
    func scheduleIfNeeded() {
        // Cancel any in-flight scan before tearing down the scheduler
        activeScanTask?.cancel()
        activeScanTask = nil

        activity?.invalidate()
        activity = nil

        let schedule = UserDefaults.standard.integer(forKey: "autoCleanSchedule")
        guard schedule != 0 else { return }   // "Never" — leave cancelled

        let intervalSeconds: TimeInterval
        switch schedule {
        case 1: intervalSeconds = 24 * 3600          // daily
        case 2: intervalSeconds = 7  * 24 * 3600     // weekly
        case 3: intervalSeconds = 30 * 24 * 3600     // monthly
        default: return
        }

        let scheduler = NSBackgroundActivityScheduler(identifier: Self.activityIdentifier)
        scheduler.repeats          = true
        scheduler.interval         = intervalSeconds
        scheduler.tolerance        = intervalSeconds * 0.1   // ±10% scheduling window
        scheduler.qualityOfService = .background

        scheduler.schedule { [weak self] completion in
            guard let self else { completion(.deferred); return }
            Task { @MainActor in
                await self.runBackgroundScan(completion: completion)
            }
        }

        activity = scheduler
    }

    // MARK: — Background scan work
    private func runBackgroundScan(completion: @escaping (NSBackgroundActivityScheduler.Result) -> Void) async {
        guard UserDefaults.standard.bool(forKey: "scanOnLaunch") else {
            completion(.deferred)
            return
        }
        guard let vm = scanVM else {
            completion(.deferred)
            return
        }
        let task = Task { @MainActor in
            await vm.startScan()
        }
        activeScanTask = task
        await task.value
        activeScanTask = nil
        guard !task.isCancelled else {
            completion(.deferred)
            return
        }
        let found = vm.totalSelectedSize
        if found > 10_000_000 {
            postFoundNotification(bytes: found)
        }
        completion(.finished)
    }

    private func postFoundNotification(bytes: Int64) {
        guard UserDefaults.standard.bool(forKey: "notifyOnComplete") else { return }
        let content = UNMutableNotificationContent()
        content.title = "Cache Out found junk"
        content.body  = "\(formatBytes(bytes)) of caches and junk is ready to clean."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "auto-clean-found-\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
        )
    }
}

import Foundation

// MARK: — SparkleUpdater
// Wraps Sparkle's SPUStandardUpdaterController and exposes a thin
// ObservableObject surface so Settings can bind to update availability.
//
// SETUP STATUS (as of 2026-03-25):
//   ✓ Step 1 — Sparkle 2.x added via SPM (File → Add Package Dependencies)
//   ✓ Step 2 — EdDSA keys generated; public key in Info.plist → SUPublicEDKey;
//               private key saved to macOS Keychain by generate_keys automatically
//   ✓ Step 3 — SUFeedURL points to apoorv/cache-out on GitHub
//   ○ Step 4 — After each release: sign the notarized DMG and update appcast.xml:
//       ~/...DerivedData/.../SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
//         CacheOut-1.x.dmg
//       (private key is read from Keychain automatically — no --ed-key-file flag needed)
//       Paste the printed edSignature + DMG byte size into appcast.xml, then push to main.
//
// The #if canImport(Sparkle) guard is kept for safety — compiles as a no-op stub
// in any environment where the SPM package is not resolved.

#if canImport(Sparkle)
import Sparkle

/// Observable wrapper so `SettingsView` can bind to update state.
@MainActor
final class SparkleUpdater: ObservableObject {

    static let shared = SparkleUpdater()

    /// True while Sparkle is performing a check or downloading.
    @Published private(set) var isCheckingForUpdates = false

    /// True once Sparkle has confirmed the app is up to date (post first check).
    @Published private(set) var isUpToDate = false

    /// Non-nil when a valid update is waiting to be installed.
    @Published private(set) var pendingUpdateVersion: String? = nil

    private let controller: SPUStandardUpdaterController
    private let delegate   = SparkleDelegate()

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        // SPUUpdaterDelegate has no "willCheckForUpdates" hook in Sparkle 2.x.
        // We set isCheckingForUpdates = true directly inside checkForUpdates()
        // before calling the controller, and clear it in the cycle-finish callback.
        delegate.onDidFindValidUpdate = { [weak self] versionString in
            DispatchQueue.main.async {
                self?.isCheckingForUpdates = false
                self?.pendingUpdateVersion = versionString
            }
        }
        delegate.onDidFinishUpdateCycle = { [weak self] in
            DispatchQueue.main.async {
                self?.isCheckingForUpdates = false
                if self?.pendingUpdateVersion == nil {
                    self?.isUpToDate = true
                }
            }
        }
    }

    // MARK: — Public API

    /// Triggered by "Check for Updates…" in the app menu.
    func checkForUpdates() {
        // SPUUpdaterDelegate has no pre-check hook, so we set the spinner state here
        // before handing off to Sparkle. The delegate's onDidFinishUpdateCycle clears it.
        isCheckingForUpdates = true
        isUpToDate = false
        pendingUpdateVersion = nil
        controller.checkForUpdates(nil)
    }

    /// Whether the menu item / button should be enabled.
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
}

// MARK: — Minimal Sparkle delegate (bridges callbacks to closures)
// Method signatures verified directly against SPUUpdaterDelegate.h in the
// Sparkle 2.x checkout. The protocol has NO "willCheckForUpdates" hook —
// the closest available notification is updater:willScheduleUpdateCheckAfterDelay:
// and the deprecated updaterMayCheckForUpdates:. To drive the spinner we
// instead set isCheckingForUpdates = true inside checkForUpdates() before
// the call, and clear it in the cycle-finish callback.
private final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    var onDidFindValidUpdate:   ((String) -> Void)?
    var onDidFinishUpdateCycle: (() -> Void)?

    // Called when a valid update is found — exact signature from SPUUpdaterDelegate.h
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onDidFindValidUpdate?(item.displayVersionString)
    }

    // Called when the full update cycle finishes — ObjC selector is
    // updater:didFinishUpdateCycleForUpdateCheck:error: but Swift imports it
    // with the label truncated to didFinishUpdateCycleFor: (type suffix dropped).
    func updater(_ updater: SPUUpdater,
                 didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: (any Error)?) {
        onDidFinishUpdateCycle?()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { }
}

#else

// MARK: — Stub (active until Sparkle SPM is added)
// Provides the same ObservableObject surface so the rest of the app compiles
// unchanged. Settings row shows "Add Sparkle SPM to enable updates."
@MainActor
final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()

    @Published private(set) var isCheckingForUpdates     = false
    @Published private(set) var isUpToDate               = false
    @Published private(set) var pendingUpdateVersion: String? = nil

    /// False while Sparkle is not linked — correctly grays out the menu item.
    var canCheckForUpdates: Bool { false }

    private init() { }

    func checkForUpdates() {
        // No-op until the Sparkle SPM package is added.
        // See the setup instructions at the top of this file.
    }
}
#endif

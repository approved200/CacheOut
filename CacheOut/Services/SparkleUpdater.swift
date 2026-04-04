import Foundation

// MARK: — SparkleUpdater
// Wraps Sparkle's SPUStandardUpdaterController and exposes a thin
// ObservableObject surface so Settings can bind to update availability.
//
// SETUP STATUS:
//   ✓ Step 1 — Sparkle 2.x added via SPM (File → Add Package Dependencies)
//               URL: https://github.com/sparkle-project/Sparkle
//               Version requirement: Up to Next Major, from 2.0.0
//   ✓ Step 2 — EdDSA keys generated; public key in Info.plist → SUPublicEDKey;
//               private key saved to macOS Keychain by generate_keys automatically.
//               To regenerate keys (if lost):
//               ~/...DerivedData/.../SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
//   ✓ Step 3 — SUFeedURL in Info.plist points to GitHub raw appcast.xml
//   ✓ Step 4 — SUPublicEDKey in Info.plist matches Keychain-stored private key
//   ○ Step 5 — After each release, sign the notarized DMG and update appcast.xml:
//
//   RELEASE WORKFLOW (run once per version):
//   1. Build archive:
//      xcodebuild archive \
//        -project "Cache Out.xcodeproj" \
//        -scheme "Cache Out" \
//        -configuration Release \
//        -archivePath build/CacheOut.xcarchive
//
//   2. Export + sign (fill YOUR_TEAM_ID in exportOptions.plist first):
//      xcodebuild -exportArchive \
//        -archivePath build/CacheOut.xcarchive \
//        -exportPath build/export \
//        -exportOptionsPlist exportOptions.plist
//
//   3. Notarize the .app:
//      xcrun notarytool submit "build/export/Cache Out.app" \
//        --apple-id "your@apple.id" \
//        --team-id "YOUR_TEAM_ID" \
//        --password "@keychain:AC_PASSWORD" \
//        --wait
//
//   4. Staple the .app:
//      xcrun stapler staple "build/export/Cache Out.app"
//
//   5. Create DMG (requires: brew install create-dmg):
//      create-dmg \
//        --volname "Cache Out" \
//        --window-size 540 380 \
//        --icon-size 128 \
//        --app-drop-link 380 185 \
//        "CacheOut-1.0.0.dmg" \
//        "build/export/Cache Out.app"
//
//   6. Sign the DMG with Developer ID:
//      codesign --sign "Developer ID Application: YOUR NAME (YOUR_TEAM_ID)" \
//        CacheOut-1.0.0.dmg
//
//   7. Notarize the DMG:
//      xcrun notarytool submit CacheOut-1.0.0.dmg \
//        --apple-id "your@apple.id" \
//        --team-id "YOUR_TEAM_ID" \
//        --password "@keychain:AC_PASSWORD" \
//        --wait
//
//   8. Staple the DMG:
//      xcrun stapler staple CacheOut-1.0.0.dmg
//
//   9. Sign with Sparkle (private key read from Keychain automatically):
//      ~/Library/Developer/Xcode/DerivedData/Cache_Out-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
//        CacheOut-1.0.0.dmg
//      → Output looks like:
//        sparkle:edSignature="ABC123..." length="12345678"
//      → Paste edSignature + length into appcast.xml → commit → push to main.
//
//   VERIFYING THE SETUP:
//   To confirm Sparkle can find and verify updates before releasing:
//   1. Build and run a Debug build.
//   2. In the app menu → "Check for Updates…"
//   3. If Sparkle finds the update: edSignature is correct, feed URL is reachable.
//   4. If Sparkle shows "up to date": the appcast.xml version == CFBundleVersion.
//      Bump sparkle:version in appcast.xml to a higher integer to force an update check.

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
        isCheckingForUpdates = true
        isUpToDate = false
        pendingUpdateVersion = nil
        controller.checkForUpdates(nil)
    }

    /// Whether the menu item / button should be enabled.
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
}

// MARK: — Minimal Sparkle delegate
private final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    var onDidFindValidUpdate:   ((String) -> Void)?
    var onDidFinishUpdateCycle: (() -> Void)?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onDidFindValidUpdate?(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater,
                 didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: (any Error)?) {
        onDidFinishUpdateCycle?()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { }
}

#else

// MARK: — Stub (active until Sparkle SPM is added)
@MainActor
final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()

    @Published private(set) var isCheckingForUpdates     = false
    @Published private(set) var isUpToDate               = false
    @Published private(set) var pendingUpdateVersion: String? = nil

    var canCheckForUpdates: Bool { false }
    private init() { }

    func checkForUpdates() { }
}
#endif

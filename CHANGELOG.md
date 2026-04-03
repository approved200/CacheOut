# Changelog

All notable changes to Cache Out will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Cache Out uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed
- `DuplicatesViewModel`: added `cancelScan()` and Cancel button — long scans on large drives no longer block indefinitely with no way to stop
- `AnalyzeViewModel`: replaced false FDA permission proxy with proper URL-API TCC probe — permission screen no longer appears incorrectly on machines with empty Caches dir
- `AnalyzeViewModel`: removed all per-level caps on drill-down — previously capped at 20 items when drilled in; now unlimited at all depths to match DaisyDisk (a folder with 91 children would show only 20)
- `DiskScanner`: limit 0 now means unlimited at all levels, not just volume root
- `APFSSnapshotViewModel.run()`: replaced `terminationHandler` pipe-read pattern (deadlock-prone on large output) with correct drain-before-wait pattern
- `MoleOutputParser`: removed unnecessary `nonisolated(unsafe)` on `NSRegularExpression` — was generating Swift 6 compiler warning
- `TreemapView`: replaced `row.last!` force-unwrap with safe `row.last?.size ?? 0`
- `SettingsView`: fixed `Expected ',' separator` compile error caused by curly quotes in a Swift string literal
- `SettingsView`: `Reset all settings` now clears all 18 keys including `debugLogging`, `hasCompletedOnboarding`, `hasSeenTour`; also resets `NSApp.appearance` immediately
- `SettingsView`: replaced force-unwrapped `URL(string:...)!` GitHub link with safe `if let`
- `Info.plist`: added `CFBundleDisplayName` ("Cache Out") and `LSApplicationCategoryType` ("public.app-category.utilities")
- `AccentColor.colorset`: added missing `Contents.json` — colorset folder had no descriptor, making it malformed
- `AppIcon/Contents.json`: fixed "unassigned children / unknown platform" actool warnings by switching to `"idiom": "universal", "platform": "ios"` for light/dark/tinted variants; confirmed zero warnings with actool 26.3 (build 24506)
- `project.pbxproj`: resolved Xcode "Update to recommended settings" warning by adding `ENABLE_USER_SCRIPT_SANDBOXING = YES`, `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `ENABLE_STRICT_OBJC_MSGSEND = YES` to project-level Debug/Release configs; bumped `LastUpgradeCheck` and `LastSwiftUpdateCheck` to `2630`
- Bundled `mole` updated V1.31.0 → V1.33.0 (2026-04-02)

### Added
- `.gitignore` — prevents `Logs/`, `DerivedData/`, `.DS_Store`, DMG files, Sparkle private key from being committed
- `validate_placeholders.sh` — pre-archive guard; fails build if `YOUR_TEAM_ID` or Sparkle placeholders are unfilled
- `.github/workflows/build.yml` — CI: builds and runs tests on every push/PR
- `CONTRIBUTING.md` — contributor guide
- `SECURITY.md` — vulnerability disclosure policy + documented safety boundaries
- `DESIGN.md` — full design system: colors, typography, spacing, component patterns, accessibility, screenshot spec

---

## [1.0.0] — 2026-03-25

### Added
- **Clean** tab: scans caches, logs, browser data, dev caches (Xcode DerivedData, npm, pip, Cargo, Gradle, CocoaPods, Go modules). Dynamic discovery finds any app cache >10 MB.
- **Uninstall** tab: fully removes apps and all remnants. Supports drag-and-drop from Finder.
- **Leftovers** tab: finds orphaned support files in `~/Library` from already-deleted apps. 10 MB floor, nothing pre-selected, explicit warning banner.
- **Analyze** tab: full-volume disk treemap with unlimited drill-down, volume picker, per-item Trash.
- **Large Files** tab: files over 100 MB sorted by size, with age and category filtering. Capped at 500 results with truncation notice.
- **Duplicates** tab: two-pass SHA-256 finder. Partial hash (64 KB) then full hash. Streaming 4 MB chunks prevents OOM. Cancellable.
- **Snapshots** tab: lists and deletes local APFS/Time Machine snapshots, shows purgeable space.
- **Dev Purge** tab: clears `node_modules`, `DerivedData`, `.gradle`, `Pods`, `venv`, `.next`, `.nuxt`, `target`, `build`. Recent projects auto-deselected.
- **Startup** tab: view and toggle/remove launch agents and login items.
- **Status** tab: live CPU, memory, disk, battery, network throughput, health score, top-process Force Quit.
- Menu bar popover, Sparkle 2.x OTA updates, onboarding + feature tour, background scan scheduler, dry-run mode, whitelist, Full Disk Access prompt.
- macOS 26 Tahoe Liquid Glass design throughout.
- Bundled `mole` CLI (no Homebrew required).
- `PrivacyInfo.xcprivacy` with all required API access reasons.

[Unreleased]: https://github.com/apoorv/cache-out/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/apoorv/cache-out/releases/tag/v1.0.0

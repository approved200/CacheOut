# Cache Out

> Free, open-source, native macOS cleaner — built for people who are tired of paying for three apps to do one job.

![macOS](https://img.shields.io/badge/macOS-26%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Tests](https://img.shields.io/badge/tests-passing-brightgreen)

---

## Screenshots

### Light mode

| Clean | Uninstall | Leftovers |
|:---:|:---:|:---:|
| ![Clean](screenshots/Light%20Mode/clean-light.png) | ![Uninstall](screenshots/Light%20Mode/uninstall-light.png) | ![Leftovers](screenshots/Light%20Mode/leftovers-light.png) |

| Analyze | Dev Purge | Duplicates |
|:---:|:---:|:---:|
| ![Analyze](screenshots/Light%20Mode/analyze-light.png) | ![Dev Purge](screenshots/Light%20Mode/dev%20purge-light.png) | ![Duplicates](screenshots/Light%20Mode/duplicates-light.png) |

| Large Files | Snapshots | Startup | Status |
|:---:|:---:|:---:|:---:|
| ![Large Files](screenshots/Light%20Mode/large%20files-light.png) | ![Snapshots](screenshots/Light%20Mode/snapshots-light.png) | ![Startup](screenshots/Light%20Mode/startup-light.png) | ![Status](screenshots/Light%20Mode/status-light.png) |

### Dark mode

| Clean | Uninstall | Leftovers |
|:---:|:---:|:---:|
| ![Clean](screenshots/Dark%20Mode/clean-dark.png) | ![Uninstall](screenshots/Dark%20Mode/uninstall-dark.png) | ![Leftovers](screenshots/Dark%20Mode/leftovers-dark.png) |

| Analyze | Dev Purge | Duplicates |
|:---:|:---:|:---:|
| ![Analyze](screenshots/Dark%20Mode/analyze-dark.png) | ![Dev Purge](screenshots/Dark%20Mode/dev%20purge-dark.png) | ![Duplicates](screenshots/Dark%20Mode/duplicates-dark.png) |

| Large Files | Snapshots | Startup | Status |
|:---:|:---:|:---:|:---:|
| ![Large Files](screenshots/Dark%20Mode/large%20files-dark.png) | ![Snapshots](screenshots/Dark%20Mode/snapshots-dark.png) | ![Startup](screenshots/Dark%20Mode/startup-dark.png) | ![Status](screenshots/Dark%20Mode/status-dark.png) |

---

## Why Cache Out exists

Three paid apps currently own the Mac cleaning space:

- **CleanMyMac** ($65.40/year) — cleans caches and manages apps
- **DaisyDisk** ($10 one-time) — visualises disk usage
- **AppCleaner** (free, but closed-source) — removes apps and remnants

None of them do everything. You need all three for full coverage, and two of them cost money. Cache Out replaces all three with a single free, open-source app — and adds features none of them have.

---

## How Cache Out compares

| Feature | CleanMyMac | DaisyDisk | AppCleaner | **Cache Out** |
|---|:---:|:---:|:---:|:---:|
| Cache & junk scan | ✅ | ❌ | ❌ | ✅ |
| Browser cache cleanup | ✅ | ❌ | ❌ | ✅ |
| App uninstall + all remnants | ✅ | ❌ | ✅ | ✅ |
| Drag-and-drop app uninstall | ❌ | ❌ | ✅ | ✅ |
| Full-volume disk treemap | ❌ | ✅ | ❌ | ✅ |
| APFS snapshot manager | ✅ | ✅ | ❌ | ✅ |
| Large file finder | ✅ | ✅ | ❌ | ✅ |
| Duplicate file finder (SHA-256) | ✅ | ❌ | ❌ | ✅ |
| Startup item manager | ✅ | ❌ | ❌ | ✅ |
| Live CPU / memory / disk status | ✅ | ❌ | ❌ | ✅ |
| Orphaned support file scanner | ✅ | ❌ | ✅ | ✅ |
| iOS backup cleanup | ✅ | ❌ | ❌ | ✅ |
| **Dev artifact purge** | ❌ | ❌ | ❌ | ✅ **exclusive** |
| Free | ❌ | ❌ | ✅ | ✅ |
| Open source | ❌ | ❌ | ❌ | ✅ |

The one feature nobody else has: **Dev Purge**. Cache Out scans your project directories and removes `node_modules`, `DerivedData`, `.gradle`, `Pods`, `venv`, `.next`, `.nuxt`, `target`, and `build` folders across every project at once — with recent projects auto-protected so you never accidentally nuke active work.

---

## What it does

| Tab | What it does |
|---|---|
| **Clean** | Removes caches, logs, browser data, and app junk. Scans `~/Library/Caches`, dev tool caches (npm, pip, Cargo, Gradle, CocoaPods), and dynamically discovers any app cache over 10 MB |
| **Uninstall** | Fully removes apps and every file they left behind — caches, containers, preferences, support files, and launch agents. Drag an app from Finder or pick from the list |
| **Leftovers** | Finds support files in `~/Library` left behind by apps you already deleted |
| **Large Files** | Lists every file over 100 MB in your home folder, sorted by size, with file age |
| **Duplicates** | Two-pass SHA-256 duplicate finder across your project folders. Streams 4 MB chunks so even 4 GB video files don't OOM |
| **Analyze** | Full-volume treemap of disk usage with drill-down, volume picker, and per-item Trash |
| **Snapshots** | Lists and deletes local Time Machine snapshots. Shows purgeable space held by APFS |
| **Dev Purge** | Clears `node_modules`, `DerivedData`, `.gradle`, `Pods`, `venv`, `.next`, `.nuxt`, `target`, `build` across all projects. Recent projects auto-deselected |
| **Startup** | View and manage launch agents and login items. Toggle or remove user agents in one click |
| **Status** | Live CPU, memory, disk, battery, and network — plus a health score and top-process Force Quit |

---

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 16 or later
- Full Disk Access (prompted on first launch)

The bundled `mo` CLI is included — no Homebrew install needed.

---

## Download

**[⬇ Download Cache Out 1.0.0 for macOS](https://github.com/approved200/CacheOut/releases/latest)**

Requires macOS 26 (Tahoe) or later.

1. Download `CacheOut-1.0.0.dmg` from the [latest release](https://github.com/approved200/CacheOut/releases/latest)
2. Open the DMG and drag **Cache Out** to your Applications folder
3. On first launch, go to **System Settings → Privacy & Security → Full Disk Access** and enable Cache Out

> The app is notarized by Apple and safe to open. If macOS shows a warning on first launch, right-click the app and choose Open.

---

## Build from source

```bash
git clone https://github.com/approved200/CacheOut
cd "Cache Out"
bash setup-hooks.sh             # install git hooks (one-time)
python3 generate_xcodeproj.py
open "Cache Out.xcodeproj"
```

Then in Xcode: select the **Cache Out** scheme → set your Team under Signing & Capabilities → ⌘R.

---

## Running tests

```bash
# In Xcode: select the CacheOutTests scheme → ⌘U
# Or from the command line:
xcodebuild test \
  -project "Cache Out.xcodeproj" \
  -scheme CacheOutTests \
  -destination "platform=macOS"
```

The test suite covers: formatters and edge cases, whitelist size filtering (BUG-03 regression),
clean/purge dry-run safety, selection isolation, duplicate grouping and SHA-256 logic,
PurgeScanner artifact detection and nesting, StartupScanner plist parsing, SystemMonitor
derived computations, ViewModel state management, FileCategory classification, error handling
for all scanner paths, MVVM architecture assertions, and concurrency-safety checks.

---

## Project scripts

| Script | Purpose | When to run |
|---|---|---|
| `generate_xcodeproj.py` | Regenerates `project.pbxproj` deterministically | After adding or removing any `.swift` file |
| `validate_placeholders.sh` | Blocks archive if Sparkle keys or Team ID are unfilled | Wire into Xcode Build Phases → New Run Script Phase, drag above "Sign Binary With Entitlements", enable "For install builds only" |

---

## Permissions

Cache Out requires **Full Disk Access** to scan all cache folders:

> System Settings → Privacy & Security → Full Disk Access → Cache Out ✓

The app requests this on first launch. Without it, some paths under `~/Library` are invisible to the scanner and a permission-denied screen is shown with a direct link to System Settings.

---

## Design

Cache Out targets **macOS 26 Tahoe** with Apple's Liquid Glass design language:

- `NavigationSplitView` + `.listStyle(.sidebar)` → automatic Liquid Glass sidebar
- All animations use `.spring(response: 0.35, dampingFraction: 0.8)`
- Only semantic Apple colors — zero hardcoded hex values
- SF Pro for UI text, SF Mono for paths and sizes
- Sentence case throughout
- Respects `accessibilityReduceMotion`, Increase Contrast, dark/light mode, Dynamic Type (`@ScaledMetric` on every view)

See [DESIGN.md](DESIGN.md) for the full design system.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘1` – `⌘0` | Jump to tab |
| `⌘R` | Scan / rescan current tab |
| `⌘,` | Settings |
| `⌘W` | Close window |
| `⌘Q` | Quit |

---

## Special thanks

Cache Out wouldn't be possible without **[Mole](https://github.com/tw93/mole)** (`mo`), a fast, open-source CLI tool by [@tw93](https://github.com/tw93) for cleaning dev artifacts, running purges, and inspecting system state from the terminal.

Mole handles the heavy lifting on the Dev Purge tab — Cache Out wraps it via `MoleService` and exposes its power through a native macOS UI. If you spend time in the terminal, `mo` is worth having on its own.

```bash
brew install tw93/tap/mole
```

---

## Project structure

```
Cache Out/
├── generate_xcodeproj.py          ← run after any .swift add/remove
├── setup-hooks.sh                 ← installs git hooks (run once after clone)
├── hooks/pre-commit               ← auto-runs generate_xcodeproj.py on commit
├── validate_placeholders.sh       ← pre-archive guard (wire into Build Phases)
├── exportOptions.plist            ← notarization workflow (fill YOUR_TEAM_ID)
├── appcast.xml                    ← Sparkle update feed (fill after first DMG)
├── screenshots/                   ← light + dark PNG for README
├── Cache Out.xcodeproj/
├── CacheOut/
│   ├── CacheOutApp.swift          ← @main, AppDelegate, NSStatusItem
│   ├── ContentView.swift          ← NavigationSplitView, 9 ViewModels, toolbar
│   ├── Info.plist
│   ├── CacheOut.entitlements
│   ├── PrivacyInfo.xcprivacy
│   ├── Models/Models.swift
│   ├── Resources/mole-src/        ← bundled mo CLI
│   ├── Services/
│   │   ├── AppScanner.swift
│   │   ├── BackgroundCleanScheduler.swift
│   │   ├── DiskScanner.swift
│   │   ├── DuplicateScanner.swift
│   │   ├── MoleService.swift      ← Dev Purge only; wraps mo CLI
│   │   ├── MoleUpdateService.swift
│   │   ├── SparkleUpdater.swift   ← full 9-step release workflow inside
│   │   ├── StartupScanner.swift
│   │   └── SystemMonitor.swift
│   ├── ViewModels/                ← one ViewModel per tab
│   ├── Views/                     ← one folder per tab
│   └── Utilities/
│       ├── CacheOutLogger.swift
│       ├── Formatters.swift
│       ├── LaunchAtLogin.swift
│       └── SidebarLogger.swift    ← debug only (#if DEBUG)
└── CacheOutTests/
    ├── AppScannerTests.swift      ← directorySize, system-path exclusion
    ├── CacheOutTests.swift        ← formatters, relativeDaysAgo, Int.nonZero
    ├── CleanViewModelTests.swift  ← whitelist filtering, BUG-01/03 regressions
    ├── DuplicateScannerTests.swift← SHA-256 grouping logic
    ├── ErrorHandlingTests.swift   ← error paths, MVVM architecture, concurrency
    ├── IntegrationTests.swift     ← dry-run safety, selection isolation
    ├── PurgeViewModelTests.swift  ← scan root discovery, artifact detection
    ├── StartupScannerTests.swift  ← plist parsing, StartupSource raw values
    ├── SystemMonitorTests.swift   ← health score, CPU/memory/disk bounds
    └── ViewModelTests.swift       ← AnalyzeVM, APFSSnapshotVM, DuplicatesVM,
                                      LargeFilesVM, OrphanedAppsVM, PurgeVM,
                                      StartupVM, FileCategory, whitelist normalisation
```

---

## Release checklist

Before tagging a release:

1. Fill in `YOUR_TEAM_ID` in `exportOptions.plist`
2. Run the 9-step notarization workflow documented in `SparkleUpdater.swift`
3. Run `sign_update CacheOut-x.x.x.dmg` → paste `edSignature` + byte size into `appcast.xml`
4. Push `appcast.xml` to `main` so Sparkle can find the update
5. Tag the release: `git tag v1.x.x && git push --tags`

---

## License

MIT

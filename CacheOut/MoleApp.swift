import SwiftUI

@main
struct CacheOutApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenTour")            private var hasSeenTour = false

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // MARK: — Main window
        WindowGroup {
            if hasCompletedOnboarding {
                // Tour overlay is managed inside ContentView itself — it reads
                // showTourOnLaunch from AppStorage and shows AppTourOverlay directly
                // over the NavigationSplitView so the real app chrome is visible.
                ContentView()
                    .frame(minWidth: 700, idealWidth: 900,
                           minHeight: 500, idealHeight: 620)
                    .background(WindowAccessor())
            } else {
                OnboardingView()
                    .background(WindowAccessor())
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Cache Out") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                Button("Check for Updates…") {
                    SparkleUpdater.shared.checkForUpdates()
                }
                .disabled(!SparkleUpdater.shared.canCheckForUpdates)
                Divider()
            }
            CommandGroup(after: .appInfo) {
                Button("Scan Now") {
                    NotificationCenter.default.post(name: .triggerScan, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Navigate") {
                ForEach(NavItem.allCases, id: \.self) { tab in
                    Button(tab.rawValue) {
                        NotificationCenter.default.post(name: .switchTab, object: tab)
                    }
                    .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                }
            }
        }

        // MARK: — Settings (Cmd+,)
        Settings {
            SettingsView()
        }
        // NOTE: No MenuBarExtra scene — the status item is managed by AppDelegate
        // so it can be added/removed when the user toggles "Show in menu bar".
    }
}

// MARK: — AppDelegate
// Owns the NSStatusItem (menu bar icon + popover) so it can be truly added and
// removed at runtime when the user toggles "Show in menu bar" in Settings.
// Also boots NSBackgroundActivityScheduler for periodic background scans.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Status item + popover
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // Register UserDefaults defaults early so all bool(forKey:) reads on launch
    // return the correct defaults rather than false/0.
    override init() {
        super.init()
        // Register UserDefaults defaults so first-launch reads are correct.
        // Without this, bool(forKey: "showMenuBar") returns false on a clean install
        // and the menu bar icon never appears.
        UserDefaults.standard.register(defaults: [
            // General
            "showMenuBar":         true,
            "notifyOnComplete":    true,
            "scanOnLaunch":        false,
            "unusedAppDays":       90,
            "appearanceMode":      0,
            "showTourOnLaunch":    false,
            // Onboarding
            "hasCompletedOnboarding": false,
            "hasSeenTour":            false,
            // Cleaning
            "autoCleanSchedule":   0,
            "cleanWhitelist":      "",
            // Dev Purge
            "purgeSkipRecentDays": 7,
            "purgeScanDirs":       "",
            // Advanced
            "dryRunMode":          false,
            // Duplicates
            "duplicatesMinSizeKB":    1024,
            "duplicatesExcludedDirs": "",
            // Large files
            "largeFilesMinSizeKB":    102_400,
            "largeFilesExcludedDirs": "",
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyMenuBarVisibility()
        applyStoredAppearance()
        Task { @MainActor in BackgroundCleanScheduler.shared.scheduleIfNeeded() }
        // Boot Sparkle — starts automatic update check per SUEnableAutomaticChecks in Info.plist
        _ = SparkleUpdater.shared

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarVisibilityChanged(_:)),
            name: .menuBarVisibilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleChanged),
            name: .autoCleanScheduleChanged,
            object: nil
        )
    }

    // MARK: — Appearance

    /// Restores the user's saved color scheme on launch.
    /// 0 = system (nil), 1 = light (.aqua), 2 = dark (.darkAqua).
    func applyStoredAppearance() {
        let mode = UserDefaults.standard.integer(forKey: "appearanceMode")
        let appearance: NSAppearance? = switch mode {
        case 1:  NSAppearance(named: .aqua)
        case 2:  NSAppearance(named: .darkAqua)
        default: nil
        }
        NSApp.appearance = appearance
    }

    // MARK: — Menu bar show/hide

    @objc private func menuBarVisibilityChanged(_ note: Notification) {
        applyMenuBarVisibility()
    }

    /// Adds or removes the NSStatusItem based on the current UserDefaults value.
    func applyMenuBarVisibility() {
        let show = UserDefaults.standard.bool(forKey: "showMenuBar")
        if show {
            guard statusItem == nil else { return }   // already visible
            addStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func addStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                   accessibilityDescription: "Cache Out")
            button.image?.isTemplate = true   // adapts to light/dark menu bar automatically
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        // Build the popover that hosts MenuBarPopover (a SwiftUI view)
        let pop = NSPopover()
        pop.contentSize  = NSSize(width: 280, height: 240)
        pop.behavior     = .transient          // closes on click outside
        pop.animates     = true
        pop.contentViewController = NSHostingController(rootView: MenuBarPopover())
        popover = pop
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        popover?.close()
        popover = nil
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let pop = popover else { return }
        if pop.isShown {
            pop.performClose(sender)
        } else {
            pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // Bring app to front so the popover receives keyboard events
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Tear down background scheduler so it doesn't fire after quit
        BackgroundCleanScheduler.shared.invalidate()
        // Remove notification observers explicitly (good practice, even though
        // AppDelegate lives for the app's lifetime)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: — Background schedule

    @objc private func scheduleChanged() {
        Task { @MainActor in BackgroundCleanScheduler.shared.scheduleIfNeeded() }
    }
}

extension Notification.Name {
    static let triggerScan              = Notification.Name("com.cacheout.triggerScan")
    static let menuBarVisibilityChanged = Notification.Name("com.cacheout.menuBarVisibility")
    static let autoCleanScheduleChanged = Notification.Name("com.cacheout.autoCleanSchedule")
}

// MARK: — Window configurator
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let win = view.window else { return }
            win.titlebarAppearsTransparent = false
            win.titleVisibility = .visible
            win.setFrameAutosaveName("CacheOutMainWindow")
            win.minSize = NSSize(width: 700, height: 500)
            // macOS 26 Tahoe: do NOT set backgroundColor = .clear or isOpaque = false
            // on the whole window. That bleeds the wallpaper into the detail pane.
            // The sidebar gets its glass treatment automatically from
            // NavigationSplitView on Tahoe — no NSWindow opt-in needed.
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

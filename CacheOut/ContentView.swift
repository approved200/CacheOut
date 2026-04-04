import SwiftUI

enum NavItem: String, Hashable, CaseIterable {
    case clean      = "Clean"
    case uninstall  = "Uninstall"
    case orphaned   = "Leftovers"
    case analyze    = "Analyze"
    case snapshots  = "Snapshots"
    case largeFiles = "Large Files"
    case devPurge   = "Dev Purge"
    case duplicates = "Duplicates"
    case startup    = "Startup"
    case status     = "Status"

    var icon: String {
        switch self {
        case .clean:      return "sparkles"
        case .uninstall:  return "shippingbox"
        case .orphaned:   return "shippingbox.and.arrow.backward"
        case .analyze:    return "chart.pie"
        case .snapshots:  return "clock.arrow.circlepath"
        case .largeFiles: return "doc.zipper"
        case .devPurge:   return "hammer"
        case .duplicates: return "doc.on.doc"
        case .startup:    return "power"
        case .status:     return "gauge.with.dots.needle.33percent"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .clean:      return "1"
        case .uninstall:  return "2"
        case .orphaned:   return "3"
        case .analyze:    return "4"
        case .snapshots:  return "5"
        case .largeFiles: return "6"
        case .devPurge:   return "7"
        case .duplicates: return "8"
        case .startup:    return "9"
        case .status:     return "0"
        }
    }
}

// Shared environment object that lets child views push a CTA label up to the toolbar.
// helpText is shown as a tooltip (.help()) on the toolbar button and as an
// accessibilityHint for VoiceOver — currently used by AnalyzeView to surface
// the full path of the folder that "Open in Finder" will reveal.
class ToolbarCTAState: ObservableObject {
    @Published var label: String    = ""
    @Published var isEnabled: Bool  = false
    @Published var helpText: String = ""
    @Published var action: (() -> Void)?
}

struct ContentView: View {
    @State private var selectedTab: NavItem = .clean
    @State private var diskFreeBytes: UInt64 = 0

    // Tour overlay state — owned here so SidebarView gets highlightedTab
    @AppStorage("showTourOnLaunch") private var showTourOnLaunch = false
    @State private var showingTour    = false
    @State private var highlightedTab : NavItem? = nil

    /// A Binding<NavItem?> for the sidebar List that never allows nil to be committed.
    /// When NavigationSplitView tries to clear the selection (writes nil), we ignore
    /// it and keep the current selectedTab — sidebar stays highlighted.
    private var safeTabBinding: Binding<NavItem?> {
        Binding<NavItem?>(
            get: { self.selectedTab },
            set: { newVal in
                if let val = newVal { self.selectedTab = val }
                // nil write → silently ignored, selection stays where it is
            }
        )
    }
    @StateObject private var ctaState = ToolbarCTAState()

    // ViewModels live here — survive tab switches, never recreated
    @StateObject private var cleanVM        = CleanViewModel()
    @StateObject private var uninstallVM    = UninstallViewModel()
    @StateObject private var purgeVM        = PurgeViewModel()
    @StateObject private var analyzeVM      = AnalyzeViewModel()
    @StateObject private var startupVM      = StartupViewModel()
    @StateObject private var duplicatesVM   = DuplicatesViewModel()
    @StateObject private var largeFilesVM   = LargeFilesViewModel()
    @StateObject private var orphanedVM     = OrphanedAppsViewModel()
    @StateObject private var snapshotVM     = APFSSnapshotViewModel()
    // SystemMonitor lives here — NOT in StatusView — so the timer survives tab
    // switches. StatusView uses .id(selectedTab) which destroys/recreates child
    // views; owning the monitor here gives it the same lifetime as all other VMs.
    @StateObject private var systemMonitor  = SystemMonitor()

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(selection: safeTabBinding)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
            } detail: {
            // The detail column has NO glass effect — like Finder's right pane,
            // it is a solid opaque surface. Glass lives only on the sidebar and
            // toolbar, which NavigationSplitView applies automatically on macOS 26.
            VStack(spacing: 0) {
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Status bar lives INSIDE the detail column so it:
                // (a) only spans the content area, not the sidebar
                // (b) clips correctly to the window's bottom-right corner radius
                bottomStatusBar
            }
            // Give each tab a distinct identity so NavigationSplitView performs
            // a clean replace rather than diffing between detail views — prevents
            // the sidebar collapse caused by rapid structural changes during
            // column transitions (macOS 26 NavigationSplitView bug).
            .id(selectedTab)
            .navigationTitle("Cache Out")
            .toolbar { toolbarContent }
            // Full-screen: macOS floats the toolbar as a glass overlay and
            // ScrollView content drifts behind it. Keeping the toolbar opaque
            // in full-screen mode matches windowed behaviour — the Liquid Glass
            // effect stays on the sidebar, not the toolbar.
            // Both APIs are kept for forward/back compatibility across Tahoe betas.
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        }
        .environmentObject(ctaState)
        .task { diskFreeBytes = readDiskFree() }
        .onChange(of: selectedTab) { oldVal, newVal in
            SidebarLogger.log("ContentView.selectedTab changed: \(oldVal) → \(newVal)")
        }
        .task {
            BackgroundCleanScheduler.shared.scanVM = cleanVM
        }
        .onReceive(NotificationCenter.default.publisher(for: .diskFreed)) { _ in
            diskFreeBytes = readDiskFree()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { note in
            if let tab = note.object as? NavItem { selectedTab = tab }
        }
        .onAppear {
            if showTourOnLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showingTour = true
                }
            }
        }
        // When the tour moves to a new step, drive the real sidebar selection so the
        // List renders its native filled-blue-capsule highlight — no custom drawing.
        .onChange(of: highlightedTab) { _, newTab in
            if let tab = newTab { selectedTab = tab }
        }
        // Tour overlay — lives inside the ZStack wrapping NavigationSplitView
        // so it covers the full window chrome and the real app is visible behind.
        if showingTour {
            AppTourOverlay(isShowing: $showingTour, highlightedTab: $highlightedTab)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showingTour)
        }
        } // end ZStack
    } // end body

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .clean:
            CleanView(viewModel: cleanVM)
        case .uninstall:
            UninstallView(viewModel: uninstallVM)
        case .orphaned:
            OrphanedAppsView(viewModel: orphanedVM)
        case .analyze:
            AnalyzeView(viewModel: analyzeVM)
        case .snapshots:
            APFSSnapshotView(viewModel: snapshotVM)
        case .largeFiles:
            LargeFilesView(viewModel: largeFilesVM)
        case .devPurge:
            PurgeView(viewModel: purgeVM)
        case .duplicates:
            DuplicatesView(viewModel: duplicatesVM)
        case .startup:
            StartupView(viewModel: startupVM)
        case .status:
            StatusView(monitor: systemMonitor)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Scan button — always visible, left of CTA
        ToolbarItem(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .triggerScan, object: nil)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Scan (⌘R)")
        }

        // Dynamic CTA — only shown when a child view pushes a label
        ToolbarItem(placement: .primaryAction) {
            if !ctaState.label.isEmpty {
                Button(ctaState.label) {
                    ctaState.action?()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(!ctaState.isEnabled)
                .help(ctaState.helpText)
                .accessibilityHint(ctaState.helpText)
            }
        }
    }

    private var bottomStatusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(formatBytes(Int64(diskFreeBytes)) + " available")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 22)
            // Solid window background — no material bleed.
            // Matches Finder's bottom bar: opaque, same color as the content area.
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func readDiskFree() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemFreeSize] as? UInt64) ?? 0
    }
}

extension Notification.Name {
    static let switchTab  = Notification.Name("com.cacheout.switchTab")
    static let diskFreed  = Notification.Name("com.cacheout.diskFreed")
}

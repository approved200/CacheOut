import SwiftUI

// MARK: — Tour step model
// Each step maps to a NavItem so the sidebar can highlight it live.
struct TourStep {
    let navItem    : NavItem?   // nil = no highlight (intro / outro)
    let icon       : String
    let iconColor  : Color
    let title      : String
    let body       : String
    let detail     : String
}

// NOTE: Keep in sync with NavItem cases in ContentView.swift.
let tourSteps: [TourStep] = [
    TourStep(navItem: nil,
             icon: "sparkles", iconColor: .purple,
             title: "Welcome to Cache Out",
             body: "A free, open-source replacement for CleanMyMac, DaisyDisk, and AppCleaner.",
             detail: "Let's walk through each tool in 30 seconds."),

    TourStep(navItem: .clean,
             icon: "sparkles", iconColor: .purple,
             title: "Clean",
             body: "Scans caches, logs, browser data, and build artifacts. Frees space in seconds.",
             detail: "Everything moves to Trash — always recoverable."),

    TourStep(navItem: .uninstall,
             icon: "shippingbox", iconColor: .blue,
             title: "Uninstall",
             body: "Removes an app and every file it left behind: caches, containers, prefs, and launch agents.",
             detail: "Drag an app from Finder or pick from the list."),

    TourStep(navItem: .orphaned,
             icon: "shippingbox.and.arrow.backward", iconColor: .indigo,
             title: "Leftovers",
             body: "Finds support files and caches left behind by apps you already deleted.",
             detail: "Nothing is pre-selected — review each item before removing."),

    TourStep(navItem: .largeFiles,
             icon: "doc.zipper", iconColor: .teal,
             title: "Large Files",
             body: "Lists every file over 100 MB in your home folder, sorted by size with age shown.",
             detail: "Right-click any row to reveal in Finder or move to Trash."),

    TourStep(navItem: .duplicates,
             icon: "doc.on.doc", iconColor: .pink,
             title: "Duplicates",
             body: "Two-pass SHA-256 scanning finds identical files across your project folders.",
             detail: "The oldest copy in each group is suggested for removal."),

    TourStep(navItem: .analyze,
             icon: "chart.pie", iconColor: .orange,
             title: "Analyze",
             body: "An interactive treemap shows exactly which folders are eating your disk.",
             detail: "Works across all mounted volumes. Drill in to any folder."),

    TourStep(navItem: .snapshots,
             icon: "clock.arrow.circlepath", iconColor: .cyan,
             title: "Snapshots",
             body: "Lists local Time Machine snapshots and the purgeable space they hold.",
             detail: "Safe to delete — off-site backups are unaffected."),

    TourStep(navItem: .devPurge,
             icon: "hammer", iconColor: .green,
             title: "Dev Purge",
             body: "Finds node_modules, DerivedData, .gradle, Pods, venv, .next, and more across your whole Mac.",
             detail: "Projects touched within your protection window are auto-deselected."),

    TourStep(navItem: .startup,
             icon: "power", iconColor: .yellow,
             title: "Startup",
             body: "See every launch agent and login item. Toggle or remove user agents in one click.",
             detail: "System agents are read-only. SMAppService items deep-link to System Settings."),

    TourStep(navItem: .status,
             icon: "gauge.with.dots.needle.33percent", iconColor: .cyan,
             title: "Status",
             body: "Live CPU, memory, disk, battery, and network — plus a health score and top processes.",
             detail: "Processes eating CPU are highlighted automatically."),
]


// MARK: — In-app overlay tour
// Renders directly over ContentView so the real sidebar and app chrome are
// always visible. Each step highlights the relevant sidebar item with a
// spotlight ring and an anchored callout card.
struct AppTourOverlay: View {
    @Binding var isShowing: Bool
    /// The sidebar item the tour should highlight. Passed in from ContentView
    /// so the tour can drive tab selection without owning that state.
    @Binding var highlightedTab: NavItem?

    @AppStorage("showTourOnLaunch") private var showTourOnLaunch = false
    @State private var currentStep  = 0
    @State private var direction    : Int = 1
    @State private var cardVisible  = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: TourStep { tourSteps[currentStep] }
    private var isLast: Bool   { currentStep == tourSteps.count - 1 }
    private var isFirst: Bool  { currentStep == 0 }

    var body: some View {
        ZStack {
            // ── Scrim ─────────────────────────────────────────────────────
            // Left strip (sidebar width ~200 pt) is lighter so the sidebar
            // labels remain readable; the rest of the window is darker.
            HStack(spacing: 0) {
                // Sidebar strip — subtle tint only
                Color.black.opacity(0.18)
                    .frame(width: 200)
                // Detail pane — heavier scrim
                Color.black.opacity(0.52)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)   // touches fall through to nothing

            // ── Callout card ──────────────────────────────────────────────
            VStack {
                Spacer()
                calloutCard
                    .padding(.bottom, 48)
                    .opacity(cardVisible ? 1 : 0)
                    .offset(y: cardVisible ? 0 : 20)
            }
            .animation(
                reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82),
                value: cardVisible
            )
        }
        .onAppear {
            highlightedTab = step.navItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { cardVisible = true }
        }
        .onChange(of: currentStep) { _, _ in
            // Flash card out → update tab → flash card in
            withAnimation(.easeIn(duration: 0.12)) { cardVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                highlightedTab = step.navItem
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    cardVisible = true
                }
            }
        }
    }

    // MARK: — Callout card
    private var calloutCard: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(step.iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: step.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(step.iconColor)
                        .symbolRenderingMode(.hierarchical)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(step.body)
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)


            // Detail line
            if !step.detail.isEmpty {
                Text(step.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 76)   // indent under icon
                    .padding(.top, 6)
            }

            Divider().padding(.top, 14)

            // Progress dots + navigation
            HStack(spacing: 0) {
                // ← Back
                Button {
                    direction = -1
                    currentStep -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .opacity(isFirst ? 0.25 : 1)
                .disabled(isFirst)

                Spacer()

                // Dots
                HStack(spacing: 7) {
                    ForEach(tourSteps.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == currentStep
                                  ? Color.accentColor
                                  : Color(nsColor: .separatorColor))
                            .frame(width: i == currentStep ? 16 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7),
                                       value: currentStep)
                    }
                }

                Spacer()

                // → Next / Done
                if isLast {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.return, modifiers: [])
                } else {
                    Button {
                        direction = 1
                        currentStep += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // "Don't show again" checkbox
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get:  { !showTourOnLaunch },
                    set:  { showTourOnLaunch = !$0 }
                )) {
                    Text("Don't show on next launch")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                .toggleStyle(.checkbox)
                Spacer()
                Button("Close tour") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Material.regular)
                .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .frame(maxWidth: 380)
        .padding(.horizontal, 220)  // push card into detail column, clear sidebar
        // Swipe left/right to navigate
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if v.translation.width < -40, !isLast  { direction =  1; currentStep += 1 }
            if v.translation.width >  40, !isFirst { direction = -1; currentStep -= 1 }
        })
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) { cardVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            highlightedTab = nil
            isShowing      = false
        }
    }
}


// MARK: — Standalone FeatureTourView
// Used when opening the tour from Settings → General or from the menu bar.
// Wraps ContentView with the overlay — identical experience to the launch tour.
struct FeatureTourView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showTourOnLaunch") private var showTourOnLaunch = false
    @State private var showTour       = true
    @State private var highlightedTab : NavItem? = nil

    // ViewModels required by ContentView — standalone instances for preview only.
    // When launched from the main window the overlay lives inside ContentView
    // directly, so this wrapper is only used for the Settings sheet path.
    var body: some View {
        ZStack {
            // The real app chrome underneath
            ContentView()
                .allowsHitTesting(false)   // tour is modal
            if showTour {
                AppTourOverlay(isShowing: $showTour, highlightedTab: $highlightedTab)
                    .onChange(of: showTour) { _, showing in
                        if !showing { dismiss() }
                    }
            }
        }
        .frame(width: 900, height: 620)
    }
}

// MARK: — Embedded tour (kept for OnboardingView final step)
// Uses the same AppTourOverlay but wires it to a local state so it can fire
// the onComplete callback when the user finishes or dismisses.
struct EmbeddedTourView: View {
    let onComplete: () -> Void
    @State private var showTour      = true
    @State private var highlighted   : NavItem? = nil

    var body: some View {
        ZStack {
            ContentView()
                .allowsHitTesting(false)
            if showTour {
                AppTourOverlay(isShowing: $showTour, highlightedTab: $highlighted)
                    .onChange(of: showTour) { _, showing in
                        if !showing { onComplete() }
                    }
            }
        }
        .frame(width: 900, height: 620)
    }
}


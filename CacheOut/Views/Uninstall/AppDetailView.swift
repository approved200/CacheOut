import SwiftUI
import AppKit

// Represents one deletable remnant path — owns its own checked state.
private struct Remnant: Identifiable {
    let id        = UUID()
    let title     : String
    let path      : String   // absolute path to delete
    let label     : String   // display-friendly path (may be tilde-abbreviated)
    let size      : Int64
    var checked   : Bool = true
    /// When true, the UI shows a "restart may be needed" warning badge.
    var needsRestart: Bool = false
}

struct AppDetailView: View {
    let selectedApp: AppItem?
    var onUninstalled: ((UUID) -> Void)? = nil

    // Dynamic Type — hero numbers and headings scale with user's font size setting
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title2)     private var titleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body)       private var bodySize: CGFloat = 13

    @State private var isUninstalling = false
    @State private var showConfirm    = false
    @State private var didUninstall   = false
    @State private var uninstallError: String? = nil
    @State private var remnants: [Remnant] = []
    @State private var resolvedSize: Int64 = 0
    @State private var resolvedVersion: String = ""
    /// The actual bytes trashed — set at the moment the user confirms uninstall.
    /// Used in successState so the number reflects what was actually moved, not
    /// the full AppItem total (which includes unchecked remnants).
    @State private var trashedSize: Int64 = 0

    var body: some View {
        Group {
            if let app = selectedApp {
                if didUninstall {
                    successState(app)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    appDetail(app)
                        .transition(.opacity)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: didUninstall)
        .onChange(of: selectedApp?.id) { _, _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                didUninstall   = false
                isUninstalling = false
                uninstallError = nil
                trashedSize    = 0
            }
            remnants = buildRemnants(for: selectedApp)
            resolvedSize    = remnants.reduce(0) { $0 + $1.size }
            resolvedVersion = readVersion(from: selectedApp?.path)
        }
        .onAppear {
            remnants = buildRemnants(for: selectedApp)
            resolvedSize    = remnants.reduce(0) { $0 + $1.size }
            resolvedVersion = readVersion(from: selectedApp?.path)
        }
    }

    // MARK: — App detail: everything in one ScrollView, button at the bottom of content
    private func appDetail(_ app: AppItem) -> some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── App header ──────────────────────────────────────────────
                VStack(spacing: 10) {
                    AppIconView(path: app.path, size: 80)
                        .padding(.top, 36)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                    Text(app.name)
                        .font(.system(size: titleSize, weight: .semibold))

                    // POLISH-03: use resolvedSize (from measured remnants) when the
                    // AppItem was created by drag-and-drop with size=0.
                    let displaySize = app.size > 0 ? app.size : resolvedSize
                    Text(formatBytes(displaySize))
                        .font(.system(size: heroSize, weight: .bold))
                        .monospacedDigit()

                    Text("Total space to free")
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))

                    // POLISH-03: show resolved version when AppItem has placeholder "—"
                    let displayVersion = (app.version == "—" || app.version.isEmpty)
                        ? resolvedVersion : app.version
                    if !displayVersion.isEmpty && displayVersion != "—" {
                        Text("v\(displayVersion)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }

                    // Last used pill
                    if app.lastUsed > Date.distantPast {
                        lastUsedBadge(app)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)

                // ── Remnant breakdown card ──────────────────────────────────
                VStack(spacing: 0) {
                    ForEach($remnants) { $remnant in
                        AppRemnantRow(title: remnant.title,
                                      pathLabel: remnant.label,
                                      size: remnant.size,
                                      needsRestart: remnant.needsRestart,
                                      isChecked: $remnant.checked)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .padding(.horizontal, 24)

                // Error banner
                if let err = uninstallError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(Color(nsColor: .labelColor))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 0.5))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // ── Uninstall button — lives INSIDE the scroll content ──────
                uninstallButton(for: app)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 32)   // generous bottom breathing room

            }
        }
    }

    // MARK: — Last used badge
    private func lastUsedBadge(_ app: AppItem) -> some View {
        let days = Int(Date().timeIntervalSince(app.lastUsed) / 86400)
        let label: String
        let color: Color
        switch days {
        case 0:       label = "Used today";             color = .green
        case 1:       label = "Used yesterday";         color = .green
        case 2...6:   label = "Used \(days) days ago";  color = .secondary
        case 7...30:  label = "Used \(days/7)w ago";    color = .secondary
        case 31...89: label = "Used \(days/30)mo ago";  color = .secondary
        default:      label = "Unused (\(days/30) months)"; color = .red
        }
        return Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color.opacity(0.1))
                    .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
            )
    }

    // MARK: — Uninstall button
    @ViewBuilder
    private func uninstallButton(for app: AppItem) -> some View {
        let checkedSize = remnants.filter(\.checked).reduce(0) { $0 + $1.size }
        let isAppleApp = isAppleInstalledApp(app.path)

        if isAppleApp {
            AppleAppUninstallCard(app: app) {
                // After successful privileged uninstall, dismiss the detail pane
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    didUninstall = true
                    trashedSize  = app.appSize
                }
                if let id = app.id as UUID? {
                    onUninstalled?(id)
                }
            }
        } else if isUninstalling {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Moving to Trash…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Button { showConfirm = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Uninstall \(app.name)")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(remnants.filter(\.checked).isEmpty)
            .confirmationDialog(
                "Move \(app.name) to Trash?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    Task { await performUninstall() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will move \(formatBytes(checkedSize)) of selected files to the Trash. You can recover them if needed.")
            }
        }
    }

    /// Returns true when the app bundle is owned by root — meaning it was
    /// installed by Apple (iMovie, GarageBand, Pages, Numbers, Keynote, etc.)
    /// and cannot be trashed by a user process. Finder handles these via
    /// authentication, but Cache Out runs as the current user without sudo.
    private func isAppleInstalledApp(_ appPath: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: appPath),
              let ownerID = attrs[.ownerAccountID] as? Int else { return false }
        return ownerID == 0   // root uid = 0
    }

    // MARK: — Perform uninstall — only deletes checked remnants
    private func performUninstall() async {
        withAnimation(.easeInOut(duration: 0.2)) { isUninstalling = true }
        uninstallError = nil
        // Capture the actual bytes being trashed NOW — before remnants are cleared.
        // successState reads this value, not app.size (which includes unchecked rows).
        trashedSize = remnants.filter(\.checked).reduce(0) { $0 + $1.size }

        let targets = remnants
            .filter(\.checked)
            .map { URL(fileURLWithPath: $0.path) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !targets.isEmpty else {
            isUninstalling = false
            return
        }

        NSWorkspace.shared.recycle(targets) { trashedURLs, error in
            Task { @MainActor in
                if let error, trashedURLs.isEmpty {
                    withAnimation { self.uninstallError = error.localizedDescription }
                    self.isUninstalling = false
                    return
                }
                self.isUninstalling = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.didUninstall = true
                }
                NotificationCenter.default.post(name: .diskFreed, object: nil)
                if let id = self.selectedApp?.id {
                    self.onUninstalled?(id)
                }
            }
        }
    }

    // MARK: — Build remnant list for a given app
    private func buildRemnants(for app: AppItem?) -> [Remnant] {
        guard let app else { return [] }
        let home = NSHomeDirectory()
        let bid  = bundleID(for: app.path)
        let fm   = FileManager.default

        // Read whitelist — whitelisted paths start unchecked
        let whitelistRaw = UserDefaults.standard.string(forKey: "cleanWhitelist") ?? ""
        let whitelist = Set(whitelistRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
        func isWhitelisted(_ path: String) -> Bool { whitelist.contains(path) }

        var result: [Remnant] = []

        func add(title: String, path: String, size: Int64, label: String? = nil) {
            guard size > 0, fm.fileExists(atPath: path) else { return }
            let tilde = (path as NSString).abbreviatingWithTildeInPath
            result.append(Remnant(
                title:   title,
                path:    path,
                label:   label ?? tilde,
                size:    size,
                checked: !isWhitelisted(path)
            ))
        }

        add(title: "Application",         path: app.path,              size: app.appSize)
        if let bid {
            add(title: "Caches",          path: home + "/Library/Caches/\(bid)",        size: app.cacheSize)
            add(title: "Container",       path: home + "/Library/Containers/\(bid)",    size: app.containerSize)
            add(title: "WebKit data",     path: home + "/Library/WebKit/\(bid)",        size: app.webKitSize)
            add(title: "Saved state",     path: home + "/Library/Saved Application State/\(bid).savedState", size: app.savedStateSize)
            add(title: "Preferences",     path: home + "/Library/Preferences/\(bid).plist", size: app.prefsSize)
            // Group containers — may be multiple dirs
            let groupBase = home + "/Library/Group Containers"
            let domain = bid.components(separatedBy: ".").prefix(3).joined(separator: ".")
            if let entries = try? fm.contentsOfDirectory(atPath: groupBase) {
                for entry in entries where entry.contains(domain) {
                    let fullPath = groupBase + "/" + entry
                    // Reuse AppScanner.directorySize — single source of truth
                    let sz = AppScanner.directorySize(path: fullPath, fm: fm)
                    add(title: "Group container", path: fullPath, size: sz,
                        label: "~/Library/Group Containers/\(entry)")
                }
            }
        }
        add(title: "Application support", path: home + "/Library/Application Support/\(app.name)", size: app.supportSize)

        // Launch agent plists — each plist gets its own row so the user can
        // selectively remove them. Rows for currently-loaded agents show a
        // "restart required" badge so the user understands the side effect.
        for agent in app.launchAgents {
            let fm2 = FileManager.default
            guard fm2.fileExists(atPath: agent.path) else { continue }
            let sz = Int64((try? fm2.attributesOfItem(atPath: agent.path)[.size] as? Int) ?? 0)
            guard sz > 0 else { continue }
            let tilde = (agent.path as NSString).abbreviatingWithTildeInPath
            let whitelisted = whitelist.contains(agent.path)
            result.append(Remnant(
                title:        "Login item",
                path:         agent.path,
                label:        tilde,
                size:         sz,
                checked:      !whitelisted,
                needsRestart: agent.isLoaded
            ))
        }

        return result
    }

    private func bundleID(for appPath: String) -> String? {
        let plist = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOfFile: plist) as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    // POLISH-03: read the version string directly from the bundle's Info.plist.
    // Used to back-fill AppItems created via drag-and-drop, which arrive with version="—".
    private func readVersion(from appPath: String?) -> String {
        guard let path = appPath else { return "" }
        let plist = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOfFile: plist) as? [String: Any] else { return "" }
        return (dict["CFBundleShortVersionString"] as? String) ?? ""
    }

    // MARK: — Success state
    private func successState(_ app: AppItem) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            }
            Text("\(app.name) removed")
                .font(.system(size: titleSize, weight: .semibold))
            Text("\(formatBytes(trashedSize)) moved to Trash")
                .font(.system(size: bodySize))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text("Empty the Trash to permanently free the space.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Open Trash") {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".Trash"))
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 4)

            // Login Items reminder — shown when the app registered via SMAppService.
            // Unlike launch agent plists (which we can remove as files), SMAppService
            // login items have no removal API available to a third party. We surface a
            // clear, actionable prompt so the user doesn't wonder why the app still
            // appears in System Settings → General → Login Items.
            if hasLikelyLoginItem(app) {
                loginItemReminderBanner(app)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasLikelyLoginItem(app))
    }

    /// True when the app likely registered a Login Item via SMAppService.
    /// Heuristic: a significant fraction of apps that add themselves to Login Items
    /// do so via SMAppService and leave no plist in ~/Library/LaunchAgents/.
    /// We flag apps that had a launch agent in our scan OR whose bundle path
    /// contained known helper patterns — then remind the user to check.
    private func hasLikelyLoginItem(_ app: AppItem) -> Bool {
        // Don't show if we already surfaced a plist launch agent row.
        if !app.launchAgents.isEmpty { return false }
        // Only flag apps that have an Application Support folder AND are over 50 MB —
        // this narrows to background-capable productivity/utility apps (Dropbox, 1Password,
        // Zoom, etc.) rather than firing on every installed app.
        // Apps below this threshold are unlikely to have registered a login item.
        let hasSupportDir = app.supportSize > 0
        let isSubstantialApp = app.appSize > 50_000_000
        return hasSupportDir && isSubstantialApp
    }

    /// Contextual banner that explains the Login Items limitation and deep-links
    /// the user directly to System Settings → General → Login Items.
    private func loginItemReminderBanner(_ app: AppItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                    .symbolRenderingMode(.hierarchical)
                Text("Check login items")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                Spacer()
            }
            Text("\(app.name) may have registered a Login Item via macOS APIs that don't provide a removal method to third-party apps. Open System Settings to remove it manually if it appears there.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .lineSpacing(2)
            Button("Open Login Items in System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
                )
            }
            .buttonStyle(.link)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.accentColor)
        }
        .padding(12)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Login Items reminder for \(app.name). Tap to open System Settings.")
    }

    // MARK: — Empty state
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .symbolRenderingMode(.hierarchical)
            Text("Select an application")
                .font(.system(size: 15, weight: .semibold))
            Text("Or drag an app from Finder")
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }
}

// MARK: — Remnant row (checkbox state is owned by AppDetailView via Binding)
struct AppRemnantRow: View {
    let title       : String
    let pathLabel   : String
    let size        : Int64
    var needsRestart: Bool = false
    @Binding var isChecked: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle("", isOn: $isChecked)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                        // Restart-required badge — only shown for active launch agents
                        if needsRestart {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Restart required")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(Color(nsColor: .systemOrange))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .systemOrange).opacity(0.12))
                                    .overlay(Capsule()
                                        .stroke(Color(nsColor: .systemOrange).opacity(0.3),
                                                lineWidth: 0.5))
                            )
                        }
                    }
                    Text(pathLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(formatBytes(size))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .monospacedDigit()
            }
            .padding(12)
            Divider().padding(.leading, 36)
        }
        .opacity(isChecked ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.15), value: isChecked)
    }
}

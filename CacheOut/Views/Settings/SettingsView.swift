import SwiftUI
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            CleaningSettingsTab()
                .tabItem { Label("Cleaning", systemImage: "sparkles") }
            DevPurgeSettingsTab()
                .tabItem { Label("Dev purge", systemImage: "hammer") }
            DuplicatesSettingsTab()
                .tabItem { Label("Duplicates", systemImage: "doc.on.doc") }
            LargeFilesSettingsTab()
                .tabItem { Label("Large files", systemImage: "doc.zipper") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "terminal") }
        }
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520,
               minHeight: 380, idealHeight: 420, maxHeight: 560)
    }
}

// MARK: — General
struct GeneralSettingsTab: View {
    @AppStorage("showMenuBar")       private var showMenuBar       = true
    @AppStorage("notifyOnComplete")  private var notifyOnComplete  = true
    @AppStorage("scanOnLaunch")      private var scanOnLaunch      = false
    @AppStorage("unusedAppDays")     private var unusedAppDays     = 90
    @AppStorage("showTourOnLaunch")  private var showTourOnLaunch  = false
    // 0 = system, 1 = light, 2 = dark
    @AppStorage("appearanceMode")    private var appearanceMode    = 0
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                LaunchAtLoginRow()

                // Menu bar toggle — posts notification so MoleApp can react
                Toggle("Show in menu bar", isOn: $showMenuBar)
                    .onChange(of: showMenuBar) { _, on in
                        NotificationCenter.default.post(name: .menuBarVisibilityChanged,
                                                        object: on)
                    }

                // Notification toggle — requests permission on first enable
                Toggle("Notify when clean is complete", isOn: $notifyOnComplete)
                    .onChange(of: notifyOnComplete) { _, on in
                        if on { requestNotificationPermission() }
                    }

                Toggle("Run background scan on schedule", isOn: $scanOnLaunch)
                    .help(Text("When enabled, Cache Out scans on the schedule set in Cleaning settings and notifies you when junk is found."))

                Toggle("Show feature tour on launch", isOn: $showTourOnLaunch)
                    .help(Text("When checked, the feature tour opens each time Cache Out launches. Uncheck to suppress it."))
            }

            Section("Appearance") {
                Picker("Color scheme", selection: $appearanceMode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
                // Apply immediately by posting to the window
                .onChange(of: appearanceMode) { _, mode in
                    applyAppearance(mode)
                }
                Text("Overrides the system appearance for Cache Out only.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("Unused apps") {
                Picker("Mark app as unused after", selection: $unusedAppDays) {
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("1 year").tag(365)
                }
                Text("Apps not launched within this period show the Unused badge.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { notifStatus = await currentNotifStatus() }
        .onAppear { applyAppearance(appearanceMode) }
    }

    private func applyAppearance(_ mode: Int) {
        let appearance: NSAppearance? = switch mode {
        case 1:  NSAppearance(named: .aqua)
        case 2:  NSAppearance(named: .darkAqua)
        default: nil   // nil = follow system
        }
        NSApp.appearance = appearance
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func currentNotifStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// Isolated row so SMAppService errors don't crash the whole settings view
private struct LaunchAtLoginRow: View {
    @State private var enabled = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: $enabled)
                .onAppear  { enabled = LaunchAtLogin.isEnabled }
                .onChange(of: enabled) { _, on in
                    errorMessage = LaunchAtLogin.setEnabled(on)
                    // If the call failed, snap the toggle back to reflect real state
                    if errorMessage != nil {
                        enabled = LaunchAtLogin.isEnabled
                    }
                }
            if let msg = errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: errorMessage != nil)
    }
}

// MARK: — Cleaning
struct CleaningSettingsTab: View {
    @AppStorage("autoCleanSchedule") private var schedule = 0
    @AppStorage("cleanWhitelist")    private var whitelistRaw = ""
    @State private var showPathPicker = false

    private var whitelist: [String] {
        whitelistRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section("Schedule") {
                Picker("Auto-clean frequency", selection: $schedule) {
                    Text("Never").tag(0)
                    Text("Daily").tag(1)
                    Text("Weekly").tag(2)
                    Text("Monthly").tag(3)
                }
                .onChange(of: schedule) { _, _ in
                    NotificationCenter.default.post(name: .autoCleanScheduleChanged, object: nil)
                }
                if schedule != 0 {
                    Text("Cache Out will scan in the background and notify you when junk is found.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Section("Whitelist — never clean these paths") {
                if whitelist.isEmpty {
                    Text("No paths added yet.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(whitelist, id: \.self) { path in
                        HStack {
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                removeWhitelistPath(path)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Add path…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Add to whitelist"
                    if panel.runModal() == .OK, let url = panel.url {
                        addWhitelistPath(url.path)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addWhitelistPath(_ path: String) {
        var paths = whitelist
        guard !paths.contains(path) else { return }
        paths.append(path)
        whitelistRaw = paths.joined(separator: "\n")
    }

    private func removeWhitelistPath(_ path: String) {
        whitelistRaw = whitelist.filter { $0 != path }.joined(separator: "\n")
    }
}

// MARK: — Dev purge
struct DevPurgeSettingsTab: View {
    @AppStorage("purgeSkipRecentDays") private var skipDays  = 7
    @AppStorage("purgeScanDirs")       private var scanDirsRaw = ""

    private var customDirs: [String] {
        scanDirsRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section("Recent project protection") {
                Picker("Skip projects modified within", selection: $skipDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
            }

            Section("Scan scope") {
                if customDirs.isEmpty {
                    // Default state — scanning home
                    HStack(spacing: 10) {
                        Image(systemName: "house")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Entire home folder")
                                .font(.system(size: 13))
                            Text("Dev Purge scans your entire home directory by default, so artifacts are found regardless of where your projects live.")
                                .font(.system(size: 11))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                    }
                    .padding(.vertical, 2)
                } else {
                    // Custom roots set — show them with remove buttons
                    ForEach(customDirs, id: \.self) { dir in
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .frame(width: 16)
                            Text(dir)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                removeScanDir(dir)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Allow reverting to full-home default
                    Button("Reset to home folder default") {
                        scanDirsRaw = ""
                    }
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .font(.system(size: 11))
                }

                Button("Limit scan to specific folders…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    panel.prompt = "Add"
                    panel.message = "Add folders to scan instead of the entire home directory."
                    if panel.runModal() == .OK {
                        for url in panel.urls { addScanDir(url.path) }
                    }
                }

                Text("Optional. Use this to narrow the scan to specific project roots if scanning your whole home folder is too slow.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
        .formStyle(.grouped)
    }

    private func addScanDir(_ path: String) {
        var dirs = customDirs
        let tilde = (path as NSString).abbreviatingWithTildeInPath
        guard !dirs.contains(tilde) else { return }
        dirs.append(tilde)
        scanDirsRaw = dirs.joined(separator: "\n")
    }

    private func removeScanDir(_ path: String) {
        scanDirsRaw = customDirs.filter { $0 != path }.joined(separator: "\n")
    }
}

// MARK: — Duplicates
struct DuplicatesSettingsTab: View {
    @AppStorage("duplicatesMinSizeKB")       private var minSizeKB: Int = 1024
    @AppStorage("duplicatesExcludedDirs")    private var excludedRaw: String = ""

    private static let logMin = log(100.0)
    private static let logMax = log(512.0 * 1024.0)

    private var sliderValue: Double {
        let clamped = max(100, min(minSizeKB, 512 * 1024))
        return (log(Double(clamped)) - Self.logMin) / (Self.logMax - Self.logMin)
    }

    private func sliderMoved(to position: Double) {
        let raw = exp(Self.logMin + position * (Self.logMax - Self.logMin))
        minSizeKB = roundedKB(raw)
    }

    private func roundedKB(_ raw: Double) -> Int {
        switch raw {
        case ..<1024:       return max(100, Int((raw / 100).rounded()) * 100)
        case ..<10_240:     return max(1024, Int((raw / 1024).rounded()) * 1024)
        default:            return max(10_240, Int((raw / 10_240).rounded()) * 10_240)
        }
    }

    private var sizeLabel: String { formatKB(minSizeKB) }

    private func formatKB(_ kb: Int) -> String {
        if kb < 1024 { return "\(kb) KB" }
        let mb = kb / 1024
        if mb < 1024 { return "\(mb) MB" }
        return "\(mb / 1024) GB"
    }

    private var excludedDirs: [String] {
        excludedRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section("Minimum file size") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Scan files larger than")
                            .font(.system(size: 13))
                        Spacer()
                        Text(sizeLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    HStack(spacing: 8) {
                        Text("100 KB").font(.system(size: 10)).foregroundColor(.secondary)
                        Slider(
                            value: Binding(get: { sliderValue }, set: { sliderMoved(to: $0) }),
                            in: 0...1
                        )
                        Text("512 MB").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Text("Smaller values find more duplicates but scan takes longer. Default is 1 MB.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Section("Scan scope") {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.accentColor).font(.system(size: 13)).frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Use the 'Scan folder\u{2026}' button in the tab")
                            .font(.system(size: 13))
                        Text("Open the Duplicates tab and tap the pill button to add specific folders. Custom roots are session-scoped and don't persist across launches.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Excluded directories") {
                if excludedDirs.isEmpty {
                    Text("No directories excluded. All scan roots are searched.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    ForEach(excludedDirs, id: \.self) { dir in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.minus")
                                .font(.system(size: 12))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .frame(width: 16)
                            Text(dir)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { removeExcludedDir(dir) } label: {
                                Image(systemName: "minus.circle.fill").foregroundColor(.red)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button("Exclude directory…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    panel.prompt = "Exclude"
                    panel.message = "Choose directories the Duplicates scanner should skip."
                    if panel.runModal() == .OK {
                        for url in panel.urls { addExcludedDir(url.path) }
                    }
                }
                Text("Files inside excluded directories are ignored even if the directory is inside a scan root.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addExcludedDir(_ path: String) {
        var dirs = excludedDirs
        let tilde = (path as NSString).abbreviatingWithTildeInPath
        guard !dirs.contains(tilde) else { return }
        dirs.append(tilde)
        excludedRaw = dirs.joined(separator: "\n")
    }

    private func removeExcludedDir(_ path: String) {
        excludedRaw = excludedDirs.filter { $0 != path }.joined(separator: "\n")
    }
}

// MARK: — Large files
struct LargeFilesSettingsTab: View {
    // Stored as KB. Default = 102400 (100 MB).
    // Slider log scale: 0.0 = 1 MB, 1.0 = 10 GB.
    @AppStorage("largeFilesMinSizeKB")    private var minSizeKB: Int = 102_400
    @AppStorage("largeFilesExcludedDirs") private var excludedRaw: String = ""

    // --- Slider logic ---
    private static let logMin = log(1_024.0)           // 1 MB in KB
    private static let logMax = log(10_240.0 * 1_024.0) // 10 GB in KB

    private var sliderValue: Double {
        let clamped = max(1_024, min(minSizeKB, 10_240 * 1_024))
        return (log(Double(clamped)) - Self.logMin) / (Self.logMax - Self.logMin)
    }

    private func sliderMoved(to position: Double) {
        let raw = exp(Self.logMin + position * (Self.logMax - Self.logMin))
        minSizeKB = roundedKB(raw)
    }

    // Snap: <100 MB → nearest 10 MB, <1 GB → nearest 100 MB, above → nearest 1 GB
    private func roundedKB(_ raw: Double) -> Int {
        switch raw {
        case ..<102_400:         return max(1_024, Int((raw / 10_240).rounded()) * 10_240)
        case ..<1_048_576:       return max(102_400, Int((raw / 102_400).rounded()) * 102_400)
        default:                 return max(1_048_576, Int((raw / 1_048_576).rounded()) * 1_048_576)
        }
    }

    private var sizeLabel: String {
        let kb = minSizeKB
        if kb < 1_024       { return "\(kb) KB" }
        let mb = kb / 1_024
        if mb < 1_024       { return "\(mb) MB" }
        let gb = mb / 1_024
        return "\(gb) GB"
    }

    // --- Excluded dirs ---
    private var excludedDirs: [String] {
        excludedRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            // ── Minimum file size ──────────────────────────────────────────
            Section("Minimum file size") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Show files larger than")
                            .font(.system(size: 13))
                        Spacer()
                        Text(sizeLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    HStack(spacing: 8) {
                        Text("1 MB")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Slider(
                            value: Binding(
                                get: { sliderValue },
                                set: { sliderMoved(to: $0) }
                            ),
                            in: 0...1
                        )
                        Text("10 GB")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Text("Only files at or above this size appear in Large Files. Default is 100 MB.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("Scan scope") {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.accentColor).font(.system(size: 13)).frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Use the 'Scan folder\u{2026}' button in the tab")
                            .font(.system(size: 13))
                        Text("Open the Large Files tab and tap the pill button to add specific folders. Custom roots are session-scoped and reset on next launch.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
                .padding(.vertical, 2)
            }

            // ── Excluded directories ───────────────────────────────────────
            Section("Excluded directories") {
                if excludedDirs.isEmpty {
                    Text("No directories excluded. The entire home folder is scanned.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(excludedDirs, id: \.self) { dir in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.minus")
                                .font(.system(size: 12))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .frame(width: 16)
                            Text(dir)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                removeExcludedDir(dir)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Exclude directory…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    panel.prompt = "Exclude"
                    panel.message = "Choose directories the Large Files scanner should skip."
                    if panel.runModal() == .OK {
                        for url in panel.urls { addExcludedDir(url.path) }
                    }
                }
                Text("Files inside excluded directories are hidden even if they exceed the size threshold.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addExcludedDir(_ path: String) {
        var dirs = excludedDirs
        let tilde = (path as NSString).abbreviatingWithTildeInPath
        guard !dirs.contains(tilde) else { return }
        dirs.append(tilde)
        excludedRaw = dirs.joined(separator: "\n")
    }

    private func removeExcludedDir(_ path: String) {
        excludedRaw = excludedDirs.filter { $0 != path }.joined(separator: "\n")
    }
}

// MARK: — Advanced
struct AdvancedSettingsTab: View {
    @AppStorage("dryRunMode")    private var dryRunMode    = false
    @AppStorage("debugLogging")  private var debugLogging  = false
    @ObservedObject private var sparkle = SparkleUpdater.shared

    var body: some View {
        Form {
            Section("Developer") {
                Toggle("Dry run mode (simulate only)", isOn: $dryRunMode)
                if dryRunMode {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("Files will NOT be moved to Trash. All operations are simulated.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
                Toggle("Debug logging", isOn: $debugLogging)
                if debugLogging {
                    Text("Verbose logs are written to Console.app under subsystem \u{201C}com.cacheout.CacheOut\u{201D}. Disable when not needed.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Section("App updates") {
                if sparkle.canCheckForUpdates {
                    LabeledContent("Cache Out") {
                        if sparkle.isCheckingForUpdates {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Checking…")
                                    .foregroundColor(.secondary)
                            }
                        } else if let version = sparkle.pendingUpdateVersion {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 12))
                                Text("v\(version) available")
                                    .foregroundColor(.secondary)
                                Button("Install") { sparkle.checkForUpdates() }
                                    .buttonStyle(.link)
                                    .font(.system(size: 12))
                            }
                        } else if sparkle.isUpToDate {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 12))
                                Text("Up to date")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Button("Check now") { sparkle.checkForUpdates() }
                                .buttonStyle(.link)
                                .font(.system(size: 12))
                        }
                    }
                } else {
                    LabeledContent("App updates") {
                        Text("Add Sparkle SPM package to enable")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                }
            }

            Section("About") {
                Button("View on GitHub") {
                    if let url = URL(string: "https://github.com/approved200/CacheOut") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Reset all settings…") {
                    let keys = ["showMenuBar","notifyOnComplete","scanOnLaunch",
                                "unusedAppDays","appearanceMode","showTourOnLaunch",
                                "autoCleanSchedule","cleanWhitelist",
                                "purgeSkipRecentDays","purgeScanDirs",
                                "dryRunMode","debugLogging",
                                "duplicatesMinSizeKB","duplicatesExcludedDirs",
                                "largeFilesMinSizeKB","largeFilesExcludedDirs",
                                "hasCompletedOnboarding","hasSeenTour"]
                    keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
                    // Re-apply system appearance and cancel pending background clean
                    NSApp.appearance = nil
                    NotificationCenter.default.post(name: .autoCleanScheduleChanged, object: nil)
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
    }

}


import SwiftUI

struct CleanView: View {
    @ObservedObject var viewModel: CleanViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("dryRunMode") private var dryRunMode = false

    // Dynamic Type — scale hero numbers and body text with user's font size preference
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title2)     private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title3)     private var subtitle1Size: CGFloat = 20
    @ScaledMetric(relativeTo: .body)       private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption)    private var captionSize: CGFloat = 11

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.state {
            case .idle:                  idleState
            case .scanning:              scanningState
            case .ready, .refreshing:    readyState
            case .cleaning(let prog):    cleaningState(progress: prog)
            case .complete:              completeState
            case .systemClean:           emptyState
            case .permissionDenied:      permissionDeniedState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.scanIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.startScan() }
        }
        // Keep the toolbar CTA in sync with our state
        .onChange(of: viewModel.state)             { _, _ in syncCTA() }
        .onChange(of: viewModel.totalSelectedSize)  { _, _ in syncCTA() }
        .onAppear  { syncCTA() }
        .onDisappear { cta.label = ""; cta.isEnabled = false; cta.action = nil; cta.helpText = "" }
        .onChange(of: dryRunMode) { _, _ in syncCTA() }
        // Standard confirmation — used when selection includes anything other than just Trash
        .confirmationDialog(
            "Move \(formatBytes(viewModel.totalSelectedSize)) to Trash?",
            isPresented: $showCleanConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await viewModel.startCleaning() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Selected items will be moved to the Trash. You can recover them if needed.")
        }
        // Trash-only confirmation — used when ONLY the Trash category is selected.
        // This operation is permanent; the copy must be honest about that.
        .confirmationDialog(
            "Permanently empty the Trash?",
            isPresented: $showTrashOnlyConfirm,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                Task { await viewModel.startCleaning() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the contents of the Trash. This cannot be undone.")
        }
    }

    // Confirmation lives here so the CTA button triggers the dialog
    @State private var showCleanConfirm      = false
    @State private var showTrashOnlyConfirm  = false
    @State private var showRestoreConfirm    = false
    /// Result of the last put-back operation — shown as a banner in completeState.
    @State private var restoreResult: (restored: Int, errors: [String])? = nil

    private func syncCTA() {
        switch viewModel.state {
        case .ready, .refreshing:
            let label = dryRunMode ? "Simulate clean" : "Clean \(formatBytes(viewModel.totalSelectedSize))"
            cta.label     = label
            cta.isEnabled = viewModel.totalSelectedSize > 0
            cta.action    = {
                // Route to a separate, honest confirmation when ONLY Trash is selected,
                // because that operation permanently deletes — not moves to Trash.
                let onlyTrash = viewModel.selectedCategories == [.trash]
                if onlyTrash {
                    showTrashOnlyConfirm = true
                } else {
                    showCleanConfirm = true
                }
            }
        case .scanning:
            cta.label = "Scanning…"; cta.isEnabled = false; cta.action = nil
            restoreResult = nil   // clear stale undo banner when a new scan starts
        case .cleaning:
            cta.label = "Cleaning…"; cta.isEnabled = false; cta.action = nil
        case .complete, .systemClean:
            cta.label     = "Scan again"
            cta.isEnabled = true
            cta.action    = { Task { await viewModel.startScan() } }
        case .idle:
            cta.label = ""; cta.isEnabled = false; cta.action = nil
        case .permissionDenied:
            cta.label = ""; cta.isEnabled = false; cta.action = nil
        }
    }

    // MARK: — Scanning
    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning…")
                .font(.system(size: titleSize, weight: .semibold))
            Text("Analyzing caches, logs, and build artifacts…")
                .font(.system(size: bodySize))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Idle (auto-scan disabled by user)
    private var idleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text("Ready to scan")
                .font(.system(size: subtitle1Size, weight: .semibold))
            Text("Automatic scan on launch is turned off.\nPress ⌘R or click Scan Now to start.")
                .font(.system(size: bodySize))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Ready
    private var readyState: some View {
        VStack(spacing: 0) {
            // Header — fixed, does not scroll
            VStack(spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(formatBytes(viewModel.totalSelectedSize))
                        .font(.system(size: heroSize, weight: .bold))
                        .contentTransition(.numericText(value: Double(viewModel.totalSelectedSize)))
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8),
                            value: viewModel.totalSelectedSize
                        )
                    // Subtle refresh indicator — only visible during background refresh
                    if viewModel.state == .refreshing {
                        ProgressView()
                            .controlSize(.small)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.state == .refreshing)

                Text("reclaimable space found")
                    .font(.system(size: bodySize))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))

                SegmentedBar(data: viewModel.categoriesData)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)

                SegmentedBarLegend(data: viewModel.categoriesData)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // Scrollable list
            ScrollView {
                VStack(spacing: 10) {
                    // Dry-run banner — shown at top of list when mode is active
                    if dryRunMode {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text("Dry run mode — nothing will actually be moved to Trash.")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.5))
                    }
                    ForEach(viewModel.categoriesData.indices, id: \.self) { i in
                        CategoryRow(
                            item: $viewModel.categoriesData[i],
                            onToggle: { viewModel.toggleSelection(for: viewModel.categoriesData[i].category) }
                        )
                    }

                    // Whitelist suppression footer — only shown when ≥1 item is hidden
                    if viewModel.whitelistSuppressedCount > 0 {
                        whitelistFooter(count: viewModel.whitelistSuppressedCount)
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: — Whitelist suppression footer
    // Shown at the bottom of the scan list when ≥1 sub-item was filtered out
    // by the user's whitelist. A quiet chip — informational, not alarming.
    // Tapping it opens Settings → Cleaning so the user can review the list.
    private func whitelistFooter(count: Int) -> some View {
        Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11))
                Text("\(count) item\(count == 1 ? "" : "s") hidden by whitelist")
                    .font(.system(size: 11))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                    .overlay(Capsule()
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .transition(.opacity)
        .accessibilityLabel("\(count) item\(count == 1 ? "" : "s") hidden by whitelist. Open settings to manage.")
    }

    // MARK: — Cleaning
    private func cleaningState(progress: Double) -> some View {
        VStack(spacing: 20) {
            Text(formatBytes(viewModel.cleanedSize))
                .font(.system(size: heroSize, weight: .bold))

            // Determinate progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor).opacity(0.3))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progress)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8),
                                   value: progress)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 60)

            Text(progress < 1.0
                 ? "Cleaning… \(Int(progress * 100))%"
                 : "Finishing up…")
                .font(.system(size: bodySize))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Complete
    private var completeState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text("\(formatBytes(viewModel.cleanedSize)) freed")
                .font(.system(size: 28, weight: .bold))

            Text("Your Mac is feeling lighter")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

            HStack(spacing: 10) {
                Button("Open Trash to review") {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: (NSHomeDirectory() as NSString)
                            .appendingPathComponent(".Trash")))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                // Put back — only shown when we have a recorded undo list
                if !viewModel.lastTrashedItems.isEmpty {
                    Button("Put everything back") {
                        showRestoreConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(.orange)
                }
            }
            .padding(.top, 4)

            // Restore result banner
            if let result = restoreResult {
                HStack(spacing: 6) {
                    Image(systemName: result.errors.isEmpty
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(result.errors.isEmpty ? .green : .orange)
                        .font(.system(size: 12))
                    Text(result.errors.isEmpty
                         ? "\(result.restored) item\(result.restored == 1 ? "" : "s") restored to original location\(result.restored == 1 ? "" : "s")"
                         : "\(result.restored) restored, \(result.errors.count) failed")
                        .font(.system(size: 12))
                        .foregroundColor(result.errors.isEmpty
                                         ? Color(nsColor: .labelColor)
                                         : Color(nsColor: .systemOrange))
                }
                .padding(10)
                .background((result.errors.isEmpty ? Color.green : Color.orange).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke((result.errors.isEmpty ? Color.green : Color.orange).opacity(0.25),
                            lineWidth: 0.5))
                .padding(.horizontal, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Error banner — shown when one or more items failed to trash
            if !viewModel.cleanErrors.isEmpty {
                // For read-only items: show PrivilegedItemCard per item.
                // A sub-item gets a card when its parent category is selected
                // and the sub-item itself is read-only (system-owned path).
                let readOnlyItems = viewModel.categoriesData
                    .filter(\.isSelected)
                    .flatMap(\.subItems)
                    .filter(\.isReadOnly)
                if !readOnlyItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(readOnlyItems, id: \.id) { item in
                            PrivilegedItemCard(item: item) {
                                Task { await viewModel.startScan() }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Genuine failures — everything that isn't a system-owned path skip
                let otherErrors = viewModel.cleanErrors.filter {
                    !$0.contains("owned by macOS")
                }
                // For genuine permission/other errors: plain error list
                if !otherErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange).font(.system(size: 12))
                            Text("\(otherErrors.count) item\(otherErrors.count == 1 ? "" : "s") could not be moved to Trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        ForEach(otherErrors, id: \.self) { err in
                            Text(err)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 0.5))
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Put \(viewModel.lastTrashedItems.count) item\(viewModel.lastTrashedItems.count == 1 ? "" : "s") back?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore to original locations") {
                Task {
                    let result = await viewModel.restoreLastClean()
                    withAnimation { restoreResult = result }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each item will be moved from the Trash back to where it was before cleaning. Items already emptied from Trash cannot be recovered.")
        }
    }

    // MARK: — System clean / empty
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text("Your Mac is clean")
                .font(.system(size: 17, weight: .semibold))

            Text("No significant junk found. Check back later.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Permission denied
    private var permissionDeniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            Text("Full Disk Access required")
                .font(.system(size: 20, weight: .semibold))

            Text("Cache Out needs Full Disk Access to scan\ncache folders, logs, and app junk.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)

            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("After granting access, press ⌘R to scan.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

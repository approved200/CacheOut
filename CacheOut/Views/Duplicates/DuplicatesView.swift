import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var viewModel: DuplicatesViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @State private var showRemoveAllConfirm  = false
    @State private var showRestoreConfirm    = false
    @State private var restoreResult: (restored: Int, errors: [String])? = nil
    @AppStorage("duplicatesMinSizeKB") private var minSizeKB: Int = 1024

    private var effectiveScanRoots: [String] {
        viewModel.customScanRoots.isEmpty
            ? PurgeViewModel.defaultScanRoots()
            : viewModel.customScanRoots
    }

    private var minSizeLabel: String {
        let kb = minSizeKB > 0 ? minSizeKB : 1024
        if kb < 1024 { return "\(kb) KB" }
        return "\(kb / 1024) MB"
    }

    var body: some View {
        Group {
            if viewModel.isScanning {
                scanningState
            } else if viewModel.groups.isEmpty && viewModel.lastTrashedItems.isEmpty {
                emptyState
            } else {
                resultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.scanIfNeeded() }
        .onAppear { DispatchQueue.main.async { syncCTA() } }
        .onDisappear { cta.label = ""; cta.isEnabled = false; cta.action = nil; cta.helpText = "" }
        .onChange(of: viewModel.isScanning)           { _, _ in syncCTA() }
        .onChange(of: viewModel.filteredGroups.count)  { _, _ in syncCTA() }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.scan(roots: effectiveScanRoots) }
        }
        .confirmationDialog(
            "Remove duplicates in \(viewModel.filteredGroups.count) group\(viewModel.filteredGroups.count == 1 ? "" : "s")?",
            isPresented: $showRemoveAllConfirm, titleVisibility: .visible
        ) {
            Button("Remove \(formatBytes(viewModel.totalSavings))", role: .destructive) {
                Task { await viewModel.removeAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file you marked Keep in each group is kept. All others move to Trash.")
        }
        .confirmationDialog(
            "Put \(viewModel.lastTrashedItems.count) file\(viewModel.lastTrashedItems.count == 1 ? "" : "s") back?",
            isPresented: $showRestoreConfirm, titleVisibility: .visible
        ) {
            Button("Restore to original locations") {
                Task {
                    let result = await viewModel.restoreLastClean()
                    withAnimation { restoreResult = result }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each file will be moved from the Trash back to where it was. Files already emptied from Trash cannot be recovered.")
        }
    }

    // MARK: — Scanning
    private var scanningState: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 60)
            Text(viewModel.phaseLabel)
                .font(.system(size: 13)).foregroundColor(.secondary)
            Text("\(Int(viewModel.progress * 100))% complete")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Button("Cancel") {
                viewModel.cancelScan()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Empty state
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48)).foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("No duplicates found")
                .font(.system(size: 17, weight: .semibold))
            Text("Scan your folders to find identical files\nwasting space on your Mac.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
            Text("Scanning files over \(minSizeLabel). Change in Settings → Duplicates.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Scan now") {
                    Task { await viewModel.scan(roots: effectiveScanRoots) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                addFolderButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Results
    private var resultsView: some View {
        VStack(spacing: 0) {
            // Error / scan-error banner
            if let err = viewModel.scanError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 12))
                    Text(err).font(.system(size: 12)).lineLimit(2)
                    Spacer()
                    Button("Dismiss") { viewModel.scanError = nil }
                        .font(.system(size: 11)).buttonStyle(.link)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 0.5))
                .padding(.horizontal, 20).padding(.top, 12)
            }

            // Restore result banner — shown after a put-back operation
            if let result = restoreResult {
                HStack(spacing: 6) {
                    Image(systemName: result.errors.isEmpty
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(result.errors.isEmpty ? .green : .orange)
                        .font(.system(size: 12))
                    Text(result.errors.isEmpty
                         ? "\(result.restored) file\(result.restored == 1 ? "" : "s") restored to original location\(result.restored == 1 ? "" : "s")"
                         : "\(result.restored) restored, \(result.errors.count) failed")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Dismiss") { withAnimation { restoreResult = nil } }
                        .font(.system(size: 11)).buttonStyle(.link)
                }
                .padding(10)
                .background((result.errors.isEmpty ? Color.green : Color.orange).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke((result.errors.isEmpty ? Color.green : Color.orange).opacity(0.25),
                            lineWidth: 0.5))
                .padding(.horizontal, 20).padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Filter + scope bar
            filterBar

            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.filteredGroups.isEmpty && !viewModel.lastTrashedItems.isEmpty {
                        // All groups removed — show a quiet confirmation state
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36)).foregroundStyle(.green)
                                .symbolRenderingMode(.hierarchical)
                            Text("All duplicates removed")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Moved \(viewModel.lastTrashedItems.count) file\(viewModel.lastTrashedItems.count == 1 ? "" : "s") to Trash.")
                                .font(.system(size: 12))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(viewModel.filteredGroups) { group in
                            DuplicateGroupRow(group: group, onRemove: { keep in
                                Task { await viewModel.remove(keeping: keep, from: group) }
                            })
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            // Status bar — always visible, contains Put Back button
            statusBar
        }
    }


    // MARK: — Always-visible status bar with Put Back button
    private var statusBar: some View {
        HStack(spacing: 12) {
            // Left: counts
            let shown = viewModel.filteredGroups.count
            let total = viewModel.groups.count
            Group {
                if shown == total && total > 0 {
                    Text("\(total) duplicate group\(total == 1 ? "" : "s") · \(formatBytes(viewModel.totalSavings)) reclaimable")
                } else if total > 0 {
                    Text("\(shown) of \(total) groups · filtered · \(formatBytes(viewModel.totalSavings)) reclaimable")
                } else {
                    Text("No groups")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))

            Spacer()

            // Custom roots badge
            if !viewModel.customScanRoots.isEmpty {
                Button {
                    viewModel.customScanRoots = []
                    Task { await viewModel.scan(roots: PurgeViewModel.defaultScanRoots()) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                        Text("\(viewModel.customScanRoots.count) custom folder\(viewModel.customScanRoots.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Clear custom folders and rescan default roots")
            }

            // Put Back button — always present, disabled when nothing to restore
            Button {
                showRestoreConfirm = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 11))
                    Text(viewModel.lastTrashedItems.isEmpty
                         ? "Put back"
                         : "Put back \(viewModel.lastTrashedItems.count) file\(viewModel.lastTrashedItems.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                }
                .foregroundColor(viewModel.lastTrashedItems.isEmpty
                                 ? Color(nsColor: .tertiaryLabelColor)
                                 : .orange)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(viewModel.lastTrashedItems.isEmpty
                              ? Color(nsColor: .quaternaryLabelColor).opacity(0.2)
                              : Color.orange.opacity(0.10))
                        .overlay(Capsule().stroke(
                            viewModel.lastTrashedItems.isEmpty
                                ? Color(nsColor: .separatorColor)
                                : Color.orange.opacity(0.3),
                            lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.lastTrashedItems.isEmpty)
            .help(viewModel.lastTrashedItems.isEmpty
                  ? "Nothing to restore yet — remove some duplicates first"
                  : "Move \(viewModel.lastTrashedItems.count) file\(viewModel.lastTrashedItems.count == 1 ? "" : "s") back to their original locations")
            .animation(.easeInOut(duration: 0.2), value: viewModel.lastTrashedItems.count)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }


    // MARK: — Filter + scope bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(
                    label: "All", icon: "tray.full",
                    color: Color(nsColor: .secondaryLabelColor),
                    isActive: viewModel.activeCategories.isEmpty
                ) { viewModel.activeCategories = [] }

                let presentCats = Set(viewModel.groups.compactMap { $0.files.first }
                    .map { FileCategory.category(for: $0) })
                ForEach(FileCategory.allCases) { cat in
                    if presentCats.contains(cat) {
                        FilterPill(
                            label: cat.rawValue, icon: cat.icon, color: cat.color,
                            isActive: viewModel.activeCategories.contains(cat)
                        ) {
                            if viewModel.activeCategories.contains(cat) {
                                viewModel.activeCategories.remove(cat)
                            } else {
                                viewModel.activeCategories.insert(cat)
                            }
                        }
                    }
                }

                Divider().frame(height: 16)
                addFolderButton
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: — Add folder button
    private var addFolderButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = "Scan"
            panel.message = "Add folders to scan for duplicate files."
            if panel.runModal() == .OK {
                for url in panel.urls {
                    let path = url.path
                    if !viewModel.customScanRoots.contains(path) {
                        viewModel.customScanRoots.append(path)
                    }
                }
                Task { await viewModel.scan(roots: viewModel.customScanRoots) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.badge.plus").font(.system(size: 11))
                Text("Scan folder…").font(.system(size: 11))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func syncCTA() {
        if viewModel.isScanning {
            cta.label = "Scanning…"; cta.isEnabled = false; cta.action = nil
        } else if viewModel.filteredGroups.isEmpty {
            cta.label = "Scan now"; cta.isEnabled = true
            cta.action = { Task { await viewModel.scan(roots: effectiveScanRoots) } }
        } else {
            cta.label = "Remove \(formatBytes(viewModel.totalSavings))"
            cta.isEnabled = true
            cta.action = { showRemoveAllConfirm = true }
        }
    }
}


// MARK: — Group row
// keepIndex is local @State — the user can tap "Keep this" on any file in the
// group before hitting Remove. The row tracks their choice independently of the
// ViewModel so no data is mutated until the user confirms removal.
struct DuplicateGroupRow: View {
    let group   : DuplicateGroup
    let onRemove: (URL) -> Void

    @State private var isExpanded = true
    /// Index of the file the user has chosen to keep. Defaults to 0 (first file).
    @State private var keepIndex  = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header
            Button { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(group.files.count) identical files")
                            .font(.system(size: 13, weight: .medium))
                        Text(group.files[0].lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .lineLimit(1)
                    }
                    Spacer()
                    let cat = FileCategory.category(for: group.files[0])
                    HStack(spacing: 3) {
                        Image(systemName: cat.icon).font(.system(size: 9))
                        Text(cat.rawValue).font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(cat.color)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(cat.color.opacity(0.10)))

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatBytes(group.fileSize * Int64(group.files.count - 1)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Text("reclaimable")
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.leading, 38)
                ForEach(Array(group.files.enumerated()), id: \.element) { idx, url in
                    DuplicateFileRow(
                        url: url,
                        isKeep: idx == keepIndex,
                        fileSize: group.fileSize,
                        onKeep: {
                            withAnimation(.easeInOut(duration: 0.15)) { keepIndex = idx }
                        },
                        onTrash: {
                            onRemove(group.files[keepIndex])
                        }
                    )
                    if idx < group.files.count - 1 {
                        Divider().padding(.leading, 38)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

// MARK: — Individual file row
// isKeep reflects the user's current choice for this group.
// Tapping "Keep this" on any row updates keepIndex in the parent.
// The "Remove others" button uses the parent's current keepIndex to decide
// which file to pass to onRemove — so the choice is always respected.
private struct DuplicateFileRow: View {
    let url      : URL
    let isKeep   : Bool
    let fileSize : Int64
    let onKeep   : () -> Void   // called when user taps "Keep this" on this row
    let onTrash  : () -> Void   // called when user taps "Remove others" on this row

    var body: some View {
        HStack(spacing: 10) {
            // Keep/trash indicator
            Image(systemName: isKeep ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundColor(isKeep ? .green : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 20)
                .onTapGesture { if !isKeep { onKeep() } }

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(formatBytes(fileSize))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

            if isKeep {
                // Show "Remove others" on the keep row so the action is clear:
                // "I'm keeping this one, remove the rest"
                Button(action: onTrash) {
                    Text("Remove others")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("Keep this copy, move all others to Trash")
            } else {
                // On non-keep rows: let the user designate this file as the one to keep
                Button(action: onKeep) {
                    Text("Keep this")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Mark this copy as the one to keep")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isKeep
            ? Color.green.opacity(0.04)
            : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isKeep)
        .onTapGesture {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
            Button("Mark as keep") { onKeep() }
                .disabled(isKeep)
            Divider()
            Button("Remove others (keep this)", role: .destructive) {
                onKeep()
                onTrash()
            }
        }
    }
}


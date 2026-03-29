import SwiftUI

struct LargeFilesView: View {
    @ObservedObject var viewModel: LargeFilesViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @State private var itemToTrash: LargeFileItem? = nil
    @State private var showConfirm  = false
    @AppStorage("largeFilesMinSizeKB") private var minSizeKB: Int = 102_400

    private var thresholdLabel: String {
        let kb = minSizeKB > 0 ? minSizeKB : 102_400
        if kb < 1_024       { return "\(kb) KB" }
        let mb = kb / 1_024
        if mb < 1_024       { return "\(mb) MB" }
        return "\(mb / 1_024) GB"
    }

    var body: some View {
        Group {
            if viewModel.isScanning { scanningState }
            else if viewModel.items.isEmpty { emptyState }
            else { resultsView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.scanIfNeeded() }
        .onAppear { DispatchQueue.main.async { syncCTA() } }
        .onDisappear { cta.label = ""; cta.isEnabled = false; cta.action = nil; cta.helpText = "" }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.scan() }
        }
        .onChange(of: viewModel.isScanning) { _, _ in syncCTA() }
        .confirmationDialog(
            "Move \"\(itemToTrash?.url.lastPathComponent ?? "")\" to Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            if let item = itemToTrash {
                Button("Move \(formatBytes(item.size)) to Trash", role: .destructive) {
                    Task { await viewModel.trash(item) }
                    itemToTrash = nil
                }
            }
            Button("Cancel", role: .cancel) { itemToTrash = nil }
        } message: { Text("The file will be moved to the Trash. You can recover it if needed.") }
    }

    // MARK: — Scanning
    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning for large files…")
                .font(.system(size: 13)).foregroundColor(.secondary)
            Text("Looking for files over \(thresholdLabel)")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            if !viewModel.customScanRoots.isEmpty {
                Text("Scanning \(viewModel.customScanRoots.count) custom folder\(viewModel.customScanRoots.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Empty state
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("No large files found")
                .font(.system(size: 17, weight: .semibold))
            Text("No files over \(thresholdLabel) found.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text("Change the threshold in Settings → Large files.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            addFolderButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Results
    private var resultsView: some View {
        VStack(spacing: 0) {
            // Error banner
            if let err = viewModel.scanError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 12))
                    Text(err).font(.system(size: 12))
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

            // Filter + scope bar
            filterBar

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.filteredItems) { item in
                        LargeFileRow(item: item, onTrash: {
                            itemToTrash = item
                            showConfirm = true
                        })
                        Divider().padding(.leading, 20)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .padding(20)
            }

            Divider()
            // Status bar
            HStack {
                let shown = viewModel.filteredItems.count
                let total = viewModel.items.count
                if shown == total {
                    Text("\(total) files over \(thresholdLabel)")
                } else {
                    Text("\(shown) of \(total) files · filtered")
                }
                Spacer()
                // Custom roots badge
                if !viewModel.customScanRoots.isEmpty {
                    Button {
                        viewModel.customScanRoots = []
                        Task { await viewModel.scan() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                            Text("\(viewModel.customScanRoots.count) custom folder\(viewModel.customScanRoots.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Clear custom folders and rescan home directory")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    // MARK: — Filter + scope bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All pill
                FilterPill(
                    label: "All",
                    icon: "tray.full",
                    color: Color(nsColor: .secondaryLabelColor),
                    isActive: viewModel.activeCategories.isEmpty
                ) {
                    viewModel.activeCategories = []
                }

                // Per-category pills — only show categories that exist in results
                let presentCats = Set(viewModel.items.map(\.category))
                ForEach(FileCategory.allCases) { cat in
                    if presentCats.contains(cat) {
                        FilterPill(
                            label: cat.rawValue,
                            icon: cat.icon,
                            color: cat.color,
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

                // Add folder button
                addFolderButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: — Add folder inline button
    private var addFolderButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = "Scan"
            panel.message = "Add folders to scan for large files."
            if panel.runModal() == .OK {
                for url in panel.urls {
                    let path = url.path
                    if !viewModel.customScanRoots.contains(path) {
                        viewModel.customScanRoots.append(path)
                    }
                }
                Task { await viewModel.scan() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                Text("Scan folder…")
                    .font(.system(size: 11))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func syncCTA() {
        cta.label = ""; cta.isEnabled = false; cta.action = nil
    }
}

// MARK: — Reusable filter pill
struct FilterPill: View {
    let label   : String
    let icon    : String
    let color   : Color
    let isActive: Bool
    let action  : () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isActive ? color : Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isActive ? color.opacity(0.12) : Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                    .overlay(Capsule().stroke(
                        isActive ? color.opacity(0.35) : Color(nsColor: .separatorColor),
                        lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Large file row
private struct LargeFileRow: View {
    let item   : LargeFileItem
    let onTrash: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            // Category badge
            HStack(spacing: 3) {
                Image(systemName: item.category.icon)
                    .font(.system(size: 9))
                Text(item.category.rawValue)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(item.category.color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(item.category.color.opacity(0.10)))

            Text(item.ageDays == 0 ? "Today"
                 : item.ageDays == 1 ? "Yesterday"
                 : "\(item.ageDays)d ago")
                .font(.system(size: 11))
                .foregroundColor(item.ageDays > 90
                    ? Color(nsColor: .systemOrange)
                    : Color(nsColor: .secondaryLabelColor))
                .frame(width: 72, alignment: .trailing)
            Text(formatBytes(item.size))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 72, alignment: .trailing)
            Button(action: onTrash) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .buttonStyle(.plain)
            .help("Move to Trash")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        // Single click → reveal in Finder
        .onTapGesture {
            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
            }
            Divider()
            Button("Move to Trash", role: .destructive) { onTrash() }
        }
    }
}

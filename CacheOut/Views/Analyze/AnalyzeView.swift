import SwiftUI

struct AnalyzeView: View {
    @ObservedObject var viewModel: AnalyzeViewModel
    @EnvironmentObject private var cta: ToolbarCTAState

    // FEATURE-02: trash confirmation state
    @State private var nodeToTrash: DiskNode? = nil
    @State private var showTrashConfirm = false
    @State private var trashError: String? = nil
    @State private var showTrashError = false

    var body: some View {
        VStack(spacing: 0) {
            // Volume picker — lets user switch between mounted volumes
            VolumePicker(viewModel: viewModel)
            Divider()
            breadcrumbBar
            Divider()
            ZStack {
                if viewModel.isScanning && viewModel.nodes.isEmpty {
                    // Only show full-screen spinner on FIRST load
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Scanning…")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.nodes.isEmpty && viewModel.permissionDenied {
                    permissionDeniedState
                } else if viewModel.nodes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.system(size: 36))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text("Nothing to show here")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else {
                    TreemapView(nodes: viewModel.nodes, onDrillDown: { node in
                        viewModel.drillDown(node)
                    }, onTrash: { node in
                        nodeToTrash = node
                        showTrashConfirm = true
                    })
                    .padding(10)
                    // Small overlay spinner during background refresh
                    if viewModel.isScanning {
                        VStack {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(10)
                                    .background(Material.regular, in: RoundedRectangle(cornerRadius: 8))
                                    .padding(12)
                            }
                            Spacer()
                        }
                        .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isScanning)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            diskFooter
        }
        .task { await viewModel.scanIfNeeded() }
        // FEATURE-02: confirmation before trashing a treemap node
        .confirmationDialog(
            nodeToTrash.map { "Move \"\($0.name)\" to Trash?" } ?? "",
            isPresented: $showTrashConfirm,
            titleVisibility: .visible
        ) {
            if let node = nodeToTrash {
                Button("Move \(formatBytes(node.size)) to Trash", role: .destructive) {
                    do {
                        try FileManager.default.trashItem(
                            at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
                        NotificationCenter.default.post(name: .diskFreed, object: nil)
                        Task { await viewModel.rescan() }
                    } catch {
                        trashError = error.localizedDescription
                        showTrashError = true
                    }
                    nodeToTrash = nil
                }
            }
            Button("Cancel", role: .cancel) { nodeToTrash = nil }
        } message: {
            if let node = nodeToTrash {
                Text("\"\(node.name)\" (\(formatBytes(node.size))) will be moved to the Trash. You can recover it if needed.")
            }
        }
        .alert("Could not move to Trash", isPresented: $showTrashError, presenting: trashError) { _ in
            Button("OK", role: .cancel) { trashError = nil }
        } message: { msg in Text(msg) }
        .onAppear { DispatchQueue.main.async { syncCTA() } }
        .onDisappear { cta.label = ""; cta.isEnabled = false; cta.action = nil }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.rescan() }
        }
        // Re-sync CTA whenever navigation depth or scan state changes
        .onChange(of: viewModel.breadcrumbs.count) { _, _ in syncCTA() }
        .onChange(of: viewModel.isScanning)         { _, _ in syncCTA() }
        .onChange(of: viewModel.nodes.isEmpty)       { _, _ in syncCTA() }
    }

    // MARK: — CTA sync
    // Shows the folder name so the user always knows exactly what "Open in Finder" will reveal.
    // Tooltip shows the full tilde-abbreviated path for power users.
    private func syncCTA() {
        guard !viewModel.nodes.isEmpty && !viewModel.isScanning else {
            cta.label = ""; cta.isEnabled = false; cta.action = nil
            return
        }

        // Derive a friendly label from the current path
        let path  = viewModel.currentPath
        let tilde = (path as NSString).abbreviatingWithTildeInPath
        let name  = (path as NSString).lastPathComponent

        // Use the last breadcrumb name when drilled in, "Library" at root
        let folderName = viewModel.breadcrumbs.last?.name ?? name

        cta.label     = "Open \u{201C}\(folderName)\u{201D} in Finder"
        cta.isEnabled = true
        cta.action    = {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        // The toolbar CTA doesn't natively support a tooltip, but we store the path in
        // the accessibility hint — exposed to VoiceOver and to the help tag via the
        // ToolbarCTAHelpState workaround in ContentView.
        cta.helpText = tilde
    }

    // MARK: — Permission denied
    private var permissionDeniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)
            Text("Full Disk Access required")
                .font(.system(size: 17, weight: .semibold))
            Text("Cache Out needs Full Disk Access to analyse your disk usage.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.borderedProminent)
            Text("After granting access, press ⌘R to scan.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Breadcrumb bar
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(viewModel.rootLabel) { Task { await viewModel.popTo(index: -1) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.breadcrumbs.isEmpty ? .primary
                                     : Color(nsColor: .secondaryLabelColor))

                ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Button(crumb.name) { Task { await viewModel.popTo(index: idx) } }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(idx == viewModel.breadcrumbs.count - 1 ? .primary
                                         : Color(nsColor: .secondaryLabelColor))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Material.regular)
    }

    // MARK: — Disk footer
    private var diskFooter: some View {
        HStack(spacing: 12) {
            if viewModel.diskTotal > 0 {
                Text(formatBytes(Int64(viewModel.diskUsed)) + " used of "
                     + formatBytes(Int64(viewModel.diskTotal)))
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .monospacedDigit()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(nsColor: .separatorColor).opacity(0.4))
                        Capsule().fill(Color.accentColor)
                            .frame(width: geo.size.width * viewModel.diskPct)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8),
                                       value: viewModel.diskPct)
                    }
                }
                .frame(height: 5)
            } else {
                Text("Calculating…")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Material.regular)
    }
}

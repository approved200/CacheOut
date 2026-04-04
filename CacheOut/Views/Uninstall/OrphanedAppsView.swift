import SwiftUI

struct OrphanedAppsView: View {
    @ObservedObject var viewModel: OrphanedAppsViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @State private var showTrashConfirm = false

    @ScaledMetric(relativeTo: .title2)  private var headlineSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body)    private var bodySize: CGFloat = 13

    var body: some View {
        Group {
            if viewModel.isScanning { scanningState }
            else if viewModel.items.isEmpty { emptyState }
            else { contentView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.scanIfNeeded() }
        .onAppear { DispatchQueue.main.async { syncCTA() } }
        .onDisappear { cta.label = ""; cta.isEnabled = false; cta.action = nil; cta.helpText = "" }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.scan() }
        }
        .onChange(of: viewModel.selectedIDs.count) { _, _ in syncCTA() }
        .onChange(of: viewModel.isScanning)        { _, _ in syncCTA() }
        .confirmationDialog(
            "Move \(viewModel.selectedIDs.count) items to Trash?",
            isPresented: $showTrashConfirm, titleVisibility: .visible
        ) {
            Button("Move \(formatBytes(viewModel.totalSelectedSize)) to Trash",
                   role: .destructive) {
                Task { await viewModel.trashSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leftover support files from uninstalled apps will be moved to the Trash.")
        }
    }

    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning for orphaned files…")
                .font(.system(size: 13)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("No orphaned files found")
                .font(.system(size: headlineSize, weight: .semibold))
            Text("All support files belong to installed apps.")
                .font(.system(size: bodySize))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Info banner explaining why nothing is pre-selected
    private var heuristicNoticeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Review before removing")
                    .font(.system(size: 12, weight: .semibold))
                Text("These files weren't matched to an installed app. Check each one before selecting — some may belong to command-line tools or Mac App Store apps.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Spacer()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5))
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            // Heuristic notice — always shown so users understand nothing is pre-ticked
            heuristicNoticeBanner

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
                .padding(.horizontal, 20).padding(.top, 8)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.items) { item in
                        OrphanRow(
                            item: item,
                            isChecked: viewModel.selectedIDs.contains(item.id),
                            onToggle: { viewModel.toggle(item) }
                        )
                        if item.id != viewModel.items.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .padding(20)
            }
            Divider()
            // Status bar: count + size on left, Select All / None on right
            HStack {
                Text("\(viewModel.selectedIDs.count) of \(viewModel.items.count) selected · \(formatBytes(viewModel.totalSelectedSize))")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Button("Select all") { viewModel.selectAll() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                Text("·")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                Button("None") { viewModel.selectNone() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    private func syncCTA() {
        if viewModel.isScanning {
            cta.label = "Scanning…"; cta.isEnabled = false; cta.action = nil
        } else if viewModel.selectedIDs.isEmpty {
            cta.label = ""; cta.isEnabled = false; cta.action = nil
        } else {
            cta.label = "Remove \(formatBytes(viewModel.totalSelectedSize))"
            cta.isEnabled = true
            cta.action = { showTrashConfirm = true }
        }
    }
}

private struct OrphanRow: View {
    let item     : OrphanedItem
    let isChecked: Bool
    let onToggle : () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if item.matchConfidence == .heuristic {
                        HeuristicBadge()
                    }
                    Text(item.category)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule()
                            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3)))
                }
                Text((item.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(formatBytes(item.size))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .opacity(isChecked ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: isChecked)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            }
        }
    }
}

private struct HeuristicBadge: View {
    var body: some View {
        Label("Possible Match", systemImage: "questionmark.circle")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.12), in: Capsule())
            .help("Detected via heuristic matching — this item may not be a leftover. Review before removing.")
    }
}

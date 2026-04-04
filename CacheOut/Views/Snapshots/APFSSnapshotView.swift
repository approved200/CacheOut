import SwiftUI

struct APFSSnapshotView: View {
    @ObservedObject var viewModel: APFSSnapshotViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @State private var showDeleteConfirm = false

    @ScaledMetric(relativeTo: .title2)  private var headlineSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body)    private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11

    var body: some View {
        // Root is always a VStack — same pattern as CleanView / AnalyzeView.
        // NavigationSplitView measures the detail column from this root; keeping it
        // stable prevents the sidebar collapse on macOS 26.
        Group {
            // Interior switches — VStack shell never changes, only its contents do.
            if viewModel.isScanning {
                scanningState
            } else if viewModel.snapshots.isEmpty {
                emptyState
            } else {
                snapshotContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Yield one frame to let NavigationSplitView finish column layout
            // before triggering any @Published mutations.
            await Task.yield()
            await viewModel.scanIfNeeded()
        }
        .onAppear {
            // Defer CTA sync to avoid mutating shared ToolbarCTAState during
            // NavigationSplitView column mount (same pattern as AnalyzeView).
            DispatchQueue.main.async { syncCTA() }
        }
        .onDisappear {
            cta.label = ""; cta.isEnabled = false; cta.action = nil; cta.helpText = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.scan() }
        }
        .onChange(of: viewModel.isScanning)        { _, _ in syncCTA() }
        .onChange(of: viewModel.isDeleting)        { _, _ in syncCTA() }
        .onChange(of: viewModel.snapshots.count)   { _, _ in syncCTA() }
        .confirmationDialog(
            "Delete \(viewModel.selectedSnapshots.count) snapshot\(viewModel.selectedSnapshots.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete snapshots", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local Time Machine snapshots will be permanently deleted. This cannot be undone. Your off-site backups are not affected.")
        }
    }

    // MARK: — Snapshot content (mirrors AnalyzeView's VStack-rooted structure)
    private var snapshotContent: some View {
        VStack(spacing: 0) {
            // This VStack MUST fill the full detail column — without this frame,
            // NavigationSplitView collapses both columns when this branch renders.
            purgeableBanner
            if let err = viewModel.deleteError {
                errorBanner(err)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local Time Machine snapshots")
                            .font(.system(size: 13, weight: .semibold))
                        Text("These snapshots let Time Machine restore files between backups. Safe to delete — your off-site backup is not affected.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                    .padding(.horizontal, 20)

                    VStack(spacing: 0) {
                        ForEach(viewModel.snapshots) { snap in
                            SnapshotRow(
                                snapshot: snap,
                                onToggle: { viewModel.toggle(snap) }
                            )
                            if snap.id != viewModel.snapshots.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .padding(.top, 16)
            }
            Divider()
            HStack {
                Text("\(viewModel.snapshots.count) snapshot\(viewModel.snapshots.count == 1 ? "" : "s") · \(viewModel.selectedSnapshots.count) selected")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Purgeable space banner
    @ViewBuilder
    private var purgeableBanner: some View {
        if viewModel.purgeableBytes > 0 {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(formatBytes(viewModel.purgeableBytes)) purgeable on boot volume")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Space held by snapshots and cached files that macOS can reclaim when needed. Delete snapshots below to free it immediately.")
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
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.system(size: 12))
            Text(message).font(.system(size: 12)).lineLimit(3)
            Spacer()
            Button("Dismiss") { viewModel.deleteError = nil }
                .font(.system(size: 11)).buttonStyle(.link)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.orange.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 20).padding(.top, 8)
    }

    // MARK: — Scanning / empty states
    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning for APFS snapshots…")
                .font(.system(size: 13)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("No local snapshots found")
                .font(.system(size: headlineSize, weight: .semibold))
            Text("No local Time Machine snapshots are stored\non this machine.")
                .font(.system(size: bodySize))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
            if viewModel.purgeableBytes > 0 {
                Text("\(formatBytes(viewModel.purgeableBytes)) purgeable space available")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — CTA
    private func syncCTA() {
        if viewModel.isScanning {
            cta.label = "Scanning…"; cta.isEnabled = false; cta.action = nil
        } else if viewModel.isDeleting {
            cta.label = "Deleting…"; cta.isEnabled = false; cta.action = nil
        } else if viewModel.selectedSnapshots.isEmpty {
            cta.label = ""; cta.isEnabled = false; cta.action = nil
        } else {
            let count = viewModel.selectedSnapshots.count
            cta.label = "Delete \(count) snapshot\(count == 1 ? "" : "s")"
            cta.isEnabled = true
            cta.action = { showDeleteConfirm = true }
        }
    }
}

// MARK: — Snapshot row
private struct SnapshotRow: View {
    let snapshot: APFSSnapshot
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { snapshot.isSelected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox).labelsHidden()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayDate)
                    .font(.system(size: 13, weight: .medium))
                Text(snapshot.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(snapshot.mountPoint)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3)))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .opacity(snapshot.isSelected ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: snapshot.isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Snapshot from \(snapshot.displayDate)")
    }
}

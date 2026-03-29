import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var viewModel: DuplicatesViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @State private var showRemoveAllConfirm = false
    @AppStorage("duplicatesMinSizeKB") private var minSizeKB: Int = 1024

    private var scanRoots: [String] { PurgeViewModel.defaultScanRoots() }

    private var minSizeLabel: String {
        let kb = minSizeKB > 0 ? minSizeKB : 1024
        if kb < 1024 { return "\(kb) KB" }
        let mb = kb / 1024
        return "\(mb) MB"
    }

    var body: some View {
        Group {
            if viewModel.isScanning {
                scanningState
            } else if viewModel.groups.isEmpty {
                emptyState
            } else {
                resultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.scanIfNeeded() }
        .onAppear { DispatchQueue.main.async { syncCTA() } }
        .onDisappear { cta.label = ""; cta.isEnabled = false; cta.action = nil; cta.helpText = "" }
        .onChange(of: viewModel.isScanning)    { _, _ in syncCTA() }
        .onChange(of: viewModel.groups.count)  { _, _ in syncCTA() }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.scan(roots: scanRoots) }
        }
        .confirmationDialog(
            "Remove all duplicates?",
            isPresented: $showRemoveAllConfirm, titleVisibility: .visible
        ) {
            Button("Remove \(formatBytes(viewModel.totalSavings))", role: .destructive) {
                Task { await viewModel.removeAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The oldest copy in each group will be moved to the Trash. The first listed file in each group is kept.")
        }
    }

    // MARK: — Scanning state
    private var scanningState: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 60)
            Text(viewModel.phaseLabel)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("\(Int(viewModel.progress * 100))% complete")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Empty state
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("No duplicates found")
                .font(.system(size: 17, weight: .semibold))
            Text("Scan your project folders to find identical files\nwasting space on your Mac.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
            Text("Scanning files over \(minSizeLabel). Change in Settings → Duplicates.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
            Button("Scan now") {
                Task { await viewModel.scan(roots: scanRoots) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Results
    private var resultsView: some View {
        VStack(spacing: 0) {
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
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.groups) { group in
                        DuplicateGroupRow(group: group, onRemove: { keep in
                            Task { await viewModel.remove(keeping: keep, from: group) }
                        })
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text("\(viewModel.groups.count) duplicate groups · \(formatBytes(viewModel.totalSavings)) reclaimable · files over \(minSizeLabel)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    private func syncCTA() {
        if viewModel.isScanning {
            cta.label = "Scanning…"; cta.isEnabled = false; cta.action = nil
        } else if viewModel.groups.isEmpty {
            cta.label = "Scan now"; cta.isEnabled = true
            cta.action = { Task { await viewModel.scan(roots: scanRoots) } }
        } else {
            cta.label = "Remove \(formatBytes(viewModel.totalSavings))"
            cta.isEnabled = true
            cta.action = { showRemoveAllConfirm = true }
        }
    }
}

// MARK: — Group row
struct DuplicateGroupRow: View {
    let group   : DuplicateGroup
    let onRemove: (URL) -> Void
    @State private var isExpanded = false

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
                        Text("\(group.files[0].lastPathComponent)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .lineLimit(1)
                    }
                    Spacer()
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
                        isKeep: idx == 0,
                        fileSize: group.fileSize,
                        onTrash: { onRemove(url) }
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

// MARK: — Individual file row inside a group
private struct DuplicateFileRow: View {
    let url     : URL
    let isKeep  : Bool
    let fileSize: Int64
    let onTrash : () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isKeep ? "checkmark.circle.fill" : "trash")
                .font(.system(size: 13))
                .foregroundColor(isKeep ? .green : Color(nsColor: .secondaryLabelColor))
                .frame(width: 18)

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

            if !isKeep {
                Button(action: onTrash) {
                    Text("Remove")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Move to Trash, keep the other copy")
            } else {
                Text("Keep")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
                    .frame(width: 54)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

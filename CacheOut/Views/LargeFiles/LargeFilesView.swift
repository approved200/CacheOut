import SwiftUI

struct LargeFilesView: View {
    @ObservedObject var viewModel: LargeFilesViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @State private var itemToTrash: LargeFileItem? = nil
    @State private var showConfirm = false
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

    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning for large files…")
                .font(.system(size: 13)).foregroundColor(.secondary)
            Text("Looking for files over \(thresholdLabel)")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("No large files found")
                .font(.system(size: 17, weight: .semibold))
            Text("No files over \(thresholdLabel) found in your home folder.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text("Change the threshold in Settings → Large files.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
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
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.items) { item in
                        LargeFileRow(item: item) {
                            itemToTrash = item
                            showConfirm = true
                        }
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
            HStack {
                Text("\(viewModel.items.count) files over \(thresholdLabel)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    private func syncCTA() {
        // The toolbar already has a permanent ↺ scan button (⌘R).
        // Pushing "Scan again" here would show two identical actions side-by-side.
        // Large Files has no meaningful second action (unlike Clean's "Clean X GB"),
        // so we leave the CTA empty — the icon button is sufficient.
        cta.label = ""; cta.isEnabled = false; cta.action = nil
    }
}

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
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
            }
            Divider()
            Button("Move to Trash", role: .destructive) { onTrash() }
        }
    }
}

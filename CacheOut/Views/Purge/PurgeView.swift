import SwiftUI

struct PurgeView: View {
    @ObservedObject var viewModel: PurgeViewModel
    @EnvironmentObject private var cta: ToolbarCTAState
    @AppStorage("dryRunMode") private var dryRunMode = false

    private var scanRootsLabel: String {
        let roots = viewModel.scanRoots
        guard !roots.isEmpty else { return "No project directories found" }
        let names = roots.map { ($0 as NSString).abbreviatingWithTildeInPath }
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2) more"
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isScanning {
                // Loading state — deterministic progress bar so large roots
                // never look frozen. Each scan root completes one segment.
                VStack(spacing: 16) {
                    ProgressView(value: viewModel.scanProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 60)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.scanProgress)
                    Text("Scanning for build artifacts…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    let rootCount = viewModel.scanRoots.count
                    let doneCount = Int((viewModel.scanProgress * Double(rootCount)).rounded())
                    Text("Directory \(doneCount) of \(rootCount)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: doneCount)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.projects.isEmpty && !viewModel.isScanning {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)
                    Text("No artifacts found")
                        .font(.system(size: 17, weight: .semibold))
                    Text("No node_modules, DerivedData, or other\nbuild artifacts found in your project folders.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .multilineTextAlignment(.center)
                    Button("Scan again") { Task { await viewModel.scan() } }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Purge error banner — shown when one or more items failed to trash
                        if !viewModel.purgeErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12))
                                    Text("\(viewModel.purgeErrors.count) item\(viewModel.purgeErrors.count == 1 ? "" : "s") could not be moved to Trash")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                                ForEach(viewModel.purgeErrors, id: \.self) { err in
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
                        }

                        // Dry-run banner — only shown when mode is active
                        if dryRunMode {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Dry run mode — nothing will actually be deleted.")
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

                        ArtifactFilterPills(activeFilters: $viewModel.activeFilters)

                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                Text(scanRootsLabel)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                Button("Rescan") { Task { await viewModel.scan() } }
                                    .buttonStyle(.link)
                                    .font(.system(size: 11))
                                if viewModel.isRefreshing {
                                    ProgressView().controlSize(.mini)
                                        .transition(.opacity)
                                        .animation(.easeInOut(duration: 0.2), value: viewModel.isRefreshing)
                                }
                            }
                            Spacer()
                            Picker("", selection: $viewModel.sortOption) {
                                Text("By size").tag(0)
                                Text("By age").tag(1)
                                Text("By type").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 200)
                        }

                        // POLISH-04: explain why certain rows arrive pre-checked.
                        // @AppStorage reads the same key PurgeViewModel uses for auto-select.
                        let skipDays = UserDefaults.standard.integer(forKey: "purgeSkipRecentDays") == 0
                            ? 7 : UserDefaults.standard.integer(forKey: "purgeSkipRecentDays")
                        Text("Projects untouched for more than \(skipDays) days are pre-selected.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))

                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.filteredProjects) { project in
                                ProjectRow(
                                    item: project,
                                    isSelected: viewModel.selectedProjects.contains(project.id),
                                    onToggle: { viewModel.toggle(project) }
                                )
                            }
                        }
                    }
                    .padding(20)
                }

                Divider()
                HStack {
                    Text("\(viewModel.selectedProjects.count) of \(viewModel.projects.count) selected · \(formatBytes(viewModel.totalSize)) to purge")
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .task { await viewModel.scanIfNeeded() }
        .onAppear  { syncCTA() }
        .onDisappear { cta.label = "" }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.scan() }
        }
        .onChange(of: viewModel.totalSize)             { _, _ in syncCTA() }
        .onChange(of: viewModel.selectedProjects.count){ _, _ in syncCTA() }
        .onChange(of: viewModel.isScanning)            { _, _ in syncCTA() }
        .onChange(of: dryRunMode)                      { _, _ in syncCTA() }
    }

    private func syncCTA() {
        if viewModel.isScanning {
            cta.label = "Scanning…"; cta.isEnabled = false; cta.action = nil
        } else if viewModel.selectedProjects.isEmpty {
            cta.label = ""; cta.isEnabled = false; cta.action = nil
        } else {
            let prefix = dryRunMode ? "Simulate purge" : "Purge"
            cta.label     = "\(prefix) \(formatBytes(viewModel.totalSize))"
            cta.isEnabled = true
            cta.action    = { Task { await viewModel.purge() } }
        }
    }
}

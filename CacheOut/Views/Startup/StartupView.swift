import SwiftUI
import AppKit

struct StartupView: View {
    @ObservedObject var viewModel: StartupViewModel
    @EnvironmentObject private var cta: ToolbarCTAState

    @ScaledMetric(relativeTo: .title2)  private var headlineSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body)    private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11

    @State private var itemToRemove: StartupItem? = nil
    @State private var showRemoveConfirm = false

    private var userAgents: [StartupItem] {
        viewModel.items.filter { $0.source == .userLaunchAgent }
    }
    private var systemAgents: [StartupItem] {
        viewModel.items.filter { $0.source == .systemLaunchAgent }
    }
    private var systemDaemons: [StartupItem] {
        viewModel.items.filter { $0.source == .systemDaemon }
    }

    var body: some View {
        Group {
            if viewModel.isScanning {
                scanningState
            } else if viewModel.items.isEmpty {
                emptyState
            } else {
                contentView
            }
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
            "Remove \"\(itemToRemove?.label ?? "")\"?",
            isPresented: $showRemoveConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let item = itemToRemove { Task { await viewModel.remove(item) } }
                itemToRemove = nil
            }
            Button("Cancel", role: .cancel) { itemToRemove = nil }
        } message: {
            Text("The launch agent plist will be moved to the Trash and the item will stop running at login.")
        }
    }

    // MARK: — Content
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let err = viewModel.actionError {
                    errorBanner(err)
                }
                if !userAgents.isEmpty {
                    itemSection(title: "Login items & launch agents",
                                items: userAgents, readOnly: false)
                }
                if !systemAgents.isEmpty {
                    readOnlySection(title: "System launch agents", items: systemAgents)
                }
                if !systemDaemons.isEmpty {
                    readOnlySection(title: "System daemons", items: systemDaemons)
                }
                smAppServiceNote
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .padding(.top, 16)
        }
    }

    // MARK: — Sections
    @ViewBuilder
    private func itemSection(title: String, items: [StartupItem], readOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    StartupItemRow(
                        item: item, readOnly: readOnly,
                        onToggle: { Task { await viewModel.toggle(item) } },
                        onRemove: { itemToRemove = item; showRemoveConfirm = true }
                    )
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func readOnlySection(title: String, items: [StartupItem]) -> some View {
        DisclosureGroup {
            itemSection(title: "", items: items, readOnly: true)
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("read-only")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule()
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3)))
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: — Banners
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.system(size: 12))
            Text(message).font(.system(size: 12))
                .foregroundColor(Color(nsColor: .labelColor))
            Spacer()
            Button("Dismiss") { viewModel.actionError = nil }
                .font(.system(size: 11)).buttonStyle(.link)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.orange.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 20)
    }

    private var smAppServiceNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(.accentColor).font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Some login items aren't listed here")
                    .font(.system(size: 12, weight: .semibold))
                Text("Apps that register via macOS login item APIs can only be managed in System Settings → General → Login Items.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Spacer()
            Button("Open") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5))
    }

    // MARK: — Empty / scanning states
    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning startup items…")
                .font(.system(size: 13)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "power")
                .font(.system(size: 48)).foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("No startup items found")
                .font(.system(size: headlineSize, weight: .semibold))
            Text("No launch agents or login items were found\nin your Library folder.")
                .font(.system(size: bodySize))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncCTA() {
        cta.label = ""; cta.isEnabled = false; cta.action = nil
    }
}

// MARK: — Startup item row
private struct StartupItemRow: View {
    let item    : StartupItem
    let readOnly: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App icon or generic fallback
            Group {
                if let icon = item.associatedAppIcon {
                    Image(nsImage: icon)
                        .resizable().interpolation(.high)
                } else {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 32, height: 32)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.associatedAppName ?? item.label)
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    sourceBadge
                }
                Text(item.executablePath.isEmpty ? item.label : item.executablePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            if readOnly {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            } else {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                .buttonStyle(.plain)
                .help("Remove this launch agent")

                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(item.isEnabled
                      ? "Enabled at login — click to disable"
                      : "Disabled at login — click to enable")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.associatedAppName ?? item.label), \(item.isLoaded ? "running" : "not running")")
    }

    private var sourceBadge: some View {
        Text(item.isLoaded ? "running" : item.source.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(item.isLoaded ? .green : Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule()
                .fill(item.isLoaded
                      ? Color.green.opacity(0.12)
                      : Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                .overlay(Capsule()
                    .stroke(item.isLoaded
                            ? Color.green.opacity(0.3)
                            : Color(nsColor: .separatorColor), lineWidth: 0.5))
            )
    }
}

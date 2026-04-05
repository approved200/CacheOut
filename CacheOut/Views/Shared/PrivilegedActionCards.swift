import SwiftUI

// MARK: — PrivilegedItemCard
// Shown in CleanView's complete state for any sub-item that is system-owned.
// Displays:
//   - The Terminal command the user can copy-paste themselves
//   - A "Run with my password" button that uses PrivilegedCleanHelper
// The transparency banner explains exactly what will happen and why we need
// the password — Cache Out never stores credentials.

struct PrivilegedItemCard: View {
    let item: SubItem
    let onComplete: () -> Void

    @State private var isRunning   = false
    @State private var result      : PrivilegedItemResult? = nil
    @State private var showCommand = false

    private var terminalCommand: String { "sudo rm -rf \"\(item.path)\"" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.name) requires admin access")
                        .font(.system(size: 13, weight: .semibold))
                    Text("This path is owned by macOS. Deleting it requires your password. Cache Out never stores your credentials.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DisclosureGroup(isExpanded: $showCommand) {
                HStack(spacing: 8) {
                    Text(terminalCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(nsColor: .labelColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(terminalCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .padding(.top, 4)
            } label: {
                Text("Show Terminal command")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
            }

            if let r = result {
                HStack(spacing: 6) {
                    Image(systemName: r.success
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(r.success ? .green : .orange)
                        .font(.system(size: 12))
                    Text(r.message).font(.system(size: 12))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if result?.success != true {
                Button { Task { await runWithAuth() } } label: {
                    if isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Deleting…").font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Delete with my password", systemImage: "key.fill")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
                .disabled(isRunning)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.orange.opacity(0.2), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.2), value: result != nil)
    }

    private func runWithAuth() async {
        isRunning = true
        let errorMsg = await PrivilegedCleanHelper.deleteWithAuth(
            path: item.path, itemName: item.name)
        isRunning = false
        if let err = errorMsg {
            result = PrivilegedItemResult(success: false, message: err)
        } else {
            result = PrivilegedItemResult(
                success: true,
                message: "\(item.name) deleted — \(formatBytes(item.size)) freed")
            NotificationCenter.default.post(name: .diskFreed, object: nil)
            onComplete()
        }
    }
}

// MARK: — AppleAppUninstallCard
// Shown in AppDetailView when isAppleInstalledApp returns true.
// Same pattern: Terminal command + "Uninstall with my password" button.
// onStarted is called immediately when the user taps the button (before the
// password dialog appears) so AppDetailView can record which app is in-flight.

struct AppleAppUninstallCard: View {
    let app       : AppItem
    var onStarted : (() -> Void)? = nil   // called when button is tapped
    let onComplete: () -> Void            // called on success

    @State private var isRunning   = false
    @State private var result      : PrivilegedItemResult? = nil
    @State private var showCommand = false

    private var terminalCommand: String { "sudo rm -rf \"\(app.path)\"" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 15))
                    .foregroundColor(.orange)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple-installed app — admin required")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(app.name) is owned by macOS and cannot be removed without your administrator password. Cache Out never stores your credentials.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DisclosureGroup(isExpanded: $showCommand) {
                HStack(spacing: 8) {
                    Text(terminalCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(nsColor: .labelColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(terminalCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .padding(.top, 4)
            } label: {
                Text("Show Terminal command")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
            }

            if let r = result {
                HStack(spacing: 6) {
                    Image(systemName: r.success
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(r.success ? .green : .orange)
                        .font(.system(size: 12))
                    Text(r.message).font(.system(size: 12))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if result?.success != true {
                Button { Task { await runWithAuth() } } label: {
                    if isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Uninstalling…").font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Uninstall with my password", systemImage: "key.fill")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .disabled(isRunning)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.orange.opacity(0.2), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.2), value: result != nil)
    }

    private func runWithAuth() async {
        onStarted?()   // notify parent immediately — before the blocking password dialog
        isRunning = true
        let errorMsg = await PrivilegedCleanHelper.deleteWithAuth(
            path: app.path, itemName: app.name)
        isRunning = false
        if let err = errorMsg {
            result = PrivilegedItemResult(success: false, message: err)
        } else {
            result = PrivilegedItemResult(
                success: true,
                message: "\(app.name) removed — \(formatBytes(app.appSize)) freed")
            NotificationCenter.default.post(name: .diskFreed, object: nil)
            onComplete()
        }
    }
}

// MARK: — Shared result model (private to this file)
private struct PrivilegedItemResult {
    let success: Bool
    let message: String
}

import SwiftUI

struct AppListView: View {
    @ObservedObject var viewModel: UninstallViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search + sort
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Search apps", text: $viewModel.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 22)
                    // Tiny spinner during silent background refresh
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.isRefreshing)
                Picker("", selection: $viewModel.sortOption) {
                    Text("Name").tag(0)
                    Text("Size").tag(1)
                    Text("Last used").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)

            Divider()

            // Loading skeleton vs real list
            if viewModel.isScanning {
                loadingSkeleton
            } else if viewModel.apps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Text("No applications found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedAppId) {
                    ForEach(viewModel.filteredApps) { app in
                        AppListRow(app: app).tag(app.id)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // Animated skeleton rows while scanning
    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .separatorColor).opacity(0.5))
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .separatorColor).opacity(0.5))
                            .frame(width: CGFloat(80 + i * 12), height: 11)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                            .frame(width: 50, height: 9)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.4))
                        .frame(width: 56, height: 11)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .shimmering()

                if i < 7 { Divider() }
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: — App row
struct AppListRow: View {
    let app: AppItem

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(path: app.path)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if app.isUnused {
                        Text("Unused")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(nsColor: .systemRed))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .systemRed).opacity(0.12))
                                    .overlay(Capsule()
                                        .stroke(Color(nsColor: .systemRed).opacity(0.35),
                                                lineWidth: 0.5))
                            )
                    }
                }
                Text("v\(app.version)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }

            Spacer()

            Text(formatBytes(app.size))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.name)\(app.isUnused ? ", unused" : ""), version \(app.version), \(formatBytes(app.size))")
    }
}

// MARK: — App icon — loads once via task, never blocks the list render
struct AppIconView: View {
    let path: String
    let size: CGFloat
    @State private var icon: NSImage? = nil

    init(path: String, size: CGFloat = 32) {
        self.path = path
        self.size = size
    }

    var body: some View {
        Group {
            if let img = icon {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else {
                // Placeholder shown until icon loads
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.22)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    Image(systemName: "app.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundColor(Color(nsColor: .quaternaryLabelColor))
                }
            }
        }
        .frame(width: size, height: size)
        .task(id: path) {
            // NSImage is not Sendable, so it can't cross actor boundaries via
            // Task.detached. Instead we bridge to a plain Thread (no Swift
            // concurrency actor context) via a checked continuation, do the
            // NSWorkspace file I/O there, then resume back on the MainActor.
            let loadedIcon: NSImage? = await withCheckedContinuation { continuation in
                let t = Thread {
                    guard FileManager.default.fileExists(atPath: path) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let img = NSWorkspace.shared.icon(forFile: path)
                    img.size = NSSize(width: 64, height: 64)  // load at 2× for retina
                    continuation.resume(returning: img)
                }
                t.qualityOfService = .utility
                t.start()
            }
            if let img = loadedIcon {
                withAnimation(.easeIn(duration: 0.15)) { icon = img }
            }
        }
    }
}

// MARK: — Shimmer modifier for skeleton rows
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: phase - 0.2),
                        .init(color: (colorScheme == .dark
                              ? Color.white.opacity(0.08)
                              : Color.white.opacity(0.55)), location: phase),
                        .init(color: .clear, location: phase + 0.2),
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

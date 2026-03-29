import SwiftUI

struct MenuBarPopover: View {
    @StateObject private var monitor = SystemMonitor()

    private var memPct: Double {
        guard monitor.memoryTotal > 0 else { return 0 }
        return Double(monitor.memoryUsed) / Double(monitor.memoryTotal) * 100
    }

    private var diskPct: Double {
        guard monitor.diskTotal > 0 else { return 0 }
        return Double(monitor.diskUsed) / Double(monitor.diskTotal) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: — Quick stats row
            HStack(spacing: 24) {
                TinyGauge(title: "CPU",  value: monitor.cpuUsage, color: .accentColor,
                          label: String(format: "%.0f%%", monitor.cpuUsage))
                TinyGauge(title: "RAM",  value: memPct, color: .cyan,
                          label: String(format: "%.0f%%", memPct))
                TinyGauge(title: "Disk", value: diskPct, color: .orange,
                          label: String(format: "%.0f%%", diskPct))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Disk free line
            if monitor.diskTotal > 0 {
                Text("\(formatBytes(Int64(monitor.diskTotal - monitor.diskUsed))) free of \(formatBytes(Int64(monitor.diskTotal)))")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 14)
            }

            Divider()

            // MARK: — Quick actions
            VStack(spacing: 2) {
                MenuBarButton(title: "Quick clean", icon: "sparkles") {
                    // Switch to Clean tab and bring app forward
                    NotificationCenter.default.post(name: .switchTab, object: NavItem.clean)
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuBarButton(title: "Dev purge", icon: "hammer") {
                    NotificationCenter.default.post(name: .switchTab, object: NavItem.devPurge)
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuBarButton(title: "Open Cache Out", icon: "macwindow") {
                    NSApp.activate(ignoringOtherApps: true)
                    // Bring main window to front — find by looking for the main
                    // WindowGroup window (not Settings, not popovers).
                    if let win = NSApp.windows.first(where: {
                        $0.isVisible && $0.canBecomeMain && !($0 is NSPanel)
                    }) {
                        win.makeKeyAndOrderFront(nil)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // MARK: — Quit
            MenuBarButton(title: "Quit Cache Out", icon: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .frame(width: 280)
        .onAppear  { monitor.startMonitoring() }
        .onDisappear { monitor.stopMonitoring() }
    }
}

// MARK: — Tiny circular gauge
struct TinyGauge: View {
    let title: String
    let value: Double   // 0–100
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color(nsColor: .separatorColor),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Circle()
                    .trim(from: 0, to: CGFloat(min(value, 100) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 36, height: 36)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(label)")
    }
}

// MARK: — Menu bar action button
struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

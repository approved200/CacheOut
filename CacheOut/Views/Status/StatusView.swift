import SwiftUI

struct StatusView: View {
    @StateObject private var monitor = SystemMonitor()
    @EnvironmentObject private var cta: ToolbarCTAState

    @ScaledMetric(relativeTo: .title2) private var macNameSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body)   private var bodySize: CGFloat = 13

    private var memPct: Double {
        monitor.memoryTotal > 0 ? Double(monitor.memoryUsed) / Double(monitor.memoryTotal) : 0
    }
    private var diskPct: Double {
        monitor.diskTotal > 0 ? Double(monitor.diskUsed) / Double(monitor.diskTotal) : 0
    }
    private var uptimeString: String {
        let s = monitor.uptimeSeconds
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: Header — health gauge + machine info
                HStack(alignment: .center, spacing: 24) {
                    HealthGauge(score: monitor.healthScore)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(monitor.macModel.isEmpty ? "Mac" : friendlyModel(monitor.macModel))
                            .font(.system(size: macNameSize, weight: .semibold))
                            .lineLimit(1)

                        if !monitor.chipName.isEmpty {
                            Text(friendlyChip(monitor.chipName))
                                .font(.system(size: bodySize - 1))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                        if !monitor.ramDescription.isEmpty {
                            Text(monitor.ramDescription + " memory")
                                .font(.system(size: bodySize - 1))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                        HStack(spacing: 10) {
                            if !monitor.macOSVersion.isEmpty {
                                Text(monitor.macOSVersion)
                            }
                            if monitor.uptimeSeconds > 0 {
                                Text("↑ \(uptimeString)")
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // MARK: 2×2 metric cards
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        MetricCard(
                            title: "CPU", value: String(format: "%.1f%%", monitor.cpuUsage),
                            subtitle: "User + system", icon: "cpu", color: .accentColor,
                            progress: monitor.cpuUsage / 100
                        )
                        MetricCard(
                            title: "Memory", value: formatBytes(Int64(monitor.memoryUsed)),
                            subtitle: formatBytes(Int64(monitor.memoryTotal)) + " total",
                            icon: "memorychip", color: .cyan, progress: memPct
                        )
                    }
                    HStack(spacing: 10) {
                        MetricCard(
                            title: "Disk", value: formatBytes(Int64(monitor.diskUsed)),
                            subtitle: formatBytes(Int64(monitor.diskTotal)) + " total",
                            icon: "internaldrive", color: .orange, progress: diskPct
                        )
                        if monitor.batteryLevel >= 0 {
                            MetricCard(
                                title: "Battery", value: "\(monitor.batteryLevel)%",
                                subtitle: batterySubtitle,
                                icon: batteryIcon,
                                color: .green,
                                progress: Double(monitor.batteryLevel) / 100,
                                barColorOverride: batteryBarColor
                            )
                        } else {
                            // Desktop Mac — show live network throughput instead of a placeholder
                            MetricCard(
                                title: "Network",
                                value: "↓ \(formatBytes(monitor.netBytesInPerSec))/s",
                                subtitle: "↑ \(formatBytes(monitor.netBytesOutPerSec))/s",
                                icon: "network", color: .indigo,
                                // Progress bar shows inbound load relative to a 100 MB/s reference
                                progress: min(1.0, Double(monitor.netBytesInPerSec) / (100 * 1024 * 1024))
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)

                // MARK: Top processes
                ProcessTable(processes: monitor.topProcesses)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .onAppear  {
            monitor.startMonitoring()
            syncCTA()
        }
        .onDisappear { monitor.stopMonitoring(); cta.label = "" }
    }

    private func syncCTA() {
        cta.label     = "Go to Clean"
        cta.isEnabled = true
        cta.action    = {
            // Navigate to the Clean tab so the user sees the current state
            // and decides whether to scan. Never auto-trigger a scan from here —
            // the user must initiate it themselves via ⌘R or the toolbar button.
            NotificationCenter.default.post(name: .switchTab, object: NavItem.clean)
        }
    }

    // MARK: — Battery helpers
    // Subtitle reflects actual charge state — never "Health" which requires
    // IOKit deep-dive and doesn't belong on a live-updating card.
    private var batterySubtitle: String {
        let level = monitor.batteryLevel
        if level >= 80 { return "Charged" }
        if level >= 20 { return "Discharging" }
        return "Low — plug in soon"
    }

    // Icon tracks approximate level — matches system battery menu bar icon style
    private var batteryIcon: String {
        let level = monitor.batteryLevel
        if level > 75 { return "battery.100percent" }
        if level > 50 { return "battery.75percent" }
        if level > 25 { return "battery.50percent" }
        return "battery.25percent"
    }

    // Bar stays green at normal levels, shifts amber only below 20%
    // (inverted logic vs CPU/disk — high battery is good)
    private var batteryBarColor: Color {
        monitor.batteryLevel < 20 ? .orange : .green
    }

    // MARK: — Model helpers
    private func friendlyModel(_ raw: String) -> String {
        if raw.hasPrefix("MacBookPro")  { return "MacBook Pro" }
        if raw.hasPrefix("MacBookAir")  { return "MacBook Air" }
        if raw.hasPrefix("MacPro")      { return "Mac Pro" }
        if raw.hasPrefix("MacMini")     { return "Mac mini" }
        if raw.hasPrefix("iMac")        { return "iMac" }
        if raw.hasPrefix("Mac")         { return "Mac" }
        return raw
    }

    // Turn long CPU brand string → "Apple M3 Max" / "Intel Core i9"
    private func friendlyChip(_ raw: String) -> String {
        if raw.contains("Apple") {
            // "Apple M3 Max" — take first 3–4 words
            let words = raw.components(separatedBy: " ")
            return words.prefix(4).joined(separator: " ")
        }
        if raw.contains("Intel") {
            let words = raw.components(separatedBy: " ")
            return words.prefix(4).joined(separator: " ")
        }
        return raw
    }
}

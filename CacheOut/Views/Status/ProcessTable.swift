import SwiftUI
import AppKit

struct ProcessTable: View {
    let processes: [ProcessItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top processes")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                // Column headers
                HStack {
                    Text("Process")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU")
                        .frame(width: 64, alignment: .trailing)
                    Text("Memory")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .accessibilityHidden(true)

                Divider()

                if processes.isEmpty {
                    Text("Fetching processes…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    // Build icon cache once per render — avoids O(n) scan per row per redraw
                    let iconCache: [Int: NSImage] = {
                        var cache: [Int: NSImage] = [:]
                        let running = NSWorkspace.shared.runningApplications
                        for proc in processes {
                            if let app = running.first(where: {
                                $0.processIdentifier == pid_t(proc.pid) ||
                                $0.localizedName == proc.name
                            }), let icon = app.icon {
                                cache[proc.pid] = icon
                            }
                        }
                        return cache
                    }()

                    ForEach(processes) { proc in
                        ProcessRow(proc: proc, icon: iconCache[proc.pid])
                        if proc.id != processes.last?.id { Divider() }
                    }
                }
            }
            .background(Material.regular, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

private struct ProcessRow: View {
    let proc: ProcessItem
    let icon: NSImage?   // pre-resolved by ProcessTable — no per-render lookup

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.trailing, 8)
            .accessibilityHidden(true)

            Text(proc.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", proc.cpu))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(proc.cpu > 30 ? .orange : Color(nsColor: .labelColor))
                .contentTransition(.numericText(value: proc.cpu))
                .frame(width: 64, alignment: .trailing)
                .monospacedDigit()

            Text(proc.memoryString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 80, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(proc.name), CPU \(String(format: "%.1f", proc.cpu)) percent, memory \(proc.memoryString)")
        .contextMenu {
            Button("Show in Activity Monitor") {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Divider()
            Button("Force Quit \(proc.name)", role: .destructive) {
                if let app = NSWorkspace.shared.runningApplications.first(where: {
                    $0.processIdentifier == pid_t(proc.pid)
                }) {
                    app.forceTerminate()
                }
            }
        }
    }
}

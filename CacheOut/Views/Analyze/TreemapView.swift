import SwiftUI

struct TreemapView: View {
    let nodes: [DiskNode]
    let onDrillDown: (DiskNode) -> Void
    /// Called when the user confirms trashing a node. The parent view owns
    /// the confirmation dialog and rescan so the treemap stays stateless.
    var onTrash: ((DiskNode) -> Void)? = nil

    // A palette of accent shades that degrades gracefully for many items
    private let palette: [Color] = [
        .accentColor,
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemBlue).opacity(0.7),
        Color(nsColor: .systemIndigo),
        Color(nsColor: .systemTeal),
        Color(nsColor: .systemPink).opacity(0.8),
        Color(nsColor: .systemGreen).opacity(0.8),
        Color(nsColor: .systemPurple).opacity(0.7),
    ]

    // Squarified treemap layout (simplified row-based)
    var body: some View {
        GeometryReader { geo in
            let layout = squarify(nodes: nodes, rect: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.enumerated()), id: \.offset) { idx, item in
                    let isStale = (item.node.ageDays ?? 0) > 180
                    let color: Color = isStale
                        ? Color(nsColor: .systemRed)
                        : palette[idx % palette.count]
                    TreemapCell(
                        node: item.node,
                        color: color,
                        frame: item.rect,
                        onTap: { onDrillDown(item.node) },
                        onTrash: onTrash
                    )
                    .frame(width: max(0, item.rect.width - 4),
                           height: max(0, item.rect.height - 4))
                    .offset(x: item.rect.minX + 2, y: item.rect.minY + 2)
                }
            }
        }
    }

    // MARK: — Layout engine: simple row-based squarification
    struct LayoutItem { let node: DiskNode; let rect: CGRect }

    func squarify(nodes: [DiskNode], rect: CGRect) -> [LayoutItem] {
        guard !nodes.isEmpty else { return [] }
        let totalSize = nodes.reduce(0.0) { $0 + Double($1.size) }
        guard totalSize > 0 else { return [] }
        let totalArea = Double(rect.width * rect.height)

        var result: [LayoutItem] = []
        var remaining = nodes
        var availRect = rect

        while !remaining.isEmpty {
            // Pick the larger dimension as the strip
            let horizontal = availRect.width >= availRect.height
            let stripLen   = horizontal ? availRect.width : availRect.height

            // Greedily fill one row/column
            var row: [DiskNode] = []
            var rowArea: Double = 0

            for node in remaining {
                let nodeArea = Double(node.size) / totalSize * totalArea
                rowArea += nodeArea
                row.append(node)
                // Stop when adding more would hurt the aspect ratio
                let rowCross = rowArea / Double(stripLen)
                let worstBefore = worstRatio(row: row, rowArea: rowArea,
                                             rowCross: rowCross, stripLen: Double(stripLen))
                if row.count > 1 {
                    let prevArea = rowArea - Double(row.last?.size ?? 0) / totalSize * totalArea
                    let prevCross = prevArea / Double(stripLen)
                    let worstBefore2 = worstRatio(row: Array(row.dropLast()),
                                                  rowArea: prevArea, rowCross: prevCross,
                                                  stripLen: Double(stripLen))
                    if worstBefore2 < worstBefore { row.removeLast(); rowArea = prevArea; break }
                }
            }
            remaining = Array(remaining.dropFirst(row.count))

            // Layout the row
            let rowCross = rowArea / Double(stripLen)
            var offset: CGFloat = 0
            for node in row {
                let nodeArea = Double(node.size) / totalSize * totalArea
                let nodeLen  = CGFloat(nodeArea / rowCross)
                let r: CGRect = horizontal
                    ? CGRect(x: availRect.minX + offset, y: availRect.minY,
                             width: nodeLen, height: CGFloat(rowCross))
                    : CGRect(x: availRect.minX, y: availRect.minY + offset,
                             width: CGFloat(rowCross), height: nodeLen)
                result.append(LayoutItem(node: node, rect: r))
                offset += nodeLen
            }

            // Shrink availRect
            availRect = horizontal
                ? CGRect(x: availRect.minX, y: availRect.minY + CGFloat(rowCross),
                         width: availRect.width, height: availRect.height - CGFloat(rowCross))
                : CGRect(x: availRect.minX + CGFloat(rowCross), y: availRect.minY,
                         width: availRect.width - CGFloat(rowCross), height: availRect.height)
        }
        return result
    }

    private func worstRatio(row: [DiskNode], rowArea: Double, rowCross: Double, stripLen: Double) -> Double {
        row.map { node -> Double in
            let area = Double(node.size) / row.reduce(0.0) { $0 + Double($1.size) } * rowArea
            let w = area / rowCross
            let h = rowCross
            let ratio = max(w, h) / min(w, h)
            return ratio
        }.max() ?? 1
    }
}

// MARK: — Individual treemap cell
struct TreemapCell: View {
    let node: DiskNode
    let color: Color
    let frame: CGRect
    let onTap: () -> Void
    /// Callback fired when user picks "Move to Trash" from context menu.
    /// The parent owns the confirmation dialog — this cell just signals intent.
    var onTrash: ((DiskNode) -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(isHovered ? 0.85 : 1.0))

            if frame.width > 60 && frame.height > 40 {
                VStack(spacing: 2) {
                    Text(node.name)
                        .font(.system(size: labelSize(frame), weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)

                    if frame.height > 60 {
                        Text(formatBytes(node.size))
                            .font(.system(size: max(9, labelSize(frame) - 2),
                                         design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(6)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }   // single-click to drill down (macOS convention)
        .contextMenu {
            Button("Open in Finder") {
                NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
            }
            Button("Get Info") {
                let script = "tell application \"Finder\" to open information window of (POSIX file \"\(node.path)\" as alias)"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            }
            Divider()
            Button(role: .destructive) {
                // Delegate to parent — parent shows confirmation and handles the actual trash
                onTrash?(node)
            } label: { Text("Move to Trash") }
        }
        .help("\(node.name) — \(formatBytes(node.size))")
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name), \(formatBytes(node.size))\((node.ageDays ?? 0) > 180 ? ", stale" : "")")
        .accessibilityHint("Click to drill down")
        .accessibilityAction(named: "Drill down") { onTap() }
    }

    private func labelSize(_ frame: CGRect) -> CGFloat {
        min(14, max(10, frame.width / 10))
    }
}

import SwiftUI

struct ProjectRow: View {
    let item: ProjectItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))

                    // Artifact type badge
                    Text(item.type.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(item.type.color.opacity(0.15)))
                        .foregroundColor(item.type.color)

                    // Recent indicator
                    if item.lastModifiedDaysAgo < 7 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text("Recent — skipped")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .help("Modified \(item.lastModifiedDaysAgo == 0 ? "today" : "\(item.lastModifiedDaysAgo)d ago") — auto-deselected to protect active work. You can still select it manually.")
                    }
                }

                HStack(spacing: 5) {
                    Text(relativeDaysAgo(item.lastModifiedDaysAgo))
                        .font(.system(size: 11, weight: .regular))
                    Text("·")
                    Text(item.path)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }

            Spacer()

            Text(byteFormatter.string(fromByteCount: item.size))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        // Dim recent projects that aren't selected (protect from accidental deletion)
        .opacity(item.lastModifiedDaysAgo < 7 && !isSelected ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.type.rawValue), \(byteFormatter.string(fromByteCount: item.size))")
        .accessibilityValue(isSelected ? "selected, \(relativeDaysAgo(item.lastModifiedDaysAgo))" : "deselected, \(relativeDaysAgo(item.lastModifiedDaysAgo))")
        .accessibilityHint(item.lastModifiedDaysAgo < 7 ? "Recent project — be careful" : "Double-tap to toggle selection")
    }
}

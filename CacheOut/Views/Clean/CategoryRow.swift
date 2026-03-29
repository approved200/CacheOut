import SwiftUI

struct CategoryRow: View {
    @Binding var item: CategoryItem
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header row
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { item.isSelected }, set: { _ in onToggle() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                Image(systemName: item.category.icon)
                    .foregroundColor(item.category.color)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)

                Text(item.category.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text("(\(item.subItems.count) items)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))

                Spacer()

                Text(byteFormatter.string(fromByteCount: item.size))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(item.category.color)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .rotationEffect(.degrees(item.isExpanded ? 90 : 0))
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.8),
                        value: item.isExpanded
                    )
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8)) {
                    item.isExpanded.toggle()
                }
            }

            // MARK: Sub-items (expanded)
            if item.isExpanded {
                Divider().padding(.horizontal, 12)

                VStack(spacing: 0) {
                    ForEach(item.subItems) { sub in
                        SubItemRow(item: sub)
                        if sub.id != item.subItems.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .opacity(item.isSelected ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.15), value: item.isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.category.rawValue), \(formatBytes(item.size))")
        .accessibilityValue(item.isSelected ? "selected" : "deselected")
        .accessibilityHint("Double-tap to \(item.isExpanded ? "collapse" : "expand")")
    }
}

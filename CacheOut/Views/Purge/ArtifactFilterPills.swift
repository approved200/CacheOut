import SwiftUI

struct ArtifactFilterPills: View {
    @Binding var activeFilters: Set<ArtifactType>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ArtifactType.allCases) { type in
                    PillButton(
                        type: type,
                        isActive: activeFilters.contains(type),
                        reduceMotion: reduceMotion
                    ) {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.72)) {
                            if activeFilters.contains(type) {
                                activeFilters.remove(type)
                            } else {
                                activeFilters.insert(type)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct PillButton: View {
    let type: ArtifactType
    let isActive: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(type.rawValue)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isActive ? .white : Color(nsColor: .labelColor))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isActive ? type.color : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            Capsule()
                                .stroke(
                                    isActive ? Color.clear : Color(nsColor: .separatorColor),
                                    lineWidth: 0.5
                                )
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: isActive)
    }
}

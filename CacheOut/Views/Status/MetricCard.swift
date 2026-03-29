import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double // 0.0–1.0
    /// When set, overrides the automatic red/orange threshold colouring.
    /// Use for metrics where high values are good (e.g. battery).
    var barColorOverride: Color? = nil

    // Progress bar color shifts when usage is high — unless caller overrides
    private var barColor: Color {
        if let override = barColorOverride { return override }
        return progress > 0.9 ? .red : progress > 0.75 ? .orange : color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: icon + title + value
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))

                Spacer()

                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor).opacity(0.35))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * CGFloat(min(progress, 1))))
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 5)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Liquid Glass: use glass material so cards float with Tahoe translucency
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityValue("\(subtitle), \(Int(progress * 100)) percent used")
    }
}

import SwiftUI

// A polished health score arc gauge — 270° sweep, round caps, live color.
struct HealthGauge: View {
    let score: Int

    private var gaugeColor: Color {
        score >= 80 ? .green : score >= 50 ? .orange : .red
    }
    // Arc goes from 135° to 405° (270° sweep). trim(from:to:) maps 0→1 to that.
    private var fill: Double { min(1.0, Double(score) / 100.0) * 0.75 }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .frame(width: 110, height: 110)

            // Fill
            Circle()
                .trim(from: 0, to: fill)
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .frame(width: 110, height: 110)
                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: fill)

            // Score + label
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText(value: Double(score)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: score)
                Text("Health")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.none)
            }
        }
        .frame(width: 110, height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System health score")
        .accessibilityValue("\(score) out of 100 — \(score >= 80 ? "good" : score >= 50 ? "fair" : "poor")")
    }
}

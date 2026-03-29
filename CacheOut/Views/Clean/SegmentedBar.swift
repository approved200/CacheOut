import SwiftUI

// Multi-colour segmented storage bar — Apple "About This Mac" style.
// Reads isSelected directly from each CategoryItem (single source of truth).
struct SegmentedBar: View {
    let data: [CategoryItem]

    private let gapWidth: CGFloat  = 2
    private let barHeight: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let nonZero   = data.filter { $0.size > 0 }
            let totalSize = CGFloat(nonZero.reduce(0) { $0 + $1.size })
            let gapTotal  = CGFloat(max(0, nonZero.count - 1)) * gapWidth
            let available = max(0, geo.size.width - gapTotal)

            HStack(spacing: gapWidth) {
                ForEach(data) { item in
                    if item.size > 0 {
                        let frac  = totalSize > 0 ? CGFloat(item.size) / totalSize : 0
                        let width = max(4, available * frac)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.category.color)
                            .frame(width: width, height: barHeight)
                            .opacity(item.isSelected ? 1.0 : 0.2)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8),
                                       value: item.isSelected)
                    }
                }
            }
        }
        .frame(height: barHeight)
    }
}

// Legend row — also reads isSelected directly from CategoryItem.
struct SegmentedBarLegend: View {
    let data: [CategoryItem]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(data) { item in
                if item.size > 0 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.category.color)
                            .frame(width: 8, height: 8)
                        Text(item.category.rawValue)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                    .opacity(item.isSelected ? 1.0 : 0.3)
                }
            }
        }
    }
}

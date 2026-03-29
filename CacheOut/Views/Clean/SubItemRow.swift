import SwiftUI

struct SubItemRow: View {
    let item: SubItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 40pt indent to align with category row content
            Color.clear.frame(width: 40, height: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)

                Text(item.path)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(byteFormatter.string(fromByteCount: item.size))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(byteFormatter.string(fromByteCount: item.size))")
        .accessibilityValue(item.path)
    }
}

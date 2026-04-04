import SwiftUI

struct SubItemRow: View {
    let item: SubItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 40pt indent to align with category row content
            Color.clear.frame(width: 40, height: 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)

                    // Lock badge — shown for system-owned paths that cannot
                    // be trashed by a user process (e.g. /private/var/log).
                    // Full Disk Access grants read but not write to these paths.
                    if item.isReadOnly {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .semibold))
                            Text("macOS managed")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                        )
                        .help("macOS owns this path. It can be read but not deleted by user apps, even with Full Disk Access.")
                    }
                }

                Text(item.path)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(byteFormatter.string(fromByteCount: item.size))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(item.isReadOnly
                    ? Color(nsColor: .tertiaryLabelColor)
                    : Color(nsColor: .secondaryLabelColor))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(byteFormatter.string(fromByteCount: item.size))\(item.isReadOnly ? ", macOS managed — cannot be deleted" : "")")
        .accessibilityValue(item.path)
    }
}

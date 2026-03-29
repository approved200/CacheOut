import SwiftUI
import AppKit

// MARK: — Volume model
struct VolumeInfo: Identifiable, Equatable {
    let id          = UUID()
    let url         : URL
    let name        : String
    let totalBytes  : Int64
    let freeBytes   : Int64
    let isBootVolume: Bool

    var usedBytes: Int64 { totalBytes - freeBytes }
    var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

// MARK: — VolumePicker
// A horizontal strip of volume chips shown at the top of AnalyzeView.
// Selecting a chip updates AnalyzeViewModel.rootPath and triggers a rescan.
struct VolumePicker: View {
    @ObservedObject var viewModel: AnalyzeViewModel
    @State private var volumes: [VolumeInfo] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(volumes) { vol in
                    VolumeChip(
                        volume: vol,
                        isSelected: viewModel.rootPath == vol.url.path
                    ) {
                        if viewModel.rootPath != vol.url.path {
                            viewModel.rootPath = vol.url.path
                            viewModel.breadcrumbs = []
                            Task { await viewModel.rescan() }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear { volumes = Self.enumerateVolumes() }
    }

    // Enumerate mounted volumes, boot volume first
    static func enumerateVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRootFileSystemKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        let home = URL(fileURLWithPath: NSHomeDirectory())
        var result: [VolumeInfo] = []

        for url in urls {
            guard let res = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name  = res.volumeName ?? url.lastPathComponent
            let total = Int64(res.volumeTotalCapacity ?? 0)
            let free  = Int64(res.volumeAvailableCapacity ?? 0)
            guard total > 0 else { continue }

            // Boot volume = volume that contains the home directory
            let isBoot = home.path.hasPrefix(url.path)
            result.append(VolumeInfo(
                url: url, name: name, totalBytes: total,
                freeBytes: free, isBootVolume: isBoot
            ))
        }
        // Boot volume first, then alphabetical
        return result.sorted { a, b in
            if a.isBootVolume != b.isBootVolume { return a.isBootVolume }
            return a.name < b.name
        }
    }
}

// MARK: — Individual volume chip
private struct VolumeChip: View {
    let volume    : VolumeInfo
    let isSelected: Bool
    let onTap     : () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: volume.isBootVolume ? "internaldrive.fill" : "externaldrive.fill")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white : .accentColor)
                    Text(volume.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? .white : Color(nsColor: .labelColor))
                        .lineLimit(1)
                }
                // Capacity bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isSelected
                                  ? Color.white.opacity(0.25)
                                  : Color(nsColor: .separatorColor).opacity(0.4))
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.85) : Color.accentColor)
                            .frame(width: geo.size.width * volume.usedFraction)
                    }
                }
                .frame(height: 3)

                Text(formatBytes(volume.totalBytes))
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.75) : Color(nsColor: .secondaryLabelColor))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 120)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor
                          : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected
                                    ? Color.clear
                                    : Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(volume.name), \(formatBytes(volume.totalBytes)) total")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

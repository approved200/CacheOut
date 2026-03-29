import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavItem?
    // highlightedTab is no longer needed — the tour drives selectedTab in
    // ContentView directly, so the List's native selection renders the
    // system filled-blue-capsule highlight automatically. Parameter kept
    // for call-site compatibility but intentionally unused.
    var highlightedTab: NavItem? = nil

    var body: some View {
        List(selection: $selection) {

            Section {
                Label("Clean",       systemImage: "sparkles")    .tag(NavItem.clean)
                Label("Uninstall",   systemImage: "shippingbox") .tag(NavItem.uninstall)
                Label("Leftovers",   systemImage: "shippingbox.and.arrow.backward").tag(NavItem.orphaned)
                Label("Large Files", systemImage: "doc.zipper")  .tag(NavItem.largeFiles)
                Label("Duplicates",  systemImage: "doc.on.doc")  .tag(NavItem.duplicates)
            }

            Section {
                Label("Analyze",   systemImage: "chart.pie")            .tag(NavItem.analyze)
                Label("Snapshots", systemImage: "clock.arrow.circlepath").tag(NavItem.snapshots)
                Label("Dev Purge", systemImage: "hammer")               .tag(NavItem.devPurge)
            }

            Section {
                Label("Startup", systemImage: "power")                            .tag(NavItem.startup)
                Label("Status",  systemImage: "gauge.with.dots.needle.33percent") .tag(NavItem.status)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { oldVal, newVal in
            SidebarLogger.log("SidebarView.selection changed: \(String(describing: oldVal)) → \(String(describing: newVal))")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { settingsFooter }
        .onAppear {
            SidebarLogger.clear()
            SidebarLogger.log("SidebarView appeared. initial selection=\(String(describing: selection))")
        }
    }

    private var settingsFooter: some View {
        SettingsLink {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                Text("Settings")
                    .font(.system(size: 13, weight: .regular))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .padding(.bottom, 22)
    }
}

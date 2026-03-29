import SwiftUI

struct UninstallView: View {
    @ObservedObject var viewModel: UninstallViewModel
    @State private var isDragTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            AppListView(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 270, maxWidth: 310)

            Divider()

            // Right: detail
            AppDetailView(
                selectedApp: viewModel.apps.first { $0.id == viewModel.selectedAppId },
                onUninstalled: { id in viewModel.apps.removeAll { $0.id == id } }
            )
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(8)
                    .opacity(isDragTargeted ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers)
            }
        }
        .task { await viewModel.scanIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScan)) { _ in
            Task { await viewModel.scan() }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                guard let data = item as? Data,
                      let url  = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension == "app" else { return }
                Task { @MainActor in
                    let name = url.deletingPathExtension().lastPathComponent
                    let newApp = AppItem(name: name, path: url.path, version: "—",
                                        lastUsed: Date(), size: 0, isUnused: false)
                    viewModel.apps.insert(newApp, at: 0)
                    viewModel.selectedAppId = newApp.id
                }
            }
        }
        return true
    }
}

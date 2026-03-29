import SwiftUI

@MainActor
class UninstallViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var selectedAppId: UUID?
    @Published var searchQuery: String = ""
    @Published var sortOption: Int = 1
    @Published var isScanning = false
    @Published var isRefreshing = false   // silent background refresh
    @Published var lastScanned: Date? = nil

    private let scanner = AppScanner()
    private let staleDuration: TimeInterval = 5 * 60   // 5 min

    var filteredApps: [AppItem] {
        var result = apps
        if !searchQuery.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }
        switch sortOption {
        case 0: result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case 1: result.sort { $0.size > $1.size }
        case 2: result.sort { $0.lastUsed > $1.lastUsed }
        default: break
        }
        return result
    }

    // MARK: — Smart entry point: instant if cached, silent-refresh if stale
    func scanIfNeeded() async {
        if isScanning || isRefreshing { return }

        if apps.isEmpty {
            // First load — show spinner
            await scan()
        } else if let last = lastScanned,
                  Date().timeIntervalSince(last) > staleDuration {
            // Stale — refresh silently, keep showing existing list
            await backgroundRefresh()
        }
        // Otherwise: data is fresh, do nothing
    }

    // MARK: — Force full scan (explicit user action)
    func scan(unusedDays: Int? = nil) async {
        // Always read the current setting so a change in Settings takes effect immediately
        let days = unusedDays ?? UserDefaults.standard.integer(forKey: "unusedAppDays").nonZero ?? 90
        isScanning = true
        let fresh = await scanner.scanApplications(unusedDays: days)
        apps = fresh
        isScanning = false
        lastScanned = Date()
        if selectedAppId == nil || !apps.contains(where: { $0.id == selectedAppId }) {
            selectedAppId = filteredApps.first?.id
        }
    }

    // MARK: — Silent background refresh — existing list stays visible
    private func backgroundRefresh() async {
        let days = UserDefaults.standard.integer(forKey: "unusedAppDays").nonZero ?? 90
        isRefreshing = true
        let fresh = await scanner.scanApplications(unusedDays: days)
        // Preserve selected app if it still exists in the new list
        let selectedPath = apps.first(where: { $0.id == selectedAppId })?.path
        apps = fresh
        lastScanned = Date()
        if let path = selectedPath,
           let match = apps.first(where: { $0.path == path }) {
            selectedAppId = match.id
        } else {
            selectedAppId = filteredApps.first?.id
        }
        isRefreshing = false
    }
}

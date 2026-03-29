import Foundation
import ServiceManagement
import OSLog

struct LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
    }

    /// Attempts to register or unregister for launch at login.
    /// Returns nil on success, a human-readable error string on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return nil }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            CacheOutLogger.clean.error("LaunchAtLogin failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}

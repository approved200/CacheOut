import Foundation

// ByteCountFormatter is not Sendable in Swift 6.
// We keep the @MainActor instance for any call sites already on the main actor
// (e.g. CategoryRow, SubItemRow which use `byteFormatter` directly).
@MainActor
let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useGB, .useMB, .useKB]
    f.countStyle = .file
    return f
}()

// Shared nonisolated formatter for formatBytes().
// nonisolated(unsafe) is correct here: the formatter is fully configured before
// first use and is only ever READ after that — no mutation at call sites.
// This avoids allocating a new ByteCountFormatter on every call, which was
// happening across every list row in the app (200 large files, 40 apps, etc.).
private nonisolated(unsafe) let _sharedFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useGB, .useMB, .useKB]
    f.countStyle = .file
    return f
}()

// Nonisolated helper callable from any context without hopping to MainActor.
nonisolated func formatBytes(_ bytes: Int64) -> String {
    _sharedFormatter.string(fromByteCount: bytes)
}

// Relative date helper
func relativeDaysAgo(_ days: Int) -> String {
    switch days {
    case 0:        return "Today"
    case 1:        return "Yesterday"
    case 2...6:    return "\(days) days ago"
    case 7...30:   return "\(days / 7) week\(days / 7 == 1 ? "" : "s") ago"
    case 31...364: return "\(days / 30) month\(days / 30 == 1 ? "" : "s") ago"
    default:       return "\(days / 365) year\(days / 365 == 1 ? "" : "s") ago"
    }
}

// Convenience: return nil if Int is zero (useful for UserDefaults fallback chains)
extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

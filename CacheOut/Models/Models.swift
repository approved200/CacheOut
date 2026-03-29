import SwiftUI
import Foundation

// MARK: — Clean Categories
enum CleanCategory: String, CaseIterable, Identifiable {
    case dev     = "Developer caches"
    case browser = "Browser data"
    case system  = "System junk"
    case app     = "Application cache"
    case trash   = "Trash"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dev:     return "chevron.left.forwardslash.chevron.right"
        case .browser: return "globe"
        case .system:  return "desktopcomputer"
        case .app:     return "app.badge.checkmark"
        case .trash:   return "trash"
        }
    }

    var color: Color {
        switch self {
        case .dev:     return .purple
        case .browser: return .blue
        case .system:  return .orange
        case .app:     return .green
        case .trash:   return .red
        }
    }
}

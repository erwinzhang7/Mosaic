import Foundation

/// Top-level mode the overlay is currently displaying. Resets to `.apps` on
/// every summon — windows mode is opt-in per summon.
enum OverlayMode: String, Hashable, CaseIterable {
    case apps, windows

    var label: String {
        switch self {
        case .apps:    return "Apps"
        case .windows: return "Windows"
        }
    }
}

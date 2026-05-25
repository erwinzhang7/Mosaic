import Foundation

/// Which screen corner triggers the summon when hot-corner mode is enabled.
enum HotCorner: String, CaseIterable, Codable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var label: String {
        switch self {
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

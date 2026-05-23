import Foundation
import Observation

/// Lightweight scalar preferences (icon size, column width). Stored in
/// `UserDefaults` — `LayoutStore` handles the heavier structured layout.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    var iconSize: Double {
        didSet { defaults.set(iconSize, forKey: Keys.iconSize) }
    }

    var columnMinWidth: Double {
        didSet { defaults.set(columnMinWidth, forKey: Keys.columnMinWidth) }
    }

    var verticalScroll: Bool {
        didSet { defaults.set(verticalScroll, forKey: Keys.verticalScroll) }
    }

    private init() {
        iconSize = (defaults.object(forKey: Keys.iconSize) as? Double) ?? 80
        columnMinWidth = (defaults.object(forKey: Keys.columnMinWidth) as? Double) ?? 112
        verticalScroll = (defaults.object(forKey: Keys.verticalScroll) as? Bool) ?? true
    }

    private enum Keys {
        static let iconSize = "iconSize"
        static let columnMinWidth = "columnMinWidth"
        static let verticalScroll = "verticalScroll"
    }
}

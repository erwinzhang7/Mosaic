import Foundation
import Observation

/// Lightweight scalar preferences (icon size, column width, trigger settings).
/// Stored in `UserDefaults` — `LayoutStore` handles the heavier structured
/// layout overrides.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // MARK: Appearance

    var iconSize: Double {
        didSet { defaults.set(iconSize, forKey: Keys.iconSize) }
    }

    var columnMinWidth: Double {
        didSet { defaults.set(columnMinWidth, forKey: Keys.columnMinWidth) }
    }

    var verticalScroll: Bool {
        didSet { defaults.set(verticalScroll, forKey: Keys.verticalScroll) }
    }

    // MARK: Hot corner trigger

    var hotCornerEnabled: Bool {
        didSet { defaults.set(hotCornerEnabled, forKey: Keys.hotCornerEnabled) }
    }

    var hotCorner: HotCorner {
        didSet { defaults.set(hotCorner.rawValue, forKey: Keys.hotCorner) }
    }

    /// Dwell in seconds before a hovered corner fires.
    var hotCornerDwell: Double {
        didSet { defaults.set(hotCornerDwell, forKey: Keys.hotCornerDwell) }
    }

    // MARK: Pinch trigger

    var pinchEnabled: Bool {
        didSet { defaults.set(pinchEnabled, forKey: Keys.pinchEnabled) }
    }

    var pinchDirection: PinchDirection {
        didSet { defaults.set(pinchDirection.rawValue, forKey: Keys.pinchDirection) }
    }

    private init() {
        iconSize = (defaults.object(forKey: Keys.iconSize) as? Double) ?? 80
        columnMinWidth = (defaults.object(forKey: Keys.columnMinWidth) as? Double) ?? 112
        verticalScroll = (defaults.object(forKey: Keys.verticalScroll) as? Bool) ?? true

        hotCornerEnabled = (defaults.object(forKey: Keys.hotCornerEnabled) as? Bool) ?? false
        hotCorner = HotCorner(rawValue: defaults.string(forKey: Keys.hotCorner) ?? "") ?? .topLeft
        hotCornerDwell = (defaults.object(forKey: Keys.hotCornerDwell) as? Double) ?? 0.2

        pinchEnabled = (defaults.object(forKey: Keys.pinchEnabled) as? Bool) ?? false
        pinchDirection = PinchDirection(rawValue: defaults.string(forKey: Keys.pinchDirection) ?? "") ?? .open
    }

    private enum Keys {
        static let iconSize = "iconSize"
        static let columnMinWidth = "columnMinWidth"
        static let verticalScroll = "verticalScroll"

        static let hotCornerEnabled = "hotCornerEnabled"
        static let hotCorner = "hotCorner"
        static let hotCornerDwell = "hotCornerDwell"

        static let pinchEnabled = "pinchEnabled"
        static let pinchDirection = "pinchDirection"
    }
}

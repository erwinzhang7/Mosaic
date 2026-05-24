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

    // MARK: F4 trigger

    var f4Enabled: Bool {
        didSet { defaults.set(f4Enabled, forKey: Keys.f4Enabled) }
    }

    // MARK: Uninstall

    /// Master toggle for the destructive uninstall feature. When OFF, the
    /// "Uninstall…" item doesn't appear in the app context menu at all.
    var uninstallEnabled: Bool {
        didSet { defaults.set(uninstallEnabled, forKey: Keys.uninstallEnabled) }
    }

    /// When ON, the uninstall flow computes the preview and goes through both
    /// gates but the final "Move to Trash" call is a logging no-op. For
    /// end-to-end exercise without deleting anything.
    var uninstallSimulate: Bool {
        didSet { defaults.set(uninstallSimulate, forKey: Keys.uninstallSimulate) }
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

        f4Enabled = (defaults.object(forKey: Keys.f4Enabled) as? Bool) ?? false

        uninstallEnabled = (defaults.object(forKey: Keys.uninstallEnabled) as? Bool) ?? false
        uninstallSimulate = (defaults.object(forKey: Keys.uninstallSimulate) as? Bool) ?? false
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

        static let f4Enabled = "f4Enabled"

        static let uninstallEnabled = "uninstallEnabled"
        static let uninstallSimulate = "uninstallSimulate"
    }
}

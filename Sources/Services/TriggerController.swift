import AppKit

/// Owns the input-monitoring side of the opt-in trigger features (hot corner,
/// pinch). Reads the user's settings from `Preferences.shared`, gates them on
/// `AccessibilityPermission.shared`, and starts/stops the underlying watchers
/// accordingly.
///
/// `applyCurrentSettings()` is the single entry point — call it on app launch,
/// after any settings change, and on permission flips. The notification
/// observer in `init()` covers the permission-flip case automatically.
@MainActor
final class TriggerController {
    static let shared = TriggerController()

    /// Set by `AppDelegate` on launch. Called by either watcher when its
    /// gesture matches; both go through the same summon path as the hotkey.
    var summon: () -> Void = {}

    private lazy var hotCornerWatcher = HotCornerWatcher { [weak self] in
        self?.summon()
    }

    private lazy var pinchWatcher = PinchWatcher { [weak self] in
        self?.summon()
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: .mosaicAccessibilityPermissionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyCurrentSettings() }
        }
    }

    /// Read Preferences + permission state and start/stop each watcher to
    /// match. Cheap and idempotent — safe to call from any settings .onChange.
    func applyCurrentSettings() {
        let prefs = Preferences.shared
        let trusted = AccessibilityPermission.shared.isTrusted

        if prefs.hotCornerEnabled && trusted {
            hotCornerWatcher.corner = prefs.hotCorner
            hotCornerWatcher.dwellSeconds = prefs.hotCornerDwell
            hotCornerWatcher.start()
        } else {
            hotCornerWatcher.stop()
        }

        if prefs.pinchEnabled && trusted {
            pinchWatcher.direction = prefs.pinchDirection
            pinchWatcher.start()
        } else {
            pinchWatcher.stop()
        }
    }
}

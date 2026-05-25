import AppKit

/// Owns the input-monitoring side of the opt-in trigger features. Currently
/// just hot corner — F4 (Search key) and 4-finger pinch were attempted but
/// removed because macOS 26 routes both gestures at a layer that public
/// APIs can't intercept. See the project README / commit history for the
/// "C" option (private MultitouchSupport framework) if either ever becomes
/// worth the maintenance burden.
///
/// Reads the user's settings from `Preferences.shared`, gates them on
/// `AccessibilityPermission.shared`, and starts/stops the underlying watcher.
/// `applyCurrentSettings()` is the single entry point — call it on app
/// launch, after any settings change, and on permission flips. The
/// notification observer in `init()` covers the permission-flip case.
@MainActor
final class TriggerController {
    static let shared = TriggerController()

    /// Set by `AppDelegate` on launch. Currently only the hot corner watcher
    /// fires this; routes through the same summon path as the hotkey.
    var summon: () -> Void = {}

    private lazy var hotCornerWatcher = HotCornerWatcher { [weak self] in
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
    }
}

import AppKit
import Foundation
import Observation
import ServiceManagement

extension Notification.Name {
    /// Posted when login-item registration state changes (either because we
    /// just toggled it or because we re-checked on app activation and the
    /// user changed it in System Settings).
    static let mosaicLoginItemDidChange = Notification.Name("MosaicLoginItemDidChange")
}

/// Wraps `SMAppService.mainApp` (macOS 13+). The system is the source of
/// truth — we re-read `.status` on every activation so the toggle in
/// Settings reflects what's actually in System Settings ▸ General ▸ Login
/// Items, not whatever we last asked for.
///
/// No entitlement is required for `SMAppService.mainApp` — only that the
/// bundle is signed (ad-hoc is enough for local dev).
@MainActor
@Observable
final class LoginItemController {
    static let shared = LoginItemController()

    /// Raw status from SMAppService — surfaced so the UI can distinguish
    /// `.enabled` from `.requiresApproval` (where the user has to flip a
    /// switch in System Settings before login launching actually happens).
    private(set) var status: SMAppService.Status

    /// Last attempt's error message, if any. Cleared on the next successful
    /// register/unregister.
    private(set) var lastError: String?

    /// Convenience for the UI's Toggle binding.
    var isEnabled: Bool { status == .enabled }

    private init() {
        status = SMAppService.mainApp.status

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let new = SMAppService.mainApp.status
        guard new != status else { return }
        status = new
        NotificationCenter.default.post(name: .mosaicLoginItemDidChange, object: nil)
    }

    /// Try to register/unregister. On error, keep our state in sync with
    /// whatever the system actually thinks (refresh) and surface the message.
    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("Mosaic: SMAppService \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        // Always re-read from the system after an attempt — the call may have
        // succeeded partially or the OS may be in a transitional state.
        status = service.status
        NotificationCenter.default.post(name: .mosaicLoginItemDidChange, object: nil)
    }
}

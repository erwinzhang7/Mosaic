import AppKit
import ApplicationServices
import Observation

extension Notification.Name {
    /// Posted when `AccessibilityPermission.isTrusted` flips, in either
    /// direction. Listeners (`TriggerController`) react by starting or
    /// stopping the input monitors they own.
    static let mosaicAccessibilityPermissionChanged = Notification.Name("MosaicAccessibilityPermissionChanged")
}

/// Centralized TCC-Accessibility helper. Every feature that needs the
/// "Accessibility" permission goes through this — step 8's hot corners and
/// pinch live here, and step 9 (F4 event tap) and step 10 (window browsing)
/// will reuse the same plumbing instead of each calling `AXIsProcessTrusted`
/// independently.
///
/// macOS doesn't deliver a callback when the user grants permission, so we
/// poll on `NSApplication.didBecomeActiveNotification` — that fires when the
/// user comes back from System Settings, which is the realistic flow.
@MainActor
@Observable
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    /// Live trust state. SwiftUI views that read this re-render when it flips.
    private(set) var isTrusted: Bool

    private init() {
        isTrusted = AXIsProcessTrusted()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Re-read the current trust state. If it changed, broadcast so non-view
    /// listeners (like `TriggerController`) can react.
    func refresh() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        NotificationCenter.default.post(name: .mosaicAccessibilityPermissionChanged, object: nil)
    }

    /// Show the system "Mosaic would like to use Accessibility" prompt.
    /// Returns the current trust state *before* the user responds (the prompt
    /// is async — we detect the actual grant via `refresh()` on next
    /// activation). macOS only shows this prompt once per session-ish; after
    /// that the user must go to System Settings directly.
    @discardableResult
    func requestPrompt() -> Bool {
        // The framework constant `kAXTrustedCheckOptionPrompt` is exposed as a
        // mutable global, which trips Swift 6's strict-concurrency check.
        // Its string value ("AXTrustedCheckOptionPrompt") is stable public
        // API, so we use the literal directly to sidestep the diagnostic.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted != isTrusted {
            isTrusted = trusted
            NotificationCenter.default.post(name: .mosaicAccessibilityPermissionChanged, object: nil)
        }
        return trusted
    }

    /// Open System Settings directly to the Privacy & Security ▸ Accessibility
    /// pane. This is the fallback when the system prompt has already been
    /// shown (and so won't appear again) or denied.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

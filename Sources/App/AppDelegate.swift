import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Globally accessible reference to the live AppDelegate instance.
    /// SwiftUI's lifecycle may replace `NSApp.delegate` after our manual
    /// assignment in `MosaicApp.init`, so anything that previously cast
    /// `NSApp.delegate as? AppDelegate` should go through this static
    /// instead. Set in `init`, lives as long as MosaicApp's stored property
    /// holds the strong reference.
    static private(set) weak var shared: AppDelegate?

    private var overlay: OverlayWindow?
    private var setupComplete = false

    override init() {
        super.init()
        Self.shared = self
    }

    /// Run the launch sequence (overlay, hotkey, triggers, observers).
    /// Idempotent — safe to call from both `MosaicApp.init` AND
    /// `applicationDidFinishLaunching`. We call from App.init because
    /// SwiftUI's lifecycle with only MenuBarExtra + Settings scenes on
    /// macOS 26 fails to deliver applicationDidFinishLaunching reliably.
    func setup() {
        guard !setupComplete else { return }
        setupComplete = true

        // LSUIElement=YES already implies .accessory; explicit for clarity.
        NSApp.setActivationPolicy(.accessory)

        // Menu bar item is declared in MosaicApp via MenuBarExtra so it can
        // host a SettingsLink — see MosaicApp.swift.

        installOverlay()
        installHotKey()
        installTriggers()
        observeAppActivation()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setup()
    }

    // MARK: Triggers (hot corner, pinch)

    private func installTriggers() {
        TriggerController.shared.summon = { [weak self] in self?.toggleOverlay() }
        // Idempotent: starts only the watchers whose toggles are on AND for
        // which Accessibility is granted. Re-runs on permission grant/revoke
        // via the controller's own notification observer.
        TriggerController.shared.applyCurrentSettings()
    }

    // MARK: Overlay

    private func installOverlay() {
        overlay = OverlayWindow(
            rootView: GridView(onDismiss: { [weak self] in self?.hideOverlay() })
        )
    }

    func toggleOverlay() {
        if overlay?.isVisible == true {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func showOverlay() {
        // Summon onto whichever screen the cursor is currently on.
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        overlay?.showOn(screen)
    }

    private func hideOverlay() {
        overlay?.dismiss()
    }

    // MARK: Hotkey

    /// Install the persisted summon hotkey on launch. If the saved combo
    /// can't be registered (taken by another app since it was set), fall back
    /// to the default. If the default also fails, leave the hotkey unset —
    /// the user can pick a different one in Settings.
    private func installHotKey() {
        let saved = LayoutStore.shared.state.summonHotKey
        if HotKeyManager.shared.install(
            keyCode: saved.keyCode,
            modifiers: saved.modifiers,
            action: { [weak self] in self?.toggleOverlay() }
        ) { return }

        if saved != .default {
            NSLog("Mosaic: saved summon hotkey unavailable, falling back to ⌃⌥Space")
            let fallback = HotKeyBinding.default
            if HotKeyManager.shared.install(
                keyCode: fallback.keyCode,
                modifiers: fallback.modifiers,
                action: { [weak self] in self?.toggleOverlay() }
            ) { return }
        }

        NSLog("Mosaic: no summon hotkey active; set one in Settings")
    }

    /// Live-rebind the summon hotkey. Returns `nil` on success, or a
    /// user-facing error string on failure (in which case the previously
    /// registered hotkey is still active — see HotKeyManager.install).
    /// Called by the Settings shortcut recorder.
    @discardableResult
    func applyHotKey(_ binding: HotKeyBinding) -> String? {
        let ok = HotKeyManager.shared.install(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers,
            action: { [weak self] in self?.toggleOverlay() }
        )
        guard ok else {
            return "That combo is already in use by another app. Pick a different one."
        }
        LayoutStore.shared.setSummonHotKey(binding)
        return nil
    }

    // MARK: Lifecycle

    /// When the user switches to another app, dismiss the overlay so it doesn't
    /// linger behind the next active window. Also surface launch-failure
    /// toasts here so they don't depend on the overlay still being visible.
    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hideOverlay() }
        }
        NotificationCenter.default.addObserver(
            forName: .mosaicAppLaunchFailed,
            object: nil,
            queue: .main
        ) { notif in
            let name = (notif.userInfo?["name"] as? String) ?? "the app"
            Task { @MainActor in
                ToastWindow.show(message: "Couldn't open \(name) — it may have been moved or deleted.")
            }
        }
    }
}

import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=YES already implies .accessory; explicit for clarity.
        NSApp.setActivationPolicy(.accessory)

        installStatusItem()
        installOverlay()
        installHotKey()
        installTriggers()
        observeAppActivation()
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

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill",
                                   accessibilityDescription: "Mosaic")
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: "Show Mosaic",
            action: #selector(menuShow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Mosaic",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        item.menu = menu
        statusItem = item
    }

    @objc private func menuShow() {
        toggleOverlay()
    }

    @objc private func openSettings() {
        // Bring the agent app to the foreground so its Settings window can
        // become key, then send the standard SwiftUI Settings selector.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: Lifecycle

    /// When the user switches to another app, dismiss the overlay so it doesn't
    /// linger behind the next active window.
    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hideOverlay() }
        }
    }
}

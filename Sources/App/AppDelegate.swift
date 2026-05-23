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
        observeAppActivation()
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

    private func installHotKey() {
        // Default summon: ⌃⌥Space. Cmd-Space is Spotlight; F4 is wired in step 9.
        HotKeyManager.shared.install(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            self?.toggleOverlay()
        }
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

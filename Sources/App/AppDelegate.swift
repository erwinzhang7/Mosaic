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

    /// Timestamps used by the didBecomeActive observer to tell apart "user
    /// clicked our Dock icon / opened the .app" (treat as summon) from
    /// "we just activated ourselves" or "this is the cold-launch activation".
    private let startupTime: TimeInterval = CACurrentMediaTime()
    private var lastSelfActivation: TimeInterval = 0

    /// Most recent time a Dock/Finder summon was handled — used to dedup
    /// across the didBecomeActive path and the AppleEvent path which both
    /// fire on the same click. Either may arrive first; the other gets
    /// skipped if within 0.5s.
    private var lastExternalActivationHandled: TimeInterval = 0

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

        // Re-install the kAEReopenApplication handler AFTER SwiftUI's own
        // App init has finished. Registering in this same setup() (which
        // runs from MosaicApp.init synchronously) gets overridden by
        // SwiftUI's later registration. A 1s deferred install puts us last
        // in line so our handler wins. The AppleEvent route catches Dock
        // clicks while the app is ALREADY active, which didBecomeActive
        // can't see (no inactive→active transition).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.registerReopenHandler()
        }
    }

    private func registerReopenHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleReopenEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication)
        )
    }

    @objc private func handleReopenEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let now = CACurrentMediaTime()
        // Dedup with the didBecomeActive path — on cold clicks both routes
        // fire for the same event.
        if now - lastExternalActivationHandled < 0.5 { return }
        lastExternalActivationHandled = now
        toggleOverlay()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setup()
    }

    /// Canonical reopen hook. SwiftUI delegates through to this method, so —
    /// unlike the raw `kAEReopenApplication` AppleEvent handler, which SwiftUI
    /// re-registers over ours on every scene re-evaluation — this stays wired
    /// for the life of the process. Covers Dock-shortcut clicks and Finder
    /// double-clicks on the .app when Mosaic is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let now = CACurrentMediaTime()
        if now - lastExternalActivationHandled < 0.5 { return false }
        lastExternalActivationHandled = now
        toggleOverlay()
        return false
    }

    // MARK: Triggers (hot corner)

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
        // Record before showOn so the didBecomeActive triggered by our own
        // NSApp.activate (inside showOn) is recognised as self-initiated and
        // not re-routed back through toggleOverlay.
        lastSelfActivation = CACurrentMediaTime()
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

        // External-activation observer: when something else makes us active
        // (Dock click, Finder double-click on the .app, `open` from a
        // terminal), summon the overlay. SwiftUI's runtime overrides our
        // AppleEvent handlers for kAEReopenApplication on .accessory apps,
        // so reopen-events don't reach us — but activation always does.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppActivation() }
        }
    }

    private func handleAppActivation() {
        let now = CACurrentMediaTime()
        // Startup grace — cold launch (especially login-launched) often
        // activates briefly; don't summon on first boot.
        if now - startupTime < 2.0 { return }
        // Self-initiated — we just called NSApp.activate ourselves
        // (showOverlay, openSettings); ignore the resulting activation.
        if now - lastSelfActivation < 0.5 { return }

        // Defer a tick so any window opening alongside this activation
        // (Settings) can become key. Use keyWindow rather than "any visible
        // window" — NSApp.windows includes SwiftUI's MenuBarExtra and the
        // internal status-bar window, which would always make hasOtherWindow
        // true and prevent the summon. keyWindow is the user-facing focus
        // target: Settings is key when open, status-bar chrome never is.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if let key = NSApp.keyWindow, !(key is OverlayWindow) {
                return // Settings or another foreground window — not a Dock click
            }
            // Dedup with the AppleEvent path which may have fired for the
            // same physical click.
            let now2 = CACurrentMediaTime()
            if now2 - self.lastExternalActivationHandled < 0.5 { return }
            self.lastExternalActivationHandled = now2
            self.toggleOverlay()
        }
    }
}

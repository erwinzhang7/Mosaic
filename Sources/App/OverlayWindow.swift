import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the overlay window has actually become key — i.e., AppKit
    /// has wired up keyboard input. SwiftUI uses this as the cue to (re-)assert
    /// focus on the search field, instead of a timer that races the hosting
    /// view's mount. Fires on every summon, including the first.
    static let mosaicOverlayDidBecomeKey = Notification.Name("MosaicOverlayDidBecomeKey")
}

/// Borderless, full-screen NSWindow that hosts the grid.
@MainActor
final class OverlayWindow: NSWindow {
    /// The app that was frontmost when we summoned. Reactivated on dismiss so
    /// the user's keyboard focus isn't left stranded on our hidden window.
    private var returnToApp: NSRunningApplication?

    init(rootView: some View) {
        let initialScreen = NSScreen.main ?? NSScreen.screens.first!
        let frame = initialScreen.frame

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        let visualEffect = NSVisualEffectView(frame: frame)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]

        visualEffect.addSubview(hosting)
        contentView = visualEffect
    }

    /// Borderless windows are not key by default. We need keyboard input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// AppKit calls this once the window has actually taken key status, which
    /// is the earliest point keyboard input is wired up. Notifying here lets
    /// SwiftUI claim focus on a real signal instead of a guessed delay.
    override func becomeKey() {
        super.becomeKey()
        NotificationCenter.default.post(name: .mosaicOverlayDidBecomeKey, object: self)
    }

    func showOn(_ screen: NSScreen) {
        // Remember who to hand focus back to — unless we're already frontmost
        // (settings window open, rapid re-summon, etc.), in which case keep
        // the prior value rather than overwriting it with self.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            returnToApp = frontmost
        }

        // Set the frame BEFORE making key so the responder chain attaches on
        // the right screen — important for multi-monitor focus.
        setFrame(screen.frame, display: true)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        guard isVisible || returnToApp != nil else { return }
        orderOut(nil)
        // Clear before activating: activating the other app makes us resign
        // active, which triggers AppDelegate's observer to call dismiss()
        // again. With returnToApp cleared, that re-entry is a no-op.
        let returning = returnToApp
        returnToApp = nil
        returning?.activate()
    }
}

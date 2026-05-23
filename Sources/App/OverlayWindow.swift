import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by `AppDelegate` when the overlay window becomes visible.
    /// `GridView` listens so it can reset state (clear search, restore focus).
    static let mosaicOverlayDidShow = Notification.Name("MosaicOverlayDidShow")
}

/// Borderless, full-screen NSWindow that hosts the grid.
@MainActor
final class OverlayWindow: NSWindow {
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

    func showOn(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .mosaicOverlayDidShow, object: nil)
    }

    func dismiss() {
        orderOut(nil)
    }
}

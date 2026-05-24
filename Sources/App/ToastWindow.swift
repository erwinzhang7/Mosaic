import AppKit
import SwiftUI

/// Small floating notification window for transient, non-modal messages —
/// used for "couldn't open <app>" errors that fire after the overlay has
/// already dismissed. Auto-dismisses after a few seconds; uses a strong
/// self-reference to stay alive until then.
@MainActor
final class ToastWindow: NSWindow {
    private static nonisolated(unsafe) var active: [ToastWindow] = []

    init(message: String, icon: String) {
        let size = NSSize(width: 380, height: 64)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: ToastContent(message: message, icon: icon))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                   y: frame.maxY - size.height - 16))
        }
    }

    /// Show a toast for a few seconds. Caller doesn't need to hold a
    /// reference — we keep one in `active` until the dismiss fires.
    @MainActor
    static func show(message: String, icon: String = "exclamationmark.triangle.fill",
                     dismissAfter seconds: TimeInterval = 3.5) {
        let win = ToastWindow(message: message, icon: icon)
        active.append(win)
        win.alphaValue = 0
        win.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            win.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.22
                    win.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        win.orderOut(nil)
                        if let idx = ToastWindow.active.firstIndex(where: { $0 === win }) {
                            ToastWindow.active.remove(at: idx)
                        }
                    }
                })
            }
        }
    }
}

private struct ToastContent: View {
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.title3)
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        )
        .padding(2)
    }
}

import AppKit
import QuartzCore

/// Watches global trackpad magnify (pinch) events and fires when accumulated
/// magnification crosses a threshold in the configured direction. One
/// gesture = one summon: after firing, we reset and don't fire again until
/// the gesture ends and a new one begins.
///
/// Uses `NSEvent.addGlobalMonitorForEvents(matching: .magnify)`, which needs
/// Accessibility permission. `TriggerController` is responsible for only
/// calling `start()` when permission is granted.
@MainActor
final class PinchWatcher {
    var direction: PinchDirection = .open
    /// Accumulated magnification value that must be exceeded to fire.
    /// 0.3 ≈ a clearly intentional pinch; smaller values get too jumpy.
    var threshold: CGFloat = 0.3

    private let onTrigger: () -> Void
    private let monitorHolder = GlobalEventMonitorHolder()
    private var accumulated: CGFloat = 0
    private var lastEventTime: TimeInterval = 0
    /// Treat the gesture as ended if no magnify event arrives for this long.
    private let gestureGap: TimeInterval = 0.25
    /// Brief cooldown after firing so a long gesture doesn't re-fire.
    private let postFireCooldown: TimeInterval = 0.6
    private var firedAt: TimeInterval = 0

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func start() {
        monitorHolder.start { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        monitorHolder.stop()
        accumulated = 0
        lastEventTime = 0
        firedAt = 0
    }

    private func handle(_ event: NSEvent) {
        let now = CACurrentMediaTime()

        // Cooldown after a successful fire — ignore the tail of the same gesture.
        if firedAt > 0 && now - firedAt < postFireCooldown {
            return
        }

        // New gesture if we've been idle long enough.
        if now - lastEventTime > gestureGap {
            accumulated = 0
        }
        lastEventTime = now

        accumulated += event.magnification

        let crossed: Bool
        switch direction {
        case .open:   crossed = accumulated >= threshold
        case .closed: crossed = accumulated <= -threshold
        }

        if crossed {
            firedAt = now
            accumulated = 0
            onTrigger()
        }
    }
}

/// Holds the `Any?` token returned by `NSEvent.addGlobalMonitorForEvents` so
/// the watcher can store it across rebinds without tangling with Sendable
/// rules. Same pattern as `MonitorHolder` in `HotKeyRecorder`.
@MainActor
final class GlobalEventMonitorHolder {
    private var token: Any?

    func start(handler: @escaping @MainActor (NSEvent) -> Void) {
        stop()
        token = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { event in
            MainActor.assumeIsolated { handler(event) }
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

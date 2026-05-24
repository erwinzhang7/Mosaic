import AppKit
import QuartzCore

/// Polls the cursor at 20 Hz and fires when it parks in the configured corner
/// for at least `dwellSeconds`. Polling rather than a global mouse-moved
/// event monitor: the cursor location is unprivileged via
/// `NSEvent.mouseLocation`, and polling is plenty for a feature with a 100+ms
/// dwell threshold. (We still gate this behind Accessibility at the
/// `TriggerController` level for UX consistency with the pinch monitor and
/// the future F4 event tap.)
@MainActor
final class HotCornerWatcher: NSObject {
    var corner: HotCorner = .topLeft
    var dwellSeconds: TimeInterval = 0.2

    private let onTrigger: () -> Void
    private var timer: Timer?
    private var cornerEnteredAt: TimeInterval?
    private var firedThisVisit = false

    /// Tolerance in points within which the cursor counts as "in the corner".
    /// Has to be at least 1pt for the cursor's pixel to actually land on a
    /// corner edge; small enough that a brisk drag through doesn't trigger.
    private let cornerTolerance: CGFloat = 3

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        super.init()
    }

    func start() {
        stop()
        // Use the target/selector form so the closure-based Sendable rules
        // don't get in the way of capturing a `@MainActor`-isolated `self`.
        let t = Timer(timeInterval: 0.05, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cornerEnteredAt = nil
        firedThisVisit = false
    }

    @objc private func tick() {
        let location = NSEvent.mouseLocation
        let inCorner = pointIsInTargetCorner(location)

        if inCorner {
            if cornerEnteredAt == nil {
                cornerEnteredAt = CACurrentMediaTime()
                firedThisVisit = false
            } else if !firedThisVisit, let entered = cornerEnteredAt,
                      CACurrentMediaTime() - entered >= dwellSeconds {
                firedThisVisit = true
                onTrigger()
            }
        } else {
            cornerEnteredAt = nil
            firedThisVisit = false
        }
    }

    /// AppKit screen coordinates: origin bottom-left of the main screen, Y
    /// increases upward.
    private func pointIsInTargetCorner(_ p: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) else {
            return false
        }
        let frame = screen.frame
        let tol = cornerTolerance
        switch corner {
        case .topLeft:
            return p.x <= frame.minX + tol && p.y >= frame.maxY - tol
        case .topRight:
            return p.x >= frame.maxX - tol && p.y >= frame.maxY - tol
        case .bottomLeft:
            return p.x <= frame.minX + tol && p.y <= frame.minY + tol
        case .bottomRight:
            return p.x >= frame.maxX - tol && p.y <= frame.minY + tol
        }
    }
}

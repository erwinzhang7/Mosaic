import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Observation

/// Opt-in summon trigger that intercepts the F4 key (kVK_F4 = 118) via a
/// `CGEventTap`.
///
/// F4 is the Launchpad/Spotlight key on most Apple keyboards. By default
/// macOS swallows it as a media-key event and fires the system action before
/// any tap can see it — the user has to either enable "Use F1, F2, etc. keys
/// as standard function keys" in System Settings ▸ Keyboard, OR press Fn+F4,
/// for the actual F4 keycode (118) to reach this tap.
///
/// When the tap *does* see it we consume the event (return nil from the
/// callback) so macOS doesn't also fire Launchpad. When the tap *can't* see
/// it, that's an OS-level limitation — we can't intercept media-key events
/// without escalating to private API.
///
/// **Quarantined**: this is the only place in Mosaic that uses CGEventTap.
/// Permission checking is handled by the shared `AccessibilityPermission`
/// helper; `TriggerController` decides when to call `start()` / `stop()`.
/// Pulling this file out should not break anything else.
@MainActor
@Observable
final class F4EventTap {
    /// True if the tap is installed and running. Read by Settings to show a
    /// warning when the toggle is ON but installation failed.
    private(set) var isInstalled: Bool = false

    /// Human-readable description of the most recent failure, or nil.
    private(set) var lastFailure: String?

    /// Invoked on the main actor when F4 is captured.
    /// `TriggerController` wires this to the overlay toggle.
    @ObservationIgnored var onTrigger: () -> Void = {}

    /// CFMachPort + run-loop source. `nonisolated(unsafe)` because the C
    /// callback (which is not main-actor-isolated even though it runs on the
    /// main run loop) needs to access `tap` to re-enable on system disable.
    @ObservationIgnored private nonisolated(unsafe) var tap: CFMachPort?
    @ObservationIgnored private nonisolated(unsafe) var source: CFRunLoopSource?

    /// Carbon kVK_F4 = 118. The value CGEvent reports for the F4 key when it
    /// actually reaches a tap (i.e. as standard function key, not media key).
    private static let f4KeyCode: Int64 = Int64(kVK_F4)

    @discardableResult
    func start() -> Bool {
        if isInstalled { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // `.defaultTap` = active (can consume), as opposed to listen-only.
        // `.headInsertEventTap` = see events before other taps further down
        // the chain. `.cgSessionEventTap` = events for the login session.
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.tapCallback,
            userInfo: selfPtr
        ) else {
            lastFailure = "macOS refused to install the event tap. Re-grant Accessibility and toggle this off and on. (Granting after the app launches sometimes doesn't take effect until a relaunch.)"
            isInstalled = false
            return false
        }

        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        source = newSource
        isInstalled = true
        lastFailure = nil
        return true
    }

    func stop() {
        teardown()
        isInstalled = false
    }

    /// Teardown shared by `stop()` and `deinit`. nonisolated so deinit can
    /// call it without an isolation hop. The stored Mach port + source live
    /// in `nonisolated(unsafe)` storage so this is safe.
    private nonisolated func teardown() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
        }
        if let s = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes)
        }
        tap = nil
        source = nil
    }

    deinit {
        // Best-effort cleanup in case `stop()` was never called. Avoids
        // leaving a zombie tap registered on the run loop.
        teardown()
    }

    /// C callback. Runs on the main run loop because that's where we added
    /// the source. Storage we touch from here is `nonisolated(unsafe)`;
    /// `onTrigger` is dispatched to a `@MainActor` Task so its body executes
    /// with main-actor isolation.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<F4EventTap>.fromOpaque(userInfo).takeUnretainedValue()

        // The system disables the tap if our callback takes too long, or if
        // a burst of user input overwhelms it. The callback fires once with
        // one of these synthetic types — re-enable in place and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = me.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == F4EventTap.f4KeyCode {
                me.fireOnMain()
                // Consume so macOS doesn't also fire Launchpad / whatever
                // the user has bound. Intentional — that's the whole point.
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private nonisolated func fireOnMain() {
        Task { @MainActor [weak self] in
            self?.onTrigger()
        }
    }
}

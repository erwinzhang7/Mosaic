import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Observation

/// Opt-in summon trigger that intercepts the Search / F4 key via a
/// `CGEventTap` at the HID level.
///
/// On a modern Apple keyboard (the F4 key is now engraved 🔍), pressing it
/// emits an `NSSystemDefined` event carrying `NX_KEYTYPE_SPOTLIGHT` rather
/// than a normal keyDown for keycode 118. macOS routes that to Spotlight
/// at a layer above session-level event taps. To catch it before Spotlight
/// does, we tap at `cghidEventTap` and listen for both `keyDown` (legacy
/// F4 hardware) and `NSSystemDefined` (modern Search key + the older
/// Launchpad key).
///
/// When the toggle is on, pressing the Search key triggers Mosaic AND
/// Spotlight stops opening from that key for as long as Mosaic runs.
/// That's the explicit, opted-in trade. Disable the toggle (Settings ▸
/// Triggers) to restore normal Spotlight behavior.
///
/// **Tested on:** 2026 MacBook Pro M5 Max, macOS 26.4. Not validated on
/// other keyboards or macOS versions — third-party keyboards may emit
/// different event codes, and Apple could change the routing in a future
/// macOS release without warning.
///
/// **Quarantined**: this is the only place in Mosaic that uses CGEventTap.
/// Permission checking is handled by the shared `AccessibilityPermission`
/// helper; `TriggerController` decides when to call `start()` / `stop()`.
@MainActor
@Observable
final class F4EventTap {
    /// True if the tap is installed and running. Read by Settings to show a
    /// warning when the toggle is ON but installation failed.
    private(set) var isInstalled: Bool = false

    /// Human-readable description of the most recent failure, or nil.
    private(set) var lastFailure: String?

    /// Invoked on the main actor when the Search/F4 key is captured.
    /// `TriggerController` wires this to the overlay toggle.
    @ObservationIgnored var onTrigger: () -> Void = {}

    /// CFMachPort + run-loop source. `nonisolated(unsafe)` because the C
    /// callback (which is not main-actor-isolated even though it runs on the
    /// main run loop) needs to access `tap` to re-enable on system disable.
    @ObservationIgnored private nonisolated(unsafe) var tap: CFMachPort?
    @ObservationIgnored private nonisolated(unsafe) var source: CFRunLoopSource?

    /// Carbon kVK_F4 = 118. Reported as a normal keyDown by legacy hardware
    /// when "Use F1, F2, etc. as standard function keys" is on, or via Fn+F4.
    private static let f4KeyCode: Int64 = Int64(kVK_F4)

    /// IOKit NX_KEYTYPE_* constants for the special media keys we care about.
    /// Hardcoded rather than imported via `IOKit.hidsystem` so the compile
    /// stays clean of cross-module Sendable noise. Values are stable.
    private static let nxKeyTypeSpotlight: Int = 90   // 🔍 on modern keyboards
    private static let nxKeyTypeLaunchpad: Int = 131  // older "show all apps" key

    /// NSEvent.SubType.aux (kIOHIDEventTypeKeyboard) — the subtype value
    /// systemDefined events use to carry NX_KEYTYPE_* codes.
    private static let nxSubtypeAuxControlButtons: Int = 8

    @discardableResult
    func start() -> Bool {
        if isInstalled { return true }

        // `.cghidEventTap` (HID level) sees raw events before macOS routes
        // them to system actions like Spotlight. Required for the Search key.
        // `.defaultTap` = active (can consume).
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << UInt64(NSEvent.EventType.systemDefined.rawValue))
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
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

        // Legacy F4 hardware path: keycode 118 as a normal keyDown.
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == F4EventTap.f4KeyCode {
                me.fireOnMain()
                return nil
            }
        }

        // Modern Search-key path: NSSystemDefined event, subtype 8, with the
        // NX_KEYTYPE_* code packed into the upper 16 bits of data1. We
        // act on key-DOWN only (state == 0x0A) to avoid firing twice per
        // press; the matching up event is allowed to pass through harmlessly
        // since nobody else cares about it once we've consumed the down.
        if type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue) {
            if let nsEvent = NSEvent(cgEvent: event),
               nsEvent.subtype.rawValue == Int16(F4EventTap.nxSubtypeAuxControlButtons) {
                let data1 = nsEvent.data1
                let keyType = (data1 & 0xFFFF0000) >> 16
                let keyState = (data1 & 0x0000FF00) >> 8
                let isDown = (keyState == 0x0A)
                if isDown && (keyType == F4EventTap.nxKeyTypeSpotlight
                              || keyType == F4EventTap.nxKeyTypeLaunchpad) {
                    me.fireOnMain()
                    return nil // consume — Spotlight / Launchpad won't fire
                }
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

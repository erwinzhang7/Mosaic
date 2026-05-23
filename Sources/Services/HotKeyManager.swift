import AppKit
import Carbon.HIToolbox

/// Wraps Carbon's `RegisterEventHotKey` so the app can react to a global
/// hotkey without needing Accessibility permission.
///
/// Carbon's event-handler API takes a C function pointer that can't capture
/// context, so we route through this singleton. Storage is
/// `nonisolated(unsafe)` because the C callback reads `handler` from an
/// unknown isolation context; we re-dispatch to the main queue before
/// running it so observers see main-actor isolation.
final class HotKeyManager: @unchecked Sendable {
    static let shared = HotKeyManager()

    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handler: (() -> Void)?
    private nonisolated(unsafe) var handlerInstalled = false
    private nonisolated(unsafe) var nextRegistrationID: UInt32 = 0

    private init() {}

    /// Register the given combo as the global summon hotkey.
    ///
    /// Try-then-swap: registers the new combo first, and only unregisters the
    /// previous one once the new one is live. On failure, the previous
    /// registration is left untouched — the caller can keep the user's
    /// existing hotkey working instead of being silently demoted to nothing.
    ///
    /// Returns `true` on success, `false` if Carbon refused the combo (the
    /// usual cause is that another app already owns it).
    @discardableResult
    func install(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        ensureHandlerInstalled()

        // Use a fresh registration ID per attempt. During the brief window
        // both the old and new registrations are live; the handler is a
        // toggle so it doesn't matter which one fires.
        nextRegistrationID &+= 1
        let id = EventHotKeyID(signature: OSType(0x4D4F5341), id: nextRegistrationID) // 'MOSA'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef else {
            NSLog("Mosaic: RegisterEventHotKey failed with status \(status)")
            return false
        }

        if let oldRef = hotKeyRef {
            UnregisterEventHotKey(oldRef)
        }
        hotKeyRef = newRef
        handler = action
        return true
    }

    func uninstall() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        handler = nil
    }

    /// Install the Carbon event handler if it hasn't been installed yet. We
    /// only ever want one of these for the app's lifetime — InstallEventHandler
    /// doesn't return a removable handle in our usage so we don't try to
    /// remove it; we just toggle the registered hotkey instead.
    private func ensureHandlerInstalled() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                if let handler = HotKeyManager.shared.handler {
                    DispatchQueue.main.async { handler() }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        handlerInstalled = true
    }
}

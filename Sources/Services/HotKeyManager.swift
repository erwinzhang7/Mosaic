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

    private init() {}

    /// Register (or replace) the global hotkey. Modifiers are Carbon constants
    /// — combinations of `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    func install(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        uninstall()
        handler = action

        if !handlerInstalled {
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

        let id = EventHotKeyID(signature: OSType(0x4D4F5341), id: 1) // 'MOSA'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("Mosaic: RegisterEventHotKey failed with status \(status)")
        }
    }

    func uninstall() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

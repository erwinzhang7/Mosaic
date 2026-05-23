import AppKit
import Carbon.HIToolbox
import Foundation

/// User-configurable summon hotkey, stored as raw Carbon `keyCode` + modifier
/// bits. `keyDisplay` is the captured display name for the key (e.g. "Space",
/// "A", "F4") — kept here so we don't have to round-trip through the keyboard
/// layout every render. May go stale if the user switches keyboard layouts;
/// re-recording fixes it.
struct HotKeyBinding: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyDisplay: String

    /// Default binding for fresh installs: ⌃⌥Space. Carbon hotkeys do not
    /// need Accessibility, and this combo doesn't collide with Spotlight
    /// (⌘Space) or the OS Launchpad key (F4).
    static let `default` = HotKeyBinding(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey),
        keyDisplay: "Space"
    )

    /// Pretty form like "⌃⌥Space" for display in the UI.
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyDisplay
        return s
    }

    // MARK: Capture & validation

    enum ValidationFailure {
        case noModifier
        case reservedBySystem(String)
    }

    /// Validate a candidate binding. Returns `nil` if acceptable, or a
    /// failure case describing why not.
    static func validate(_ b: HotKeyBinding) -> ValidationFailure? {
        let realModifiers = b.modifiers & UInt32(cmdKey | controlKey | optionKey)
        if realModifiers == 0 {
            return .noModifier
        }
        // Block obvious system combos: ⌘Space (Spotlight), ⌘Tab (app switcher).
        // The brief is explicit about not trying to be exhaustive — only catch
        // the trivial footguns.
        let cmdOnly = (b.modifiers & ~UInt32(shiftKey)) == UInt32(cmdKey)
        if cmdOnly && b.keyCode == UInt32(kVK_Space) {
            return .reservedBySystem("⌘Space is Spotlight.")
        }
        if cmdOnly && b.keyCode == UInt32(kVK_Tab) {
            return .reservedBySystem("⌘Tab is the app switcher.")
        }
        return nil
    }

    /// Build a binding from an NSEvent (used by the SwiftUI recorder).
    static func fromKeyDownEvent(_ event: NSEvent) -> HotKeyBinding {
        let keyCode = UInt32(event.keyCode)
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option)  { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift)   { mods |= UInt32(shiftKey) }
        return HotKeyBinding(
            keyCode: keyCode,
            modifiers: mods,
            keyDisplay: keyDisplay(forKeyCode: keyCode, characters: event.charactersIgnoringModifiers)
        )
    }

    /// Resolve a display name for a Carbon keyCode. Handles common special
    /// keys explicitly; falls back to the uppercased character the user
    /// produced for everything else (so "a" → "A", "1" → "1", "[" → "[").
    private static func keyDisplay(forKeyCode keyCode: UInt32, characters: String?) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        if let chars = characters, !chars.isEmpty {
            let scalar = chars.unicodeScalars.first.map { UInt32($0.value) } ?? 0
            // Filter out the function-key private-use range — those should be
            // covered by the lookup table; if we got here it's likely the user
            // pressed an unknown special key. Show its scalar so they can see
            // something rather than a control char.
            if scalar >= 0xF700 && scalar <= 0xF8FF {
                return "Key \(keyCode)"
            }
            return chars.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space):       "Space",
        UInt32(kVK_Return):      "Return",
        UInt32(kVK_Tab):         "Tab",
        UInt32(kVK_Delete):      "Delete",
        UInt32(kVK_ForwardDelete): "Fwd Delete",
        UInt32(kVK_Escape):      "Esc",
        UInt32(kVK_LeftArrow):   "←",
        UInt32(kVK_RightArrow):  "→",
        UInt32(kVK_UpArrow):     "↑",
        UInt32(kVK_DownArrow):   "↓",
        UInt32(kVK_Home):        "Home",
        UInt32(kVK_End):         "End",
        UInt32(kVK_PageUp):      "Page Up",
        UInt32(kVK_PageDown):    "Page Down",
        UInt32(kVK_F1):  "F1",  UInt32(kVK_F2):  "F2",  UInt32(kVK_F3):  "F3",
        UInt32(kVK_F4):  "F4",  UInt32(kVK_F5):  "F5",  UInt32(kVK_F6):  "F6",
        UInt32(kVK_F7):  "F7",  UInt32(kVK_F8):  "F8",  UInt32(kVK_F9):  "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]
}

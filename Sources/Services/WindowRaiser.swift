import AppKit
import ApplicationServices
import Foundation

/// Raises a specific window via the Accessibility API, with a graceful
/// fallback when AX is unavailable or the specific window can't be resolved.
///
/// The AX path needs Accessibility permission (Settings ▸ Privacy &
/// Security ▸ Accessibility). The fallback path uses `NSRunningApplication
/// .activate`, which only requires being able to message the app — no
/// special permission — but it raises whatever the app considers its
/// frontmost window, not necessarily the one the user picked.
@MainActor
enum WindowRaiser {
    enum Result {
        /// AX raised the specific window the user selected.
        case raisedSpecificWindow
        /// AX couldn't resolve the window (no permission, empty title, or no
        /// match). We activated the owning app instead — focuses *some*
        /// window of that app, just not necessarily the chosen one.
        case activatedAppFallback
        /// The owning process is gone.
        case ownerNotRunning
    }

    @discardableResult
    static func raise(_ item: WindowItem) -> Result {
        guard let app = NSRunningApplication(processIdentifier: item.ownerPID) else {
            return .ownerNotRunning
        }

        let raised = raiseSpecificWindow(pid: item.ownerPID, title: item.title)

        // Always activate the owning app: AXRaise alone reorders the window
        // within its app's window stack but doesn't bring the *app* forward.
        app.activate()

        return raised ? .raisedSpecificWindow : .activatedAppFallback
    }

    /// Try to find the window with the matching title under the given PID and
    /// `AXRaise` it. Returns `true` if we found and raised a specific window;
    /// `false` if we should fall back to plain app activation.
    private static func raiseSpecificWindow(pid: pid_t, title: String) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard status == .success, let windows = windowsValue as? [AXUIElement] else {
            // Most common cause: no Accessibility permission. AX returns
            // kAXErrorAPIDisabled and we can't even enumerate.
            return false
        }

        // Title-based match. Skipped entirely if our enumeration title was
        // empty (very common without Screen Recording / Accessibility): we'd
        // match the wrong window. Fall back to whole-app activation instead.
        var target: AXUIElement?
        if !title.isEmpty {
            for axWindow in windows {
                var titleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue) == .success,
                   let axTitle = titleValue as? String,
                   axTitle == title {
                    target = axWindow
                    break
                }
            }
        }

        // Single-window apps: if matching failed but there's only one window,
        // it's unambiguous — take it.
        if target == nil, windows.count == 1 {
            target = windows[0]
        }

        guard let target else { return false }

        let raiseStatus = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        return raiseStatus == .success
    }
}

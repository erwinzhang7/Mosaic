import AppKit
import CoreGraphics
import Foundation

/// Enumerates on-screen windows across running apps using
/// `CGWindowListCopyWindowInfo`. Cheap — call on mode switch / refresh, never
/// in a tight poll loop.
///
/// Permission model: enumeration itself does not require Accessibility, but
/// window *titles* are empty for most other apps unless Mosaic has either
/// Accessibility or Screen Recording permission. We don't request Screen
/// Recording (too invasive for this step) — instead we surface the missing-
/// titles state in the UI and rely on the user granting Accessibility for
/// fuller info plus the specific-window raise behavior.
@MainActor
enum WindowDiscovery {
    static func discover() -> [WindowItem] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier

        var items: [WindowItem] = []
        var iconCache: [pid_t: NSImage] = [:]

        for info in infoList {
            guard
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let ownerName = info[kCGWindowOwnerName as String] as? String
            else { continue }

            // Skip Mosaic's own windows (the overlay, and Settings if open).
            if pid == myPID { continue }

            // Layer 0 = normal app windows. Anything else is menu-bar item,
            // system UI, status icon, Dock, etc. — not "windows" in the
            // user's mental model.
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }

            // Bounds: skip tiny things that are usually invisible helpers.
            let boundsDict = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            if bounds.isEmpty { continue }
            if bounds.width < 40 || bounds.height < 40 { continue }

            let title = info[kCGWindowName as String] as? String ?? ""

            let icon: NSImage
            if let cached = iconCache[pid] {
                icon = cached
            } else if let app = NSRunningApplication(processIdentifier: pid), let appIcon = app.icon {
                icon = appIcon
                iconCache[pid] = appIcon
            } else {
                icon = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage()
            }

            items.append(WindowItem(
                id: windowID,
                ownerPID: pid,
                ownerName: ownerName,
                title: title,
                icon: icon,
                bounds: bounds
            ))
        }

        // Sort: by app name, then by title within app.
        items.sort {
            if $0.ownerName != $1.ownerName {
                return $0.ownerName.localizedStandardCompare($1.ownerName) == .orderedAscending
            }
            return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        }

        return items
    }
}

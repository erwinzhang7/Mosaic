import AppKit
import CoreGraphics
import Foundation

/// One on-screen window owned by some other app. Surfaced in the Windows
/// browsing mode. Non-Sendable for the same reason as `AppItem` — carries an
/// `NSImage` icon — so it's used only on the main actor.
struct WindowItem: Identifiable, Hashable {
    /// Quartz window number — globally unique while the window exists.
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    /// The window's title. Often empty for other apps when Mosaic doesn't have
    /// Accessibility or Screen Recording permission — that's the OS hiding it,
    /// not a discovery bug.
    let title: String
    let icon: NSImage
    let bounds: CGRect

    var displayTitle: String {
        title.isEmpty ? "Untitled window" : title
    }

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
            && lhs.ownerPID == rhs.ownerPID
            && lhs.title == rhs.title
            && lhs.ownerName == rhs.ownerName
            && lhs.bounds == rhs.bounds
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

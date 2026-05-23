import AppKit
import Foundation

/// One discovered app. Non-Sendable because `NSImage` isn't, which is fine —
/// AppItem is only ever read or written on the main actor.
struct AppItem: Identifiable, Hashable {
    let bundleID: String
    var displayName: String
    let icon: NSImage
    let sourcePath: URL

    var id: String { bundleID }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.bundleID == rhs.bundleID
            && lhs.displayName == rhs.displayName
            && lhs.sourcePath == rhs.sourcePath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }
}

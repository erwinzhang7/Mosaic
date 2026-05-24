import Foundation

/// The complete set of items that would be moved to the Trash when
/// uninstalling an app. Computed by `Uninstaller.computeSet(for:)`; never
/// constructed directly elsewhere.
///
/// The `.app` bundle itself is mandatory (not user-deselectable). Each
/// support item is checked-by-default but can be unchecked individually in
/// the preview before confirming.
struct UninstallSet: Identifiable {
    let id = UUID()
    let bundleID: String
    let bundleURL: URL
    let bundleSize: Int64
    var supportItems: [SupportItem]

    struct SupportItem: Identifiable, Hashable {
        /// Human-readable category for grouping in the preview
        /// ("Application Support", "Caches", "Preferences", etc.).
        let category: String
        let url: URL
        let size: Int64
        var isSelected: Bool

        var id: String { url.path }
    }

    /// Items the user has currently chosen to trash: bundle + selected
    /// support items.
    var selectedURLs: [URL] {
        [bundleURL] + supportItems.filter(\.isSelected).map(\.url)
    }

    var selectedCount: Int {
        1 + supportItems.lazy.filter(\.isSelected).count
    }

    var selectedSize: Int64 {
        bundleSize + supportItems.lazy.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    var appName: String {
        bundleURL.deletingPathExtension().lastPathComponent
    }
}

/// Outcome of a trash operation. Partial success is normal — permission or
/// transient I/O can fail individual items.
struct UninstallResult {
    /// URLs that were successfully trashed (or pretend-trashed, in simulation
    /// mode).
    let trashed: [URL]
    /// URLs that failed, with the underlying error.
    let failed: [(url: URL, error: String)]
    /// True if no items were actually moved — simulation mode just logged.
    let simulated: Bool

    var hasFailures: Bool { !failed.isEmpty }
}

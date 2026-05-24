import AppKit
import Foundation

/// **The only destructive code in Mosaic.** Every path that moves a file
/// lives in this file, behind:
///
/// 1. A master toggle (`Preferences.uninstallEnabled`) that hides the menu
///    item entirely when off.
/// 2. A mandatory three-stage modal: preview → explicit confirm → result.
///    `Uninstaller.trash(_:simulate:)` is never called without the user
///    clicking through both gates.
/// 3. A simulation mode (`Preferences.uninstallSimulate`) that turns
///    `trash(_:simulate:)` into a logging no-op, so the whole flow can be
///    exercised end-to-end against real bundles without anything actually
///    moving.
///
/// Deletion path: `FileManager.trashItem` only — items are recoverable from
/// the user's Trash. There is no permanent-delete code path anywhere in the
/// project. Don't add one.
@MainActor
enum Uninstaller {
    enum ComputeError: LocalizedError {
        case systemApp
        case outsideAllowedRoots
        case bundleIDMissing
        case bundleUnreadable

        var errorDescription: String? {
            switch self {
            case .systemApp:
                return "Mosaic refuses to uninstall Apple-supplied or system apps."
            case .outsideAllowedRoots:
                return "Mosaic only uninstalls apps in /Applications or ~/Applications."
            case .bundleIDMissing:
                return "The app has no bundle identifier — can't match its support files safely."
            case .bundleUnreadable:
                return "Couldn't read the app bundle to measure its size."
            }
        }
    }

    // MARK: Compute

    /// Inspect an `AppItem` and build the full uninstall set: the bundle plus
    /// any support files we can confidently match by bundle ID. Throws on the
    /// safety checks (system apps, suspicious paths, missing bundle ID).
    /// Never deletes anything.
    static func computeSet(for item: AppItem) throws -> UninstallSet {
        // Safety gate 1: refuse Apple-supplied bundles.
        // Apple's apps live in /System/Applications but we also block
        // anything under `com.apple.*` to be defensive against odd layouts.
        if item.bundleID.hasPrefix("com.apple.") {
            throw ComputeError.systemApp
        }

        let bundlePath = item.sourcePath.path

        // Safety gate 2: must be inside a user-writable app root. We
        // deliberately *don't* allow custom source folders from Settings —
        // those are for discovery only.
        if bundlePath.hasPrefix("/System/") {
            throw ComputeError.systemApp
        }
        let allowedPrefixes = [
            "/Applications/",
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/").path,
        ]
        let inAllowedRoot = allowedPrefixes.contains { bundlePath.hasPrefix($0) }
        if !inAllowedRoot {
            throw ComputeError.outsideAllowedRoots
        }

        // Safety gate 3: bundle ID must be present so support-file matching
        // is strict. We never fuzzy-match on app name.
        guard !item.bundleID.isEmpty else { throw ComputeError.bundleIDMissing }

        let bundleSize = directorySize(at: item.sourcePath)
        guard bundleSize > 0 || FileManager.default.fileExists(atPath: bundlePath) else {
            throw ComputeError.bundleUnreadable
        }

        let supportItems = discoverSupportItems(forBundleID: item.bundleID)

        return UninstallSet(
            bundleID: item.bundleID,
            bundleURL: item.sourcePath,
            bundleSize: bundleSize,
            supportItems: supportItems
        )
    }

    /// Standard `~/Library` paths that may carry per-app data. Strictly
    /// bundle-ID-matched — no name matching, no globs. Unreadable paths are
    /// silently skipped (rather than failing the whole computation) so a
    /// missing Full Disk Access doesn't block the whole feature.
    private static func discoverSupportItems(forBundleID bundleID: String) -> [UninstallSet.SupportItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appending(path: "Library")

        struct Candidate {
            let category: String
            let url: URL
        }

        let candidates: [Candidate] = [
            .init(category: "Application Support",
                  url: library.appending(path: "Application Support").appending(path: bundleID)),
            .init(category: "Caches",
                  url: library.appending(path: "Caches").appending(path: bundleID)),
            .init(category: "Preferences",
                  url: library.appending(path: "Preferences").appending(path: "\(bundleID).plist")),
            .init(category: "Containers",
                  url: library.appending(path: "Containers").appending(path: bundleID)),
            .init(category: "Group Containers",
                  url: library.appending(path: "Group Containers").appending(path: bundleID)),
            .init(category: "Saved Application State",
                  url: library.appending(path: "Saved Application State").appending(path: "\(bundleID).savedState")),
            .init(category: "Logs",
                  url: library.appending(path: "Logs").appending(path: bundleID)),
            .init(category: "HTTPStorages",
                  url: library.appending(path: "HTTPStorages").appending(path: bundleID)),
            .init(category: "WebKit",
                  url: library.appending(path: "WebKit").appending(path: bundleID)),
            .init(category: "Cookies",
                  url: library.appending(path: "Cookies").appending(path: "\(bundleID).binarycookies")),
        ]

        var items: [UninstallSet.SupportItem] = []
        for c in candidates where fm.fileExists(atPath: c.url.path) {
            let size = directorySize(at: c.url)
            items.append(.init(category: c.category, url: c.url, size: size, isSelected: true))
        }
        return items
    }

    // MARK: Trash

    /// Move the selected URLs to the Trash. If `simulate` is true, this
    /// logs what it WOULD trash and returns a synthesized success result
    /// without touching anything.
    ///
    /// This is the only function in the project that calls `trashItem`.
    /// Never `FileManager.removeItem`, never `rm`, never anything permanent.
    static func trash(_ set: UninstallSet, simulate: Bool) -> UninstallResult {
        let urls = set.selectedURLs

        if simulate {
            NSLog("Mosaic [UNINSTALL SIMULATION] would trash \(urls.count) items for \(set.bundleID):")
            for url in urls { NSLog("  - \(url.path)") }
            return UninstallResult(trashed: urls, failed: [], simulated: true)
        }

        var trashed: [URL] = []
        var failed: [(url: URL, error: String)] = []

        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.append(url)
            } catch {
                failed.append((url, error.localizedDescription))
                NSLog("Mosaic: failed to trash \(url.path): \(error.localizedDescription)")
            }
        }

        return UninstallResult(trashed: trashed, failed: failed, simulated: false)
    }

    // MARK: Size helpers

    /// Recursive byte size for a path. Returns 0 if unreadable — sizes are
    /// for display only; the trash path doesn't care about size accuracy.
    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

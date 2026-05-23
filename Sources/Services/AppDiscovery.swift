import AppKit
import Foundation

/// Enumerates `.app` bundles under the configured source roots.
@MainActor
enum AppDiscovery {
    static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]

    static func discover(extraRoots: [URL] = []) -> [AppItem] {
        let roots = (defaultRoots + extraRoots).filter { FileManager.default.fileExists(atPath: $0.path) }
        var seen = Set<String>()   // dedupe by bundle ID across roots
        var items: [AppItem] = []

        for root in roots {
            for appURL in appBundles(under: root) {
                guard let item = makeItem(at: appURL) else { continue }
                guard seen.insert(item.bundleID).inserted else { continue }
                items.append(item)
            }
        }

        items.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return items
    }

    private static func appBundles(under root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isApplicationKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return [] }

        var bundles: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                bundles.append(url)
                // .skipsPackageDescendants already keeps us out of the .app, but be defensive.
                enumerator.skipDescendants()
            }
        }
        return bundles
    }

    private static func makeItem(at url: URL) -> AppItem? {
        guard let bundle = Bundle(url: url) else { return nil }
        guard let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { return nil }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)

        return AppItem(
            bundleID: bundleID,
            displayName: displayName,
            icon: icon,
            sourcePath: url
        )
    }
}

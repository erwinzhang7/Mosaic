import Foundation
import Observation

/// User-customizable overrides on top of raw discovery results.
/// Persisted as JSON in Application Support; one source of truth for hidden, renamed,
/// reordered, and foldered apps.
@MainActor
@Observable
final class LayoutStore {
    struct Folder: Codable, Hashable {
        var id: UUID
        var name: String
        var bundleIDs: [String]
    }

    struct State: Codable {
        var hidden: Set<String> = []           // bundle IDs to omit from the grid
        var renames: [String: String] = [:]    // bundle ID → custom display name
        var customSources: [String] = []       // extra directories to scan
        var order: [String] = []               // bundle IDs in display order; unlisted apps trail
        var folders: [Folder] = []             // populated in step 5
    }

    private(set) var state = State()

    static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "com.erwinzhang.mosaic/layout.json")
    }()

    init() { load() }

    func load() {
        guard
            let data = try? Data(contentsOf: Self.fileURL),
            let decoded = try? JSONDecoder().decode(State.self, from: data)
        else { return }
        state = decoded
    }

    func save() {
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// Apply hidden + rename overrides. Ordering and folders arrive in later steps.
    func apply(to items: [AppItem]) -> [AppItem] {
        items.compactMap { item -> AppItem? in
            guard !state.hidden.contains(item.bundleID) else { return nil }
            guard let rename = state.renames[item.bundleID] else { return item }
            var copy = item
            copy.displayName = rename
            return copy
        }
    }
}

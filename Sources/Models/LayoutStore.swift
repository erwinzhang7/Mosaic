import Foundation
import Observation

/// Folder of apps, addressed by stable UUID so renames don't break references.
struct Folder: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var bundleIDs: [String]

    init(id: UUID = UUID(), name: String, bundleIDs: [String]) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
    }
}

/// One position in the top-level grid: either a single app or a folder.
enum Slot: Codable, Hashable {
    case app(String)
    case folder(Folder)
}

/// User-customizable overrides on top of raw discovery results.
/// Persisted as JSON in Application Support; one source of truth for hidden, renamed,
/// reordered, and foldered apps.
@MainActor
@Observable
final class LayoutStore {
    static let shared = LayoutStore()

    struct State: Codable {
        var hidden: Set<String>
        var renames: [String: String]
        var customSources: [String]
        var topLevel: [Slot]
        var summonHotKey: HotKeyBinding

        init() {
            hidden = []
            renames = [:]
            customSources = []
            topLevel = []
            summonHotKey = .default
        }

        // Decode each key optionally so adding new fields later doesn't break
        // existing on-disk JSON.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
            renames = try c.decodeIfPresent([String: String].self, forKey: .renames) ?? [:]
            customSources = try c.decodeIfPresent([String].self, forKey: .customSources) ?? []
            topLevel = try c.decodeIfPresent([Slot].self, forKey: .topLevel) ?? []
            summonHotKey = try c.decodeIfPresent(HotKeyBinding.self, forKey: .summonHotKey) ?? .default
        }

        enum CodingKeys: String, CodingKey {
            case hidden, renames, customSources, topLevel, summonHotKey
        }
    }

    private(set) var state = State()

    static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "com.erwinzhang.mosaic/layout.json")
    }()

    private init() { load() }

    // MARK: Custom sources

    func addCustomSource(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !state.customSources.contains(trimmed) else { return }
        state.customSources.append(trimmed)
        save()
    }

    func removeCustomSource(_ path: String) {
        state.customSources.removeAll { $0 == path }
        save()
    }

    // MARK: Hotkey

    /// Persist a new summon-hotkey binding. Does not touch the Carbon
    /// registration — `AppDelegate.applyHotKey(_:)` is responsible for that
    /// and only saves once registration succeeds.
    func setSummonHotKey(_ binding: HotKeyBinding) {
        state.summonHotKey = binding
        save()
    }

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

    // MARK: Override mutations

    func hide(_ bundleID: String) {
        state.hidden.insert(bundleID)
        detach(bundleID: bundleID)
        save()
    }

    func unhide(_ bundleID: String) {
        state.hidden.remove(bundleID)
        save()
    }

    func rename(_ bundleID: String, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            state.renames.removeValue(forKey: bundleID)
        } else {
            state.renames[bundleID] = trimmed
        }
        save()
    }

    // MARK: Folder mutations

    /// Drop `droppedBundleID` onto another top-level app: replace that target
    /// with a new folder containing both apps (target first, dropped second).
    func createFolder(droppedBundleID: String, ontoTargetBundleID targetBundleID: String) {
        guard droppedBundleID != targetBundleID else { return }
        detach(bundleID: droppedBundleID)
        guard let targetIdx = state.topLevel.firstIndex(of: .app(targetBundleID)) else { return }
        let folder = Folder(name: "New Folder", bundleIDs: [targetBundleID, droppedBundleID])
        state.topLevel[targetIdx] = .folder(folder)
        cleanupEmptyFolders()
        save()
    }

    /// Reorder a top-level app: move `droppedBundleID` so it lands at the
    /// slot currently held by `targetBundleID`. Source can be a tile that
    /// hasn't been explicitly ordered yet (one of `render`'s alphabetically-
    /// trailing apps) — we materialize the full displayed order, perform the
    /// move on that, and write it back as the new authoritative order.
    /// Newly-installed apps still get appended alphabetically by `render`
    /// until the user moves them.
    func reorder(droppedBundleID: String, ontoTargetBundleID targetBundleID: String, allApps: [AppItem]) {
        guard droppedBundleID != targetBundleID else { return }

        // Build the current displayed order as a fresh [Slot] sequence.
        var working: [Slot] = render(allApps: allApps).map { display in
            switch display {
            case .app(let item):
                return .app(item.bundleID)
            case .folder(let f):
                return .folder(Folder(id: f.id, name: f.name, bundleIDs: f.items.map(\.bundleID)))
            }
        }

        let sourceSlot: Slot = .app(droppedBundleID)
        guard let sourceIdx = working.firstIndex(of: sourceSlot) else { return }
        working.remove(at: sourceIdx)

        guard let targetIdx = working.firstIndex(where: {
            if case .app(let b) = $0 { return b == targetBundleID }
            return false
        }) else { return }

        working.insert(sourceSlot, at: targetIdx)

        state.topLevel = working
        save()
    }

    func addToFolder(_ bundleID: String, folderID: UUID) {
        detach(bundleID: bundleID)
        for i in state.topLevel.indices {
            if case .folder(var f) = state.topLevel[i], f.id == folderID, !f.bundleIDs.contains(bundleID) {
                f.bundleIDs.append(bundleID)
                state.topLevel[i] = .folder(f)
            }
        }
        cleanupEmptyFolders()
        save()
    }

    func removeFromFolder(_ bundleID: String, folderID: UUID) {
        for i in state.topLevel.indices {
            if case .folder(var f) = state.topLevel[i], f.id == folderID {
                f.bundleIDs.removeAll { $0 == bundleID }
                state.topLevel[i] = .folder(f)
            }
        }
        if !state.topLevel.contains(.app(bundleID)) {
            state.topLevel.append(.app(bundleID))
        }
        cleanupEmptyFolders()
        save()
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for i in state.topLevel.indices {
            if case .folder(var f) = state.topLevel[i], f.id == folderID {
                f.name = trimmed
                state.topLevel[i] = .folder(f)
            }
        }
        save()
    }

    // MARK: Render

    /// Combine raw discovery with the saved layout to produce the list the
    /// grid should display. Unknown apps (newly installed) are appended at the
    /// end alphabetically.
    func render(allApps: [AppItem]) -> [DisplaySlot] {
        let visible = allApps.filter { !state.hidden.contains($0.bundleID) }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.bundleID, $0) })

        var rendered: [DisplaySlot] = []
        var referenced: Set<String> = []

        for slot in state.topLevel {
            switch slot {
            case .app(let bid):
                if let item = byID[bid] {
                    referenced.insert(bid)
                    rendered.append(.app(applyRename(item)))
                }
            case .folder(let folder):
                let items = folder.bundleIDs.compactMap { byID[$0] }.map(applyRename)
                if items.isEmpty { continue }
                for bid in folder.bundleIDs { referenced.insert(bid) }
                rendered.append(.folder(.init(id: folder.id, name: folder.name, items: items)))
            }
        }

        for item in visible where !referenced.contains(item.bundleID) {
            rendered.append(.app(applyRename(item)))
        }

        return rendered
    }

    private func applyRename(_ item: AppItem) -> AppItem {
        guard let name = state.renames[item.bundleID] else { return item }
        var copy = item
        copy.displayName = name
        return copy
    }

    // MARK: Helpers

    private func detach(bundleID: String) {
        state.topLevel.removeAll { $0 == .app(bundleID) }
        for i in state.topLevel.indices {
            if case .folder(var f) = state.topLevel[i] {
                f.bundleIDs.removeAll { $0 == bundleID }
                state.topLevel[i] = .folder(f)
            }
        }
    }

    private func cleanupEmptyFolders() {
        state.topLevel.removeAll { slot in
            if case .folder(let f) = slot { return f.bundleIDs.isEmpty }
            return false
        }
    }
}

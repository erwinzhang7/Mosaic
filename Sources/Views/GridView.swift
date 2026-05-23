import AppKit
import SwiftUI

struct GridView: View {
    var onDismiss: (() -> Void)? = nil

    @State private var allApps: [AppItem] = []
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    @Bindable private var layout = LayoutStore.shared
    @Bindable private var prefs = Preferences.shared

    @State private var renamingItem: AppItem?
    @State private var renameDraft: String = ""
    @State private var openFolderID: UUID?

    private var iconSize: CGFloat { prefs.iconSize }
    private var columnMinWidth: CGFloat { prefs.columnMinWidth }
    private let columnSpacing: CGFloat = 24
    private let rowSpacing: CGFloat = 28

    /// Rendered slots derived from the latest discovery + layout state.
    private var slots: [DisplaySlot] {
        layout.render(allApps: allApps)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The first app slot in the filtered list, when a search is active.
    /// Used to highlight the Return-key target and to drive launchFirstMatch.
    private var firstMatchBundleID: String? {
        guard !trimmedQuery.isEmpty else { return nil }
        for slot in visibleSlots {
            if case .app(let item) = slot { return item.bundleID }
        }
        return nil
    }

    /// Slots filtered by the live search. Folders are kept if their name
    /// matches OR any contained app does.
    private var visibleSlots: [DisplaySlot] {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else { return slots }
        return slots.compactMap { slot in
            switch slot {
            case .app(let item):
                return item.displayName.localizedCaseInsensitiveContains(trimmed) ? slot : nil
            case .folder(let folder):
                let nameMatch = folder.name.localizedCaseInsensitiveContains(trimmed)
                let matchingItems = folder.items.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
                if nameMatch { return slot }
                if matchingItems.isEmpty { return nil }
                return .folder(.init(id: folder.id, name: folder.name, items: matchingItems))
            }
        }
    }

    private var openFolder: DisplayFolder? {
        guard let id = openFolderID else { return nil }
        for slot in slots {
            if case .folder(let f) = slot, f.id == id { return f }
        }
        return nil
    }

    var body: some View {
        ZStack {
            mainContent

            if let folder = openFolder {
                folderModal(for: folder)
            }

            if let item = renamingItem {
                renameModal(for: item)
            }
        }
        .task {
            reload()
        }
        .onChange(of: layout.state.customSources) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicOverlayDidBecomeKey)) { _ in
            handleSummon()
        }
        .onExitCommand {
            if renamingItem != nil { cancelRename() }
            else if openFolderID != nil { openFolderID = nil; Task { await restoreSearchFocus() } }
            else if !query.isEmpty { query = "" }
            else { onDismiss?() }
        }
        .onSubmit { launchFirstMatch() }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, focused: $searchFocused)
                .padding(.top, 24)
                .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: iconSize + 32), spacing: columnSpacing)],
                    spacing: rowSpacing
                ) {
                    ForEach(visibleSlots) { slot in
                        slotView(for: slot)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
            }
        }
        .background(
            Color.clear.contentShape(Rectangle())
                .onTapGesture { onDismiss?() }
        )
    }

    @ViewBuilder
    private func slotView(for slot: DisplaySlot) -> some View {
        switch slot {
        case .app(let item):
            AppTile(
                item: item,
                iconSize: iconSize,
                context: .grid,
                isHighlighted: item.bundleID == firstMatchBundleID
            ) { action in
                handle(action, for: item)
            }
            .dropDestination(for: String.self) { dropped, _ in
                guard let droppedID = dropped.first, droppedID != item.bundleID else { return false }
                layout.createFolder(droppedBundleID: droppedID, ontoTargetBundleID: item.bundleID)
                reload()
                return true
            }

        case .folder(let folder):
            FolderTile(folder: folder, iconSize: iconSize, onOpen: {
                openFolderID = folder.id
                searchFocused = false
            }, onDropApp: { droppedID in
                guard !droppedID.isEmpty else { return false }
                layout.addToFolder(droppedID, folderID: folder.id)
                reload()
                return true
            })
        }
    }

    private func folderModal(for folder: DisplayFolder) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    openFolderID = nil
                    Task { await restoreSearchFocus() }
                }
            FolderOpenView(
                folder: folder,
                iconSize: iconSize,
                onLaunch: { launch($0) },
                onReveal: { item in
                    NSWorkspace.shared.activateFileViewerSelecting([item.sourcePath])
                    onDismiss?()
                },
                onRemove: { item in
                    layout.removeFromFolder(item.bundleID, folderID: folder.id)
                    reload()
                    // Folder may have been auto-deleted (last app removed).
                    if !slots.contains(where: { if case .folder(let f) = $0 { return f.id == folder.id }; return false }) {
                        openFolderID = nil
                        Task { await restoreSearchFocus() }
                    }
                },
                onRename: { newName in
                    layout.renameFolder(folder.id, to: newName)
                    reload()
                },
                onClose: {
                    openFolderID = nil
                    Task { await restoreSearchFocus() }
                }
            )
        }
        .transition(.opacity)
    }

    private func renameModal(for item: AppItem) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { cancelRename() }
            RenameSheet(
                originalName: item.displayName,
                draft: $renameDraft,
                onSave: commitRename,
                onCancel: cancelRename
            )
        }
        .transition(.opacity)
    }

    // MARK: Actions

    private func handle(_ action: AppTile.Action, for item: AppItem) {
        switch action {
        case .launch:
            launch(item)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([item.sourcePath])
            onDismiss?()
        case .rename:
            renameDraft = item.displayName
            searchFocused = false
            renamingItem = item
        case .hide:
            layout.hide(item.bundleID)
            reload()
        case .removeFromFolder:
            break  // handled in folder modal
        }
    }

    private func reload() {
        let extra = layout.state.customSources.map { URL(fileURLWithPath: $0) }
        allApps = AppDiscovery.discover(extraRoots: extra)
    }

    /// Reset transient UI state and claim search-field focus on every summon.
    /// Driven by `.mosaicOverlayDidBecomeKey`, so this fires exactly when the
    /// window actually has keyboard input — no timed guessing.
    private func handleSummon() {
        query = ""
        renamingItem = nil
        renameDraft = ""
        openFolderID = nil

        // Defer the focus claim by one runloop tick so SwiftUI has finished
        // tearing down any modal we just cleared above. Without this, the
        // focus assignment can land on a half-removed sheet's TextField.
        Task { @MainActor in
            searchFocused = true
        }
    }

    /// Return focus to the search field after a SwiftUI modal closes.
    /// The small delay gives SwiftUI a tick to finish removing the modal's
    /// own TextField before we claim focus — without it, focus can land
    /// nowhere because the modal's FocusState owner is still resigning.
    /// Only fires when no modal is up, so a late call can't yank focus
    /// away from a sheet that opened in the meantime.
    private func restoreSearchFocus() async {
        try? await Task.sleep(for: .milliseconds(40))
        guard renamingItem == nil, openFolderID == nil else { return }
        searchFocused = true
    }

    private func launch(_ item: AppItem) {
        AppLauncher.launch(item)
        query = ""
        openFolderID = nil
        onDismiss?()
    }

    private func launchFirstMatch() {
        // Don't fire on an empty query — pressing Return immediately after
        // summon shouldn't launch a random "first app." It only acts when
        // the user has narrowed the grid by typing.
        guard !trimmedQuery.isEmpty, openFolderID == nil else { return }
        for slot in visibleSlots {
            if case .app(let item) = slot {
                launch(item)
                return
            }
        }
    }

    private func commitRename() {
        guard let item = renamingItem else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (trimmed.isEmpty || trimmed == item.displayName) ? nil : trimmed
        layout.rename(item.bundleID, to: target)
        reload()
        renamingItem = nil
        Task { await restoreSearchFocus() }
    }

    private func cancelRename() {
        renamingItem = nil
        Task { await restoreSearchFocus() }
    }
}

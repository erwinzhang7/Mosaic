import AppKit
import SwiftUI

struct GridView: View {
    var onDismiss: (() -> Void)? = nil

    @State private var allApps: [AppItem] = []
    @State private var slots: [DisplaySlot] = []
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    @State private var layout = LayoutStore()

    @State private var renamingItem: AppItem?
    @State private var renameDraft: String = ""
    @State private var openFolderID: UUID?

    private let iconSize: CGFloat = 80
    private let columnSpacing: CGFloat = 24
    private let rowSpacing: CGFloat = 28

    /// Slots filtered by the live search. Folders are kept if their name
    /// matches OR any contained app does.
    private var visibleSlots: [DisplaySlot] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
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
            await refocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicOverlayDidShow)) { _ in
            query = ""
            renamingItem = nil
            openFolderID = nil
            Task { await refocus() }
        }
        .onExitCommand {
            if renamingItem != nil { cancelRename() }
            else if openFolderID != nil { openFolderID = nil; Task { await refocus() } }
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
            AppTile(item: item, iconSize: iconSize, context: .grid) { action in
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
                    Task { await refocus() }
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
                        Task { await refocus() }
                    }
                },
                onRename: { newName in
                    layout.renameFolder(folder.id, to: newName)
                    reload()
                },
                onClose: {
                    openFolderID = nil
                    Task { await refocus() }
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
        slots = layout.render(allApps: allApps)
    }

    private func refocus() async {
        try? await Task.sleep(for: .milliseconds(40))
        searchFocused = true
    }

    private func launch(_ item: AppItem) {
        AppLauncher.launch(item)
        query = ""
        openFolderID = nil
        onDismiss?()
    }

    private func launchFirstMatch() {
        // When a folder is open, Return on the search field doesn't apply.
        guard openFolderID == nil else { return }
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
        Task { await refocus() }
    }

    private func cancelRename() {
        renamingItem = nil
        Task { await refocus() }
    }
}

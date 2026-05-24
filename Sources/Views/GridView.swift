import AppKit
import SwiftUI

struct GridView: View {
    var onDismiss: (() -> Void)? = nil

    @State private var allApps: [AppItem] = []
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    @Bindable private var layout = LayoutStore.shared
    @Bindable private var prefs = Preferences.shared
    @Bindable private var permission = AccessibilityPermission.shared

    @State private var renamingItem: AppItem?
    @State private var renameDraft: String = ""
    @State private var openFolderID: UUID?
    @State private var folderBackdropTargeted = false

    // Windows mode state — enumeration runs on mode switch, not on a timer.
    @State private var mode: OverlayMode = .apps
    @State private var windows: [WindowItem] = []

    // Uninstall modal state. Non-nil only while the modal is on screen.
    @State private var uninstallSet: UninstallSet?
    @State private var uninstallError: String?

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

    // MARK: Windows mode

    private var filteredWindows: [WindowItem] {
        let q = trimmedQuery
        guard !q.isEmpty else { return windows }
        return windows.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(q)
                || $0.ownerName.localizedCaseInsensitiveContains(q)
        }
    }

    private var firstWindowMatchID: CGWindowID? {
        guard !trimmedQuery.isEmpty else { return nil }
        return filteredWindows.first?.id
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

            if let set = uninstallSet {
                uninstallModalView(for: set)
            }

            if let message = uninstallError {
                uninstallErrorView(message)
            }
        }
        .task {
            reload()
        }
        .onChange(of: layout.state.customSources) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicOverlayDidBecomeKey)) { _ in
            handleSummon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicAppLaunchFailed)) { _ in
            // The bundle was likely moved/deleted between scan and launch.
            // Re-discover so the stale tile clears. The toast itself is shown
            // by AppDelegate (the overlay may already be hidden by the time
            // this fires).
            reload()
        }
        .onExitCommand {
            if uninstallError != nil { uninstallError = nil; Task { await restoreSearchFocus() } }
            else if uninstallSet != nil { closeUninstall() }
            else if renamingItem != nil { cancelRename() }
            else if openFolderID != nil { openFolderID = nil; Task { await restoreSearchFocus() } }
            else if !query.isEmpty { query = "" }
            else { onDismiss?() }
        }
        .onSubmit {
            switch mode {
            case .apps:    launchFirstMatch()
            case .windows: selectFirstWindowMatch()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            modeSwitcher
                .padding(.top, 18)
                .padding(.bottom, 4)

            SearchField(text: $query, focused: $searchFocused)
                .padding(.bottom, 8)

            ScrollView {
                switch mode {
                case .apps:    appsGrid
                case .windows: windowsList
                }
            }
        }
        .background(
            Color.clear.contentShape(Rectangle())
                .onTapGesture { onDismiss?() }
        )
    }

    private var modeSwitcher: some View {
        Picker("", selection: $mode) {
            ForEach(OverlayMode.allCases, id: \.self) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 220)
        .onChange(of: mode) { _, newMode in
            if newMode == .windows {
                reloadWindows()
            }
            // The picker steals focus on click; give it back to the search field
            // so typing keeps filtering immediately.
            Task { @MainActor in searchFocused = true }
        }
    }

    @ViewBuilder
    private var appsGrid: some View {
        if slots.isEmpty {
            EmptyStateView(
                icon: "tray",
                title: "No apps to show",
                message: "Mosaic scans /Applications, /System/Applications, and ~/Applications. If your apps live elsewhere, add the folder in Settings ▸ Sources.",
                primaryAction: .init(label: "Open Sources Settings") {
                    onDismiss?()
                    openSettingsWindow()
                }
            )
        } else if visibleSlots.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Nothing in your apps matches \u{201C}\(trimmedQuery)\u{201D}.",
                primaryAction: .init(label: "Clear search") { query = "" }
            )
        } else {
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

    @ViewBuilder
    private var windowsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !permission.isTrusted {
                permissionBannerForWindows
            }

            if windows.isEmpty {
                EmptyStateView(
                    icon: "macwindow",
                    title: "No open windows",
                    message: "Open something in another app and switch back to see it here."
                )
            } else if filteredWindows.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No matches",
                    message: "No open windows match \u{201C}\(trimmedQuery)\u{201D}.",
                    primaryAction: .init(label: "Clear search") { query = "" }
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 12)],
                    spacing: 10
                ) {
                    ForEach(filteredWindows) { item in
                        WindowTile(
                            item: item,
                            iconSize: 32,
                            isHighlighted: item.id == firstWindowMatchID
                        ) {
                            selectWindow(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.bottom, 40)
        .padding(.top, 4)
    }

    private var permissionBannerForWindows: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Limited without Accessibility")
                    .font(.callout.weight(.semibold))
                Text("Window titles for other apps may be empty, and selecting a window only activates its app rather than raising that specific window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open System Settings") { permission.openSystemSettings() }
                        .buttonStyle(.link)
                    Button("Re-check") { permission.refresh() }
                        .buttonStyle(.link)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
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
                isHighlighted: item.bundleID == firstMatchBundleID,
                uninstallEnabled: prefs.uninstallEnabled
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
            Color.black.opacity(folderBackdropTargeted ? 0.6 : 0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    openFolderID = nil
                    Task { await restoreSearchFocus() }
                }
                .dropDestination(for: String.self) { droppedIDs, _ in
                    // Drop a folder-tile outside the panel = remove from folder.
                    // Only honor drops that actually originated from this folder
                    // (top-level drags can't reach here while the modal is up,
                    // but be defensive).
                    guard let bid = droppedIDs.first,
                          folder.items.contains(where: { $0.bundleID == bid })
                    else { return false }
                    layout.removeFromFolder(bid, folderID: folder.id)
                    // Folder may have been auto-pruned (last item removed).
                    if !slots.contains(where: {
                        if case .folder(let f) = $0 { return f.id == folder.id }
                        return false
                    }) {
                        openFolderID = nil
                        Task { await restoreSearchFocus() }
                    }
                    return true
                } isTargeted: { folderBackdropTargeted = $0 }
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
        case .uninstall:
            beginUninstall(for: item)
        }
    }

    // MARK: Uninstall

    private func beginUninstall(for item: AppItem) {
        do {
            uninstallSet = try Uninstaller.computeSet(for: item)
            searchFocused = false
        } catch {
            uninstallError = error.localizedDescription
        }
    }

    private func closeUninstall() {
        uninstallSet = nil
        Task { await restoreSearchFocus() }
    }

    private func uninstallModalView(for set: UninstallSet) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                // Intentionally NO onTapGesture to dismiss — destructive
                // operations should require explicit cancel via the buttons,
                // not stray backdrop clicks.
            UninstallModal(
                set: set,
                simulate: prefs.uninstallSimulate,
                onConfirm: { confirmed in
                    let result = Uninstaller.trash(confirmed, simulate: prefs.uninstallSimulate)
                    if !result.simulated { reload() }
                    return result
                },
                onClose: { closeUninstall() }
            )
        }
        .transition(.opacity)
    }

    private func uninstallErrorView(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { uninstallError = nil; Task { await restoreSearchFocus() } }
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Can't uninstall this app")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .foregroundStyle(.secondary)
                Button("OK") { uninstallError = nil; Task { await restoreSearchFocus() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(28)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            )
        }
        .transition(.opacity)
    }

    private func reload() {
        let extra = layout.state.customSources.map { URL(fileURLWithPath: $0) }
        allApps = AppDiscovery.discover(extraRoots: extra)
    }

    private func openSettingsWindow() {
        // Same path AppDelegate uses for its menu-bar Settings… item.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func reloadWindows() {
        windows = WindowDiscovery.discover()
    }

    private func selectWindow(_ item: WindowItem) {
        // Lazy permission prompt: AX is needed to raise the specific window
        // and to read most window titles. The first click fires the system
        // prompt; if denied, raise() falls back to activating the owning app.
        if !permission.isTrusted {
            permission.requestPrompt()
        }
        WindowRaiser.raise(item)
        query = ""
        onDismiss?()
    }

    private func selectFirstWindowMatch() {
        // Mirror launchFirstMatch's behavior: Return on an empty query should
        // not trigger anything destructive (here, raising an arbitrary first
        // window). Only fire when the user has narrowed the list.
        guard !trimmedQuery.isEmpty else { return }
        if let item = filteredWindows.first {
            selectWindow(item)
        }
    }

    /// Reset transient UI state and claim search-field focus on every summon.
    /// Driven by `.mosaicOverlayDidBecomeKey`, so this fires exactly when the
    /// window actually has keyboard input — no timed guessing.
    private func handleSummon() {
        query = ""
        renamingItem = nil
        renameDraft = ""
        openFolderID = nil
        uninstallSet = nil
        uninstallError = nil
        // Default summon mode is always Apps — windows mode is opt-in per summon.
        mode = .apps
        // Windows enumeration is stale once we return to the overlay; drop it
        // so the next windows-mode switch re-enumerates fresh.
        windows = []

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

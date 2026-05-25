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

    // Paged-layout state — only consulted when prefs.verticalScroll is false
    // AND there's no active search.
    @State private var currentPageID: Int?
    @State private var topSafeInset: CGFloat = 0
    /// Tiles per page in the horizontal layout, computed from the paged
    /// container's geometry. Persisted in @State so the arrow-key monitor
    /// (which runs outside the SwiftUI body) can read the latest value.
    @State private var pagedTilesPerPage: Int = 35
    @State private var arrowKeyMonitor = ArrowKeyMonitorBox()

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

    /// Slots filtered and ranked by the live search. A folder match retains
    /// all contents; a child-only match narrows the displayed contents.
    private var visibleSlots: [DisplaySlot] {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else { return slots }
        return slots.enumerated().compactMap { offset, slot -> (Int, Int, DisplaySlot)? in
            switch slot {
            case .app(let item):
                guard let score = SearchMatcher.score(item.displayName, query: trimmed) else { return nil }
                return (offset, score, slot)
            case .folder(let folder):
                let nameScore = SearchMatcher.score(folder.name, query: trimmed)
                let matchingItems = folder.items.compactMap { item -> (AppItem, Int)? in
                    guard let score = SearchMatcher.score(item.displayName, query: trimmed) else { return nil }
                    return (item, score)
                }
                let itemScore = matchingItems.map { $0.1 }.max()
                guard let score = [nameScore, itemScore].compactMap({ $0 }).max() else { return nil }
                if nameScore != nil {
                    return (offset, score, slot)
                }
                let narrowed = matchingItems.map(\.0)
                return (offset, score, .folder(.init(id: folder.id, name: folder.name, items: narrowed)))
            }
        }
        .sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
        }
        .map { $0.2 }
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
        return windows.enumerated().compactMap { offset, item -> (Int, Int, WindowItem)? in
            let titleScore = SearchMatcher.score(item.displayTitle, query: q)
            let ownerScore = SearchMatcher.score(item.ownerName, query: q)
            guard let score = [titleScore, ownerScore].compactMap({ $0 }).max() else { return nil }
            return (offset, score, item)
        }
        .sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
        }
        .map { $0.2 }
    }

    private var firstWindowMatchID: CGWindowID? {
        guard !trimmedQuery.isEmpty else { return nil }
        return filteredWindows.first?.id
    }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { handleBackgroundClick() }

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
            installArrowKeyMonitor()
        }
        .onChange(of: layout.state.customSources) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicOverlayDidBecomeKey)) { _ in
            handleSummon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicOverlayBackgroundClick)) { _ in
            // AppKit catch-all dismiss path (see OverlayWindow.sendEvent).
            // handleBackgroundClick already guards against firing while a
            // modal is up.
            handleBackgroundClick()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            topSafeInset = NSScreen.main?.safeAreaInsets.top ?? 0
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
                .padding(.top, 18 + topSafeInset)
                .padding(.bottom, 4)

            SearchField(text: $query, focused: $searchFocused)
                .padding(.bottom, 8)

            Group {
                switch mode {
                case .apps:    appsContent
                case .windows: ScrollView { windowsList }
                }
            }
        }
        // Dismiss layer behind mainContent. The ZStack's outer Color.clear
        // doesn't catch clicks inside the ScrollView's empty content area
        // (ScrollView absorbs them for its own gesture system). This
        // .background sits within mainContent's frame so those clicks fall
        // through to it instead. Tiles / picker / search still consume
        // their own clicks above this.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleBackgroundClick() }
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
    private var appsContent: some View {
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
        } else if prefs.verticalScroll || !trimmedQuery.isEmpty {
            // Single vertical-scrolling grid. Always used when searching —
            // paged layout doesn't fit short, filtered result sets cleanly.
            ScrollView { appsScrollGrid }
        } else {
            // Paged horizontal layout.
            appsPagedGrid
        }
    }

    private var appsScrollGrid: some View {
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

    private var appsPagedGrid: some View {
        GeometryReader { geo in
            let dotsReserve: CGFloat = 30
            let pageHeight = max(0, geo.size.height - dotsReserve)
            let pageSize = CGSize(width: geo.size.width, height: pageHeight)
            let perPage = computePerPage(in: pageSize)
            let pages = paginate(visibleSlots, by: perPage)

            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { idx in
                            pageGrid(slots: pages[idx])
                                .frame(width: pageSize.width, height: pageHeight)
                                .id(idx)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentPageID)
                .frame(height: pageHeight)

                if pages.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { idx in
                            Circle()
                                .fill((currentPageID ?? 0) == idx ? Color.primary.opacity(0.85) : Color.primary.opacity(0.25))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .frame(height: dotsReserve)
                }
            }
            // Keep @State perPage in sync so the arrow-key monitor (outside
            // SwiftUI body) reads the current value.
            .onAppear { pagedTilesPerPage = perPage }
            .onChange(of: perPage) { _, new in pagedTilesPerPage = new }
        }
    }

    /// Adaptive tile-per-page count: max columns × max rows that fit in the
    /// page area, given the user's icon size and our internal padding.
    /// Replaces the previous hardcoded 35 — pages now fill the screen.
    private func computePerPage(in size: CGSize) -> Int {
        let tileWidth = iconSize + 32 + columnSpacing
        let tileHeight = iconSize + 28 + rowSpacing  // icon + label + spacing
        let usableW = max(0, size.width - 120)       // pageGrid's horizontal padding
        let usableH = max(0, size.height - 60)       // pageGrid's vertical padding
        let cols = max(1, Int(usableW / tileWidth))
        let rows = max(1, Int(usableH / tileHeight))
        return max(1, cols * rows)
    }

    private func paginate(_ slots: [DisplaySlot], by perPage: Int) -> [[DisplaySlot]] {
        guard perPage > 0, !slots.isEmpty else { return [slots] }
        return stride(from: 0, to: slots.count, by: perPage).map { start in
            Array(slots[start..<min(start + perPage, slots.count)])
        }
    }

    private func pageGrid(slots: [DisplaySlot]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: iconSize + 32), spacing: columnSpacing)],
            spacing: rowSpacing
        ) {
            ForEach(slots) { slot in
                slotView(for: slot)
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                // Default: reorder. Hold Option at drop time to create a
                // folder instead — matches the Launchpad-style intuition
                // (drag = move, modifier = combine).
                if NSEvent.modifierFlags.contains(.option) {
                    layout.createFolder(droppedBundleID: droppedID, ontoTargetBundleID: item.bundleID)
                } else {
                    layout.reorder(droppedBundleID: droppedID, ontoTargetBundleID: item.bundleID, allApps: allApps)
                }
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

    private func handleBackgroundClick() {
        guard renamingItem == nil,
              openFolderID == nil,
              uninstallSet == nil,
              uninstallError == nil
        else { return }
        onDismiss?()
    }

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
        topSafeInset = NSScreen.main?.safeAreaInsets.top ?? 0
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

    // MARK: Paged-layout arrow-key navigation

    /// Install a local NSEvent monitor that turns ←/→ into page navigation
    /// when we're in paged mode with an empty query and no modal up.
    /// AppKit-level interception is necessary because the search TextField
    /// consumes arrow keys for cursor movement, beating any SwiftUI
    /// `.onKeyPress` we'd place at the parent level.
    private func installArrowKeyMonitor() {
        arrowKeyMonitor.install { specialKey in
            // Only intercept when paged apps mode is actually active and no
            // modal / search context wants the keys.
            guard self.mode == .apps,
                  !self.prefs.verticalScroll,
                  self.trimmedQuery.isEmpty,
                  self.renamingItem == nil,
                  self.openFolderID == nil,
                  self.uninstallSet == nil,
                  self.uninstallError == nil
            else { return false }

            switch specialKey {
            case .leftArrow:
                let current = self.currentPageID ?? 0
                if current > 0 { self.currentPageID = current - 1 }
                return true
            case .rightArrow:
                let pageCount = max(
                    1,
                    Int(ceil(Double(self.visibleSlots.count) / Double(max(1, self.pagedTilesPerPage))))
                )
                let current = self.currentPageID ?? 0
                if current < pageCount - 1 { self.currentPageID = current + 1 }
                return true
            default:
                return false
            }
        }
    }
}

/// Boxes the opaque token from `NSEvent.addLocalMonitorForEvents`. Hands the
/// handler only `NSEvent.SpecialKey?` (Sendable) instead of the raw NSEvent,
/// dodging Swift 6's "NSEvent isn't Sendable" rule for cross-isolation calls.
/// The handler returns true to swallow the keypress, false to pass it through.
@MainActor
final class ArrowKeyMonitorBox {
    private var token: Any?

    func install(handler: @escaping @MainActor (NSEvent.SpecialKey?) -> Bool) {
        uninstall()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
            // Unwrap the Sendable bits on this side of the boundary, then
            // call into the main-actor handler with just those.
            let special = event.specialKey
            let swallow = MainActor.assumeIsolated { handler(special) }
            return swallow ? nil : event
        }
    }

    func uninstall() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

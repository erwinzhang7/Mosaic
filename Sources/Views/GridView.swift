import AppKit
import SwiftUI

struct GridView: View {
    var onDismiss: (() -> Void)? = nil

    @State private var allItems: [AppItem] = []
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    @State private var layout = LayoutStore()

    @State private var renamingItem: AppItem?
    @State private var renameDraft: String = ""

    private let iconSize: CGFloat = 80
    private let columnSpacing: CGFloat = 24
    private let rowSpacing: CGFloat = 28

    private var filteredItems: [AppItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allItems }
        return allItems.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SearchField(text: $query, focused: $searchFocused)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: iconSize + 32), spacing: columnSpacing)],
                        spacing: rowSpacing
                    ) {
                        ForEach(filteredItems) { item in
                            AppTile(item: item, iconSize: iconSize) { action in
                                handle(action, for: item)
                            }
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

            if let item = renamingItem {
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
        }
        .task {
            reload()
            await refocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicOverlayDidShow)) { _ in
            query = ""
            renamingItem = nil
            Task { await refocus() }
        }
        .onExitCommand {
            if renamingItem != nil {
                cancelRename()
            } else if !query.isEmpty {
                query = ""
            } else {
                onDismiss?()
            }
        }
        .onSubmit { launchFirstMatch() }
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
        }
    }

    private func reload() {
        let extra = layout.state.customSources.map { URL(fileURLWithPath: $0) }
        allItems = layout.apply(to: AppDiscovery.discover(extraRoots: extra))
    }

    private func refocus() async {
        try? await Task.sleep(for: .milliseconds(40))
        searchFocused = true
    }

    private func launch(_ item: AppItem) {
        AppLauncher.launch(item)
        query = ""
        onDismiss?()
    }

    private func launchFirstMatch() {
        if let first = filteredItems.first {
            launch(first)
        }
    }

    private func commitRename() {
        guard let item = renamingItem else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty value or the unchanged original both mean "no override".
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

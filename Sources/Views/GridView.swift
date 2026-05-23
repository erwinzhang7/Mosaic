import SwiftUI

struct GridView: View {
    var onDismiss: (() -> Void)? = nil

    @State private var allItems: [AppItem] = []
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    @State private var layout = LayoutStore()

    private let iconSize: CGFloat = 80
    private let columnSpacing: CGFloat = 24
    private let rowSpacing: CGFloat = 28

    private var filteredItems: [AppItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allItems }
        return allItems.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
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
                        AppTile(item: item, iconSize: iconSize) {
                            launch(item)
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
            }

            // Click in dead space to dismiss.
            Color.clear
                .frame(height: 0)
        }
        .background(
            // Catches mouse-down in any otherwise-empty area of the overlay.
            Color.clear.contentShape(Rectangle())
                .onTapGesture { onDismiss?() }
        )
        .task {
            reload()
            await refocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mosaicOverlayDidShow)) { _ in
            query = ""
            Task { await refocus() }
        }
        .onExitCommand {
            if query.isEmpty {
                onDismiss?()
            } else {
                query = ""
            }
        }
        .onSubmit { launchFirstMatch() }
    }

    private func reload() {
        let extra = layout.state.customSources.map { URL(fileURLWithPath: $0) }
        allItems = layout.apply(to: AppDiscovery.discover(extraRoots: extra))
    }

    private func refocus() async {
        // Small hop so SwiftUI has actually mounted the TextField.
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
}

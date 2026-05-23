import SwiftUI

struct GridView: View {
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
                .padding(.top, 20)
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
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .task {
            reload()
            searchFocused = true
        }
        .onExitCommand { query = "" }
        .onSubmit { launchFirstMatch() }
    }

    private func reload() {
        let extra = layout.state.customSources.map { URL(fileURLWithPath: $0) }
        allItems = layout.apply(to: AppDiscovery.discover(extraRoots: extra))
    }

    private func launch(_ item: AppItem) {
        AppLauncher.launch(item)
        query = ""
    }

    private func launchFirstMatch() {
        if let first = filteredItems.first {
            launch(first)
        }
    }
}

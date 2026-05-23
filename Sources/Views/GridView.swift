import SwiftUI

struct GridView: View {
    @State private var items: [AppItem] = []
    @State private var layout = LayoutStore()

    private let iconSize: CGFloat = 80
    private let columnSpacing: CGFloat = 24
    private let rowSpacing: CGFloat = 28

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: iconSize + 32), spacing: columnSpacing)],
                spacing: rowSpacing
            ) {
                ForEach(items) { item in
                    AppTile(item: item, iconSize: iconSize) {
                        AppLauncher.launch(item)
                    }
                }
            }
            .padding(40)
        }
        .task { reload() }
    }

    private func reload() {
        let raw = AppDiscovery.discover(extraRoots: layout.state.customSources.map { URL(fileURLWithPath: $0) })
        items = layout.apply(to: raw)
    }
}

import SwiftUI

/// Top-level folder representation in the main grid. Shows a 2×2 preview of
/// the contained icons over a glass background. Click opens the folder;
/// dropping an app on it adds that app to the folder.
struct FolderTile: View {
    let folder: DisplayFolder
    let iconSize: CGFloat
    let onOpen: () -> Void
    /// Called when an app is dropped on the tile. Returns `true` if accepted.
    let onDropApp: (String) -> Bool

    @State private var isHovering = false
    @State private var isTargeted = false

    private var miniSize: CGFloat { (iconSize - 24) / 2 }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                        .frame(width: iconSize, height: iconSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    isTargeted ? Color.accentColor : Color.white.opacity(isHovering ? 0.18 : 0.08),
                                    lineWidth: isTargeted ? 2 : 1
                                )
                        )

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(miniSize), spacing: 4), count: 2),
                        spacing: 4
                    ) {
                        ForEach(Array(folder.items.prefix(4))) { item in
                            Image(nsImage: item.icon)
                                .resizable()
                                .interpolation(.medium)
                                .frame(width: miniSize, height: miniSize)
                        }
                    }
                    .frame(width: iconSize - 16, height: iconSize - 16)
                }
                .padding(8)

                Text(folder.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: iconSize + 24)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(folder.name)
        .dropDestination(for: String.self) { dropped, _ in
            guard let id = dropped.first else { return false }
            return onDropApp(id)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

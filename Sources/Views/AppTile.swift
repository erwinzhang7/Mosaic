import SwiftUI

struct AppTile: View {
    enum Action {
        case launch, reveal, rename, hide, removeFromFolder
    }

    enum Context {
        case grid    // top-level: rename + hide
        case folder  // inside an open folder: removeFromFolder
    }

    let item: AppItem
    let iconSize: CGFloat
    var context: Context = .grid
    /// Drawn with a ring to mark it as the Return-key target.
    var isHighlighted: Bool = false
    let onAction: (Action) -> Void

    @State private var isHovering = false

    var body: some View {
        Button { onAction(.launch) } label: {
            VStack(spacing: 8) {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .opacity(isHighlighted ? 1 : 0)
                    )

                Text(item.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: iconSize + 24)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.displayName)
        .contextMenu { menuItems }
        .draggable(item.bundleID) {
            // Drag preview
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Launch") { onAction(.launch) }
        Button("Reveal in Finder") { onAction(.reveal) }
        Divider()
        switch context {
        case .grid:
            Button("Rename…") { onAction(.rename) }
            Button("Hide") { onAction(.hide) }
        case .folder:
            Button("Remove from Folder") { onAction(.removeFromFolder) }
        }
    }
}

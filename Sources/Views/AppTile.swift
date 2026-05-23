import SwiftUI

struct AppTile: View {
    let item: AppItem
    let iconSize: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
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
    }
}

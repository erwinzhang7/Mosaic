import SwiftUI

/// One row in the Windows browsing list: app icon + window title + app name.
/// Click to raise.
struct WindowTile: View {
    let item: WindowItem
    let iconSize: CGFloat
    /// Drawn with an accent ring when this is the Return-key target.
    var isHighlighted: Bool = false
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.ownerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isHighlighted ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(item.displayTitle) — \(item.ownerName)")
    }
}

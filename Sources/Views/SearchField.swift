import SwiftUI

/// Search "pill" that fades in once the user starts typing.
/// Stays in the layout tree so the grid below doesn't jump.
struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 280)
        .background(
            Capsule().fill(Color.primary.opacity(0.08))
        )
        .opacity(text.isEmpty ? 0 : 1)
        .allowsHitTesting(!text.isEmpty)
        .animation(.easeOut(duration: 0.12), value: text.isEmpty)
    }
}

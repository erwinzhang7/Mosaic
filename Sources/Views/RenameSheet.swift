import SwiftUI

/// In-app modal for renaming an app. We render this inside the overlay rather
/// than using `.alert` / `.sheet` because the overlay window lives at
/// `.screenSaver` level and AppKit sheets attached there are unreliable.
struct RenameSheet: View {
    let originalName: String
    @Binding var draft: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename")
                .font(.headline)

            Text("Original: \(originalName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { onSave() }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        )
        .task {
            try? await Task.sleep(for: .milliseconds(40))
            fieldFocused = true
        }
    }
}

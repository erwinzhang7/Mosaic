import AppKit
import SwiftUI

/// Modal panel showing the contents of one folder. Allows launching apps,
/// removing them from the folder, and renaming the folder itself.
struct FolderOpenView: View {
    let folder: DisplayFolder
    let iconSize: CGFloat
    let onLaunch: (AppItem) -> Void
    let onReveal: (AppItem) -> Void
    let onRemove: (AppItem) -> Void
    let onRename: (String) -> Void
    let onClose: () -> Void

    @State private var nameDraft: String
    @FocusState private var nameFocused: Bool

    init(
        folder: DisplayFolder,
        iconSize: CGFloat,
        onLaunch: @escaping (AppItem) -> Void,
        onReveal: @escaping (AppItem) -> Void,
        onRemove: @escaping (AppItem) -> Void,
        onRename: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.folder = folder
        self.iconSize = iconSize
        self.onLaunch = onLaunch
        self.onReveal = onReveal
        self.onRemove = onRemove
        self.onRename = onRename
        self.onClose = onClose
        _nameDraft = State(initialValue: folder.name)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                TextField("Folder name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .focused($nameFocused)
                    .onSubmit { commitRename() }
                    .frame(maxWidth: 320)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: iconSize + 32), spacing: 20)],
                spacing: 24
            ) {
                ForEach(folder.items) { item in
                    AppTile(item: item, iconSize: iconSize, context: .folder) { action in
                        switch action {
                        case .launch: onLaunch(item)
                        case .reveal: onReveal(item)
                        case .removeFromFolder: onRemove(item)
                        case .rename, .hide: break
                        }
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 760)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
        )
        .onChange(of: folder.name) { _, newValue in
            // Reflect external renames if the folder is re-opened, etc.
            nameDraft = newValue
        }
    }

    private func commitRename() {
        nameFocused = false
        if nameDraft != folder.name { onRename(nameDraft) }
    }
}

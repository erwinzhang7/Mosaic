import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The standard macOS Settings window for Mosaic. Backs onto the shared
/// `Preferences` (scalar prefs) and shared `LayoutStore` (structured layout
/// overrides + custom source folders).
struct SettingsView: View {
    enum Tab: String, Hashable {
        case appearance, sources, hidden, renames
    }

    @State private var selection: Tab = .appearance

    var body: some View {
        TabView(selection: $selection) {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(Tab.appearance)

            SourcesSettings()
                .tabItem { Label("Sources", systemImage: "folder") }
                .tag(Tab.sources)

            HiddenSettings()
                .tabItem { Label("Hidden", systemImage: "eye.slash") }
                .tag(Tab.hidden)

            RenameSettings()
                .tabItem { Label("Renames", systemImage: "pencil") }
                .tag(Tab.renames)
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Icon size") {
                    VStack(alignment: .leading) {
                        Slider(value: $prefs.iconSize, in: 48...144, step: 4)
                        Text("\(Int(prefs.iconSize)) pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Minimum tile width") {
                    VStack(alignment: .leading) {
                        Slider(value: $prefs.columnMinWidth, in: 80...200, step: 4)
                        Text("\(Int(prefs.columnMinWidth)) pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Vertical scroll (single page)", isOn: $prefs.verticalScroll)
                    .disabled(true)
                Text("Horizontal-paged layout is planned; only vertical scroll is supported today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Summon hotkey") {
                    Text("⌃⌥Space")
                        .font(.body.monospaced())
                }
                Text("A configurable hotkey picker is on the roadmap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Sources

private struct SourcesSettings: View {
    @Bindable private var layout = LayoutStore.shared
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mosaic always scans /Applications, /System/Applications, and ~/Applications. Add extra directories below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(layout.state.customSources, id: \.self) { path in
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .tag(path)
                }
            }
            .frame(minHeight: 180)

            HStack {
                Button("Add Folder…") { pickFolder() }
                Button("Remove") {
                    if let path = selection {
                        layout.removeCustomSource(path)
                        selection = nil
                    }
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Add Application Source"
        if panel.runModal() == .OK, let url = panel.url {
            layout.addCustomSource(url.path)
        }
    }
}

// MARK: Hidden

private struct HiddenSettings: View {
    @Bindable private var layout = LayoutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hidden apps don't appear in the grid. Unhide here to bring them back.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if layout.state.hidden.isEmpty {
                Text("Nothing hidden.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(layout.state.hidden.sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Unhide") { layout.unhide(bundleID) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 240)
            }
        }
    }
}

// MARK: Renames

private struct RenameSettings: View {
    @Bindable private var layout = LayoutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom names you've given to apps. Reset to use the app's own name.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if layout.state.renames.isEmpty {
                Text("No renames.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(layout.state.renames.keys.sorted(), id: \.self) { bundleID in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(layout.state.renames[bundleID] ?? "")
                                    .lineLimit(1)
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Reset") { layout.rename(bundleID, to: nil) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 240)
            }
        }
    }
}

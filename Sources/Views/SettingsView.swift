import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The standard macOS Settings window for Mosaic. Backs onto the shared
/// `Preferences` (scalar prefs) and shared `LayoutStore` (structured layout
/// overrides + custom source folders).
struct SettingsView: View {
    enum Tab: String, Hashable {
        case appearance, shortcut, triggers, sources, hidden, renames, uninstall
    }

    @State private var selection: Tab = .appearance

    var body: some View {
        TabView(selection: $selection) {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(Tab.appearance)

            ShortcutSettings()
                .tabItem { Label("Shortcut", systemImage: "command") }
                .tag(Tab.shortcut)

            TriggersSettings()
                .tabItem { Label("Triggers", systemImage: "rectangle.inset.filled.and.cursorarrow") }
                .tag(Tab.triggers)

            SourcesSettings()
                .tabItem { Label("Sources", systemImage: "folder") }
                .tag(Tab.sources)

            HiddenSettings()
                .tabItem { Label("Hidden", systemImage: "eye.slash") }
                .tag(Tab.hidden)

            RenameSettings()
                .tabItem { Label("Renames", systemImage: "pencil") }
                .tag(Tab.renames)

            UninstallSettings()
                .tabItem { Label("Uninstall", systemImage: "trash") }
                .tag(Tab.uninstall)
        }
        .padding(20)
        .frame(width: 580, height: 480)
    }
}

// MARK: Uninstall

private struct UninstallSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Destructive — opt in deliberately", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Uninstall moves the app bundle plus standard `~/Library` support files (matched strictly by bundle ID) to the Trash. Nothing is permanently deleted by Mosaic — items remain restorable until you empty Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Master toggle") {
                Toggle("Show \"Uninstall…\" in the app context menu", isOn: $prefs.uninstallEnabled)
                Text("When off, the destructive menu item doesn't appear at all. Default is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                Toggle("Simulation mode (don't actually trash, just log)", isOn: $prefs.uninstallSimulate)
                Text("When on, the full preview + confirmation flow runs but the final \"Move to Trash\" call becomes a no-op that writes the would-trash list to the system log. Use this to exercise the feature against real bundles without anything moving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What's matched") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mosaic only includes files in these standard per-app locations, matched on the app's bundle ID. Names are never fuzzy-matched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("• ~/Library/Application Support/<bundleID>\n• ~/Library/Caches/<bundleID>\n• ~/Library/Preferences/<bundleID>.plist\n• ~/Library/Containers/<bundleID>\n• ~/Library/Group Containers/<bundleID>\n• ~/Library/Saved Application State/<bundleID>.savedState\n• ~/Library/Logs/<bundleID>\n• ~/Library/HTTPStorages/<bundleID>\n• ~/Library/WebKit/<bundleID>\n• ~/Library/Cookies/<bundleID>.binarycookies")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Refused") {
                Text("Mosaic refuses to uninstall apps in /System, any bundle ID starting with com.apple., or anything outside /Applications and ~/Applications. Apps added via custom source folders aren't uninstallable from Mosaic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @Bindable private var prefs = Preferences.shared
    @Bindable private var loginItem = LoginItemController.shared

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Mosaic at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))

                switch loginItem.status {
                case .requiresApproval:
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                        Text("Needs your approval in System Settings ▸ General ▸ Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .notFound:
                    Text("System Services couldn't locate Mosaic. Try relaunching after running the app once from /Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }

                if let err = loginItem.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Menu bar") {
                Toggle("Show Mosaic in the menu bar", isOn: $prefs.showMenuBarIcon)
                Text("Off hides the menu-bar icon. Summon still works via your hotkey or by clicking Mosaic in the Dock. To re-enable if you change your mind, run\n`defaults write com.erwinzhang.mosaic showMenuBarIcon -bool true`\nand relaunch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section("Layout") {
                Toggle("Vertical scroll (single page)", isOn: $prefs.verticalScroll)
                Text(prefs.verticalScroll
                     ? "One long scrolling grid of all your apps."
                     : "Horizontal pages — swipe between pages of apps. While searching, the grid falls back to a single scrolling list regardless of this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: Shortcut

private struct ShortcutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick the global hotkey that summons Mosaic.")
                .font(.callout)
                .foregroundStyle(.secondary)

            LabeledContent("Summon hotkey") {
                HotKeyRecorder()
            }

            Text("Click the recorder, then press your desired combo. At least one of ⌘, ⌃, or ⌥ is required. ⌘Space and ⌘Tab are reserved by macOS. While recording, the Settings window swallows keystrokes — Esc cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: Triggers

private struct TriggersSettings: View {
    @Bindable private var prefs = Preferences.shared
    @Bindable private var permission = AccessibilityPermission.shared

    var body: some View {
        Form {
            if !permission.isTrusted {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Hot corner needs Accessibility permission.", systemImage: "exclamationmark.shield")
                            .font(.callout)
                        Text("Grant it once and Mosaic can poll the global cursor position. The hotkey, search, and launching work without it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Open System Settings") {
                                permission.openSystemSettings()
                            }
                            Button("Re-check") {
                                permission.refresh()
                            }
                        }
                    }
                }
            }

            Section("Hot corner") {
                Toggle("Summon when the cursor parks in a corner", isOn: $prefs.hotCornerEnabled)
                    .onChange(of: prefs.hotCornerEnabled) { _, new in
                        if new && !permission.isTrusted { permission.requestPrompt() }
                        TriggerController.shared.applyCurrentSettings()
                    }

                if prefs.hotCornerEnabled {
                    Picker("Corner", selection: $prefs.hotCorner) {
                        ForEach(HotCorner.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .onChange(of: prefs.hotCorner) { _, _ in TriggerController.shared.applyCurrentSettings() }

                    LabeledContent("Dwell") {
                        VStack(alignment: .leading) {
                            Slider(value: $prefs.hotCornerDwell, in: 0.05...1.0, step: 0.05)
                            Text("\(Int(prefs.hotCornerDwell * 1000)) ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: prefs.hotCornerDwell) { _, _ in TriggerController.shared.applyCurrentSettings() }

                    Text("Off by default to avoid stomping on macOS hot corners (Mission Control, Quick Note, etc.). If you've assigned the same corner there, both will fire.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Looking for the F4 / Search key and 4-finger pinch triggers? They were removed in this build. macOS 26 routes those gestures at the WindowServer layer before any public-API event tap can see them — implementing them reliably would require the private `MultitouchSupport` framework, which we deliberately don't ship. Use the hotkey, hot corner, or the menu-bar's \"Show Mosaic\" item instead.")
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
                    HStack(spacing: 6) {
                        Image(systemName: pathExists(path) ? "folder" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pathExists(path) ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.orange))
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !pathExists(path) {
                            Text("missing")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.orange.opacity(0.2))
                                )
                                .foregroundStyle(Color.orange)
                        }
                    }
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
                if layout.state.customSources.contains(where: { !pathExists($0) }) {
                    Button("Remove All Missing") {
                        for p in layout.state.customSources where !pathExists(p) {
                            layout.removeCustomSource(p)
                        }
                        if let sel = selection, !pathExists(sel) { selection = nil }
                    }
                }
                Spacer()
            }
        }
    }

    private func pathExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
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

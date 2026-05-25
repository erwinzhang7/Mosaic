import AppKit
import SwiftUI

@main
struct MosaicApp: App {
    // Manual delegate assignment instead of @NSApplicationDelegateAdaptor.
    // With only MenuBarExtra + Settings scenes (no WindowGroup), the adaptor
    // fails to attach the delegate on macOS 26 — applicationDidFinishLaunching
    // never fires, so the overlay/hotkey/triggers never get set up. Assigning
    // NSApp.delegate ourselves in App.init() (which runs before AppKit's
    // launch sequence) is reliable.
    private let appDelegate: AppDelegate
    @Bindable private var prefs = Preferences.shared

    @MainActor
    init() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        // Drive the launch sequence ourselves — SwiftUI's lifecycle with
        // MenuBarExtra + Settings on macOS 26 doesn't reliably fire
        // applicationDidFinishLaunching. setup() is idempotent.
        delegate.setup()
        self.appDelegate = delegate
    }

    var body: some Scene {
        MenuBarExtra("Mosaic", image: "MenuBarIcon", isInserted: $prefs.showMenuBarIcon) {
            Button("Show Mosaic") {
                appDelegate.toggleOverlay()
            }

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("Quit Mosaic") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .menuBarExtraStyle(.menu)

        Settings { SettingsView() }
    }
}

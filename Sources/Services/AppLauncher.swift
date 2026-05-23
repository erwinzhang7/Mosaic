import AppKit
import Foundation

@MainActor
enum AppLauncher {
    static func launch(_ item: AppItem) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: item.sourcePath, configuration: config) { _, error in
            if let error {
                NSLog("Mosaic: failed to launch \(item.bundleID): \(error.localizedDescription)")
            }
        }
    }
}

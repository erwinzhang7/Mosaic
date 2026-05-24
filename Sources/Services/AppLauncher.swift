import AppKit
import Foundation

extension Notification.Name {
    /// Posted when NSWorkspace.openApplication returns an error — typically
    /// the bundle was moved or deleted between the discovery scan and the
    /// user's click. `userInfo["name"]` carries the app's display name.
    static let mosaicAppLaunchFailed = Notification.Name("MosaicAppLaunchFailed")
}

@MainActor
enum AppLauncher {
    static func launch(_ item: AppItem) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let displayName = item.displayName
        let bundleID = item.bundleID
        NSWorkspace.shared.openApplication(at: item.sourcePath, configuration: config) { _, error in
            if let error {
                NSLog("Mosaic: failed to launch \(bundleID): \(error.localizedDescription)")
                // Hop to main so observers can be @MainActor without ceremony.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .mosaicAppLaunchFailed,
                        object: nil,
                        userInfo: ["name": displayName]
                    )
                }
            }
        }
    }
}

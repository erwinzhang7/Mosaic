import SwiftUI

/// Kept as a thin wrapper so the SwiftUI entry point and the AppDelegate-owned
/// `NSHostingView` instantiate the same top-level view tree.
struct RootView: View {
    var body: some View {
        GridView()
    }
}

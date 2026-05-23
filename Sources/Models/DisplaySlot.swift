import Foundation

/// What the grid actually renders: an `AppItem` resolved from discovery,
/// or a `DisplayFolder` resolving its contents. Computed from raw discovery
/// + `LayoutStore.state` on each reload.
enum DisplaySlot: Identifiable {
    case app(AppItem)
    case folder(DisplayFolder)

    var id: String {
        switch self {
        case .app(let item): return "app:\(item.bundleID)"
        case .folder(let folder): return "folder:\(folder.id.uuidString)"
        }
    }
}

struct DisplayFolder: Identifiable {
    let id: UUID
    var name: String
    var items: [AppItem]
}

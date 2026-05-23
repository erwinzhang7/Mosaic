# Architecture

A short tour of how Mosaic is put together, why, and where to look when you want to change something.

## Shape of the app

Mosaic is a single-binary macOS app written in Swift + SwiftUI. Once it ships in agent form (step 3 of the build order), it has no Dock icon and no main window in the conventional sense — it sits as a menu-bar item and a global hotkey, and renders a borderless full-screen overlay when summoned.

```
┌────────────────────────────────────────────────────────┐
│ MosaicApp (@main App)                                  │
│  └─ AppDelegate (NSApplicationDelegate)                │
│      ├─ owns the overlay window                        │
│      ├─ owns the menu-bar status item                  │
│      └─ owns the global hotkey registration            │
└────────────────────────────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────────────────┐
│ Overlay NSWindow                                       │
│  • borderless, .screenSaver level                      │
│  • full-screen, clear background                       │
│  • NSVisualEffectView (.hudWindow material)            │
│  • NSHostingView { GridView }                          │
└────────────────────────────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────────────────┐
│ SwiftUI view tree                                      │
│  GridView ── LazyVGrid of AppTile                      │
│   ├─ reads AppDiscovery results                        │
│   ├─ applies LayoutStore overrides (hidden, renamed,   │
│   │   folder structure, ordering)                      │
│   └─ applies live search filter                        │
└────────────────────────────────────────────────────────┘
```

Until step 3 lands, the same view tree is hosted in a regular window so you can run and test it without the hotkey infrastructure.

## Modules

```
Sources/
├── App/
│   ├── MosaicApp.swift         # @main entry, wires AppDelegate
│   └── AppDelegate.swift       # window, hotkey, status item ownership
├── Models/
│   ├── AppItem.swift           # bundleID, displayName, icon, sourcePath
│   └── LayoutStore.swift       # folders, order, hidden, rename overrides + JSON persistence
├── Services/
│   ├── AppDiscovery.swift      # NSWorkspace-based enumeration
│   └── AppLauncher.swift       # NSWorkspace.openApplication wrapper
├── Views/
│   ├── GridView.swift          # the main grid + search wiring
│   └── AppTile.swift           # one icon + label
└── Resources/                  # assets when needed
```

## Data flow

1. **Discovery** (`AppDiscovery`) walks the configured source roots — `/Applications`, `~/Applications`, `/System/Applications`, plus any user-added directories — using `NSWorkspace` to resolve bundle metadata and icons. Output is a sorted list of `AppItem`.
2. **Layout overrides** (`LayoutStore`) layer the user's customizations on top: hidden bundle IDs are filtered out, rename overrides replace `displayName`, the folder tree groups items, and a custom ordering wins over the alphabetical default.
3. **Render** (`GridView`) shows the resulting list as a `LazyVGrid` of `AppTile`s. Type-to-search applies a case-insensitive substring filter on top of the overrides.
4. **Launch** (`AppLauncher`) calls `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` and dismisses the overlay.

## Persistence

`LayoutStore` serializes to JSON at:

```
~/Library/Application Support/com.erwinzhang.mosaic/layout.json
```

That's the only persistent state. Deleting it returns Mosaic to defaults — alphabetical, no folders, no hidden apps, no renames.

## Permissions

Mosaic asks for system permissions lazily, only when the user opts into a feature that needs one:

| Feature | Permission | Notes |
|---|---|---|
| Discovery, launch, hotkey | none | Carbon `RegisterEventHotKey` is permission-free |
| Hot corners, trackpad pinch | Accessibility (TCC) | Feature stays disabled if denied |
| F4-key trigger | Accessibility (CGEventTap) | Opt-in; off by default; isolated module |
| Window browsing mode | Accessibility | Future phase |
| App uninstall | Full Disk Access | Dry-run preview before any deletion |

The hardened runtime is enabled. The app sandbox is **off** — a launcher fundamentally needs to enumerate and launch arbitrary apps, which the sandbox blocks.

## Concurrency

Swift strict concurrency is on. `AppDiscovery` runs off the main actor (filesystem scan + icon resolution can be slow on cold cache). Everything that touches AppKit lives on `@MainActor`. Models are `Sendable` value types.

## Build system

The Xcode project is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open Mosaic.xcodeproj
```

`Mosaic.xcodeproj` is gitignored — only `project.yml` is canonical. This keeps diffs clean and merges easy.

## Why these choices

- **AppKit window, SwiftUI content.** SwiftUI's `WindowGroup` can't produce a borderless `.screenSaver`-level overlay with the behavior we need. Owning the `NSWindow` directly from `AppDelegate` and embedding SwiftUI via `NSHostingView` is the standard escape hatch.
- **xcodegen over checked-in `.pbxproj`.** Project files are notorious for merge conflicts and noisy diffs. `project.yml` is human-readable and lossless for our needs.
- **JSON over `UserDefaults` for layout.** Layout is structured, may grow large, and is worth being able to inspect/back up as a file. `UserDefaults` is fine for scalar preferences if we add them later.
- **Carbon for the global hotkey.** It is the only API that registers a system-wide hotkey without requiring Accessibility permission. `CGEventTap` (used in step 9 for F4) does need it, which is exactly why F4 is opt-in.

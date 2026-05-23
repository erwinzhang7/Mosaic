# Mosaic

A free, open-source full-screen app launcher for macOS — a native alternative to Launchpad, built with Swift and SwiftUI for macOS 26 (Tahoe).

Summon a grid of all your apps with a global hotkey, search by typing, organize into folders, and launch. That's the core. Everything is local, native, and yours to modify.

## Why

Launchpad-style launchers are a commodity. This one is free, open, and hackable — built from scratch so you don't have to pay for the basics. Use it, fork it, change it.

## Features

Core
- [x] Full-screen grid of all installed apps with real icons
- [x] Click or press Enter to launch
- [x] Type-to-search live filtering
- [x] Global hotkey to summon/dismiss *(default ⌃⌥Space)*
- [x] Right-click menu: launch, reveal in Finder, rename, hide
- [x] Folders via drag-and-drop, with persisted layout
- [x] Glass background overlay native to Tahoe

Customization
- [x] Adjustable icon size and minimum tile width
- [ ] Vertical-scroll layout mode *(vertical only today; horizontal-paged planned)*
- [x] Custom per-app renaming
- [x] Hide apps you don't want to see *(unhide from Settings)*
- [x] Add custom source folders to scan

Advanced (require extra permissions)
- [ ] Launch from hot corners *(Accessibility)*
- [ ] Launch with trackpad pinch gesture *(Accessibility)*
- [ ] Launch with the F4 key *(Accessibility, opt-in)*
- [ ] Window browsing mode *(Accessibility — planned)*
- [ ] Fully uninstall apps, including leftover Library files *(planned, with dry-run preview)*

## Requirements

- macOS 26 (Tahoe)
- Xcode 16+
- Apple Silicon recommended

## Build

```bash
git clone <your-repo-url> mosaic
cd mosaic
open Mosaic.xcodeproj
```

Build and run from Xcode (⌘R).

## Permissions

Some features need macOS to grant access, and you'll be prompted the first time you enable them:

| Feature | Permission |
|---|---|
| Hot corners, gestures, F4 trigger | Accessibility |
| Window browsing | Accessibility |
| App uninstall | Full Disk Access |

If you decline, those features stay disabled and the rest of the app works normally.

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md). In short: a `LSUIElement` agent app that puts a borderless full-screen `NSWindow` over your desktop, lists apps via `NSWorkspace`, and persists your layout as JSON in Application Support.

## Status

Early and under active development. Expect rough edges. The build order in the source ships a runnable launcher first, with advanced features layered on after.

## Contributing

Issues and PRs welcome. Keep contributions original — no code, assets, or strings lifted from commercial launchers.

## License

MIT. See [`LICENSE`](LICENSE).

## Acknowledgements

An independent project. Not affiliated with, derived from, or endorsed by Apple or any commercial launcher. "Launchpad" is a trademark of Apple Inc.; Mosaic is an independent alternative and uses the term only to describe the category.
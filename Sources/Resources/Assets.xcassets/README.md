# Mosaic asset catalog

## AppIcon

`AppIcon.appiconset/` holds the macOS app-icon slots. All sizes are
rasterized from a single SVG source: `scripts/mosaic-icon-dark.svg`.

### Regenerate after editing the SVG

```bash
swift scripts/rasterize-icon.swift scripts/mosaic-icon-dark.svg \
  Sources/Resources/Assets.xcassets/AppIcon.appiconset
```

That writes `icon-16.png` through `icon-1024.png` into the appiconset,
which `Contents.json` already references — no further config needed.

### Slot mapping

```
icon-16.png    16×16   (1× for 16pt)
icon-32.png    32×32   (2× for 16pt, also 1× for 32pt)
icon-64.png    64×64   (2× for 32pt)
icon-128.png   128×128 (1× for 128pt)
icon-256.png   256×256 (2× for 128pt, 1× for 256pt)
icon-512.png   512×512 (2× for 256pt, 1× for 512pt)
icon-1024.png  1024×1024 (2× for 512pt)
```

`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in `project.yml` wires
this catalog as the bundle icon. Replacing the icon is a pure asset
operation: drop in a new SVG (same path) and re-run the rasterizer, or
hand-author PNGs at the filenames above.

### MenuBarIcon (the menu-bar status item glyph)

Custom template image set rasterized from
`scripts/mosaic-menubar-template.svg`. Black-on-transparent at 18pt 1× and
36pt 2×; the imageset's `Contents.json` marks it `template-rendering-intent`
so the system inverts it for light/dark menu bars automatically.

Regenerate after editing the SVG:

```bash
swift scripts/rasterize-icon.swift scripts/mosaic-menubar-template.svg \
  Sources/Resources/Assets.xcassets/MenuBarIcon.imageset \
  menubar 18 36
```

`Sources/App/AppDelegate.swift` (`installStatusItem`) loads it via
`NSImage(named: "MenuBarIcon")`. To swap back to an SF Symbol, replace the
two `NSImage(named:)` lines with
`NSImage(systemSymbolName: "<name>", accessibilityDescription: "Mosaic")`.

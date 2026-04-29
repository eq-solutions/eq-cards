# Launcher icon source files

This folder holds the **launcher icon source PNGs** that `flutter_launcher_icons` consumes.

## Required files

| File | Size | Format | Purpose |
|---|---|---|---|
| `launcher.png` | 1024 × 1024 | PNG, opaque, no rounded corners | Sky mark (#3DA8D8) on white background. Drives iOS, web, Windows, Android legacy. |
| `launcher_foreground.png` | 1024 × 1024 | PNG, transparent background | Same mark but in WHITE on transparent. Drives Android 8+ adaptive-icon foreground over the sky background. |

The OS adds rounding and platform shaping — don't pre-round the source.

## Design — EQ infinity-loop mark

The "EQ" mark drawn as an infinity loop where the lowercase letterforms — `e` on the left, `q` on the right — share the loop's two halves. Stroke weight roughly the icon-edge × 0.045. The `e` has a slash through its middle; the `q` has a perpendicular descender extending down-right.

| Layer | Background | Mark colour |
|---|---|---|
| `launcher.png` (iOS / web / Win / Android legacy) | `#FFFFFF` white | `#3DA8D8` EQ Sky |
| `launcher_foreground.png` (Android adaptive) | transparent | `#FFFFFF` white |
| Adaptive background (Android adaptive) | `#3DA8D8` EQ Sky (set in `flutter_launcher_icons.yaml`) | — |

So users see slightly different but cohesive treatments per platform:
- **iOS / web / Windows:** sky mark on white
- **Android adaptive launchers:** white mark on sky (with launcher-controlled shape + parallax)
- **Android legacy launchers:** sky mark on white (falls back to `launcher.png`)

The in-app `Settings → Design → Linear` preview ([`lib/core/design/app_icon_preview.dart`](../../lib/core/design/app_icon_preview.dart)) loads `launcher.png` directly via `Image.asset` so the picker matches what's installed on the user's device.

## Generating the PNGs

Three options:

### A) Render from the in-app preview widget (recommended)

The `AppIconPreview(version: DesignVersion.linear)` widget already encodes the design. A small dart export script can render it to PNG at any size:

```dart
// tools/export_launcher_icon.dart — write this when needed
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:eq_cards/core/design/app_icon_preview.dart';
// ... use RenderRepaintBoundary.toImage to dump 1024x1024 PNG ...
```

This keeps the source design and the rendered icon in sync — change the widget, re-run, both update.

### B) Use a Figma export

If the design lives in Figma (e.g. for marketing assets), export `launcher.png` and `launcher_foreground.png` from there at 1024×1024.

### C) Use an AI image-gen tool

Prompt with the brand spec: "1024x1024 app icon, solid sky-blue background #3DA8D8, white 'EQ' wordmark in Plus Jakarta Sans Bold, opaque, no rounding, opaque flat design, Linear/Notion aesthetic, no gradients no shadows."

## Wiring up

Once `launcher.png` and `launcher_foreground.png` are in this folder:

```bash
dart run flutter_launcher_icons
```

That writes:
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `web/icons/Icon-192.png`, `Icon-512.png` (+ maskable versions)
- `windows/runner/resources/app_icon.ico`

Commit those generated files (they're platform-required). Re-run when the source changes.

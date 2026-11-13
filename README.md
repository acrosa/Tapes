# Tapes

A four-track tape recorder for iPhone and iPad. One screen, no menus: turn the dial to move the tape.

Not on the App Store yet.

## What's here

| Folder | What it is |
| --- | --- |
| `Spule` | The app (SwiftUI, iOS 18 or later). The code still uses the project's earlier name, Spule. |
| `Packages/TapeEngine` | The tape itself: playhead, recording, loop, click, mixdown. Pure Swift, with tests. |
| `Packages/GridKit` | The layout grid and vertical rhythm the interface is built on. |
| `SpuleUITests` | End-to-end tests that drive the app through its controls. |
| `docs` | What the app does (`SPEC.md`), how it looks (`DESIGN.md`) and how it moves (`MOTION.md`). |
| `web` | The landing page. One static HTML file. |
| `screenshots` | iPhone and iPad in the three finishes. |

## Build

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Spule.xcodeproj
```

To run on a device, set your own development team in `project.yml` first.

```sh
(cd Packages/TapeEngine && swift test)
(cd Packages/GridKit && swift test)
```

## Credits

Set in [Geist](https://vercel.com/font) (SIL Open Font License, included in `Spule/Fonts`).

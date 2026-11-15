# Tapes

A four-track tape recorder for iPhone and iPad. One screen, built like a Braun appliance:
every function has one control, the control shows its own state, and the tape is moved by hand.

Read before changing anything visible or anything that moves:

- `docs/SPEC.md` — what the app does, control by control, and what is deliberately left out.
- `docs/DESIGN.md` — grid, type, colour, materials, components.
- `docs/MOTION.md` — animation, tape physics and haptics.

If a change contradicts one of these, change the document in the same commit.

## Commands

```sh
xcodegen generate                                   # after adding, moving or removing files
xcodebuild -project Tapes.xcodeproj -scheme Tapes \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build
(cd Packages/TapeEngine && swift test)              # tape transport and mix, no device needed
(cd Packages/GridKit && swift test)                 # grid arithmetic
xcodebuild -project Tapes.xcodeproj -scheme Tapes \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build test   # end-to-end UI tests (about 4 minutes)
```

`Tapes.xcodeproj` is generated from `project.yml`. Edit `project.yml`, never the project file.

Debug launch arguments: `-seedDemoTape` fills an empty tape with synthetic notes, cues and a loop;
`-autoplay` starts playback after loading; `-showsGrid YES` draws the layout grid;
`-resetTapes` empties the shelf first (the UI tests use it); `-showTapes` opens the tapes sheet;
`-tiltX` and `-tiltY` (0 to 1; a negative value is misread as a flag) fix the tilt that lights the glass;
`-routeProbe` (device only) prints how iOS routes sound under each strategy with whatever is plugged in;
`-autorecord` (simulator only) starts a take after loading, for store screenshots;
`-edit` opens the cutting controls with the demo tape cut in two places;
`-instrument` shows the headphones key as if an instrument and headphones were connected;
`-landscape` turns the window on its side (the way to check landscape in a simulator); `-portrait` turns it upright;
`-fold 0.55` stands in for iPhone Duo's fold at that fraction of the two-pane layout's longer side.

## Layout of the code

| Path | What lives there |
| --- | --- |
| `Packages/GridKit` | Local package. Baseline unit (`Rhythm`), column grid (`ColumnGrid`, `GridContainer`, `UnitRow`), row grid (`RowGrid`), rhythm-locked type (`TypeSpec`, `.rhythm()`), the on-grid check (`.gridChecked()`), debug `GridOverlay`. Its README is the layout contract. No third-party "GridKit" exists for this; this one is ours. |
| `Packages/TapeEngine` | Local package, pure Swift. `TapeCore`: the tape in memory, the playhead, render, record, loop, click, bounce. `Splice`: an edit as a list of pieces, and the sound it renders. |
| `Tapes/Audio/AudioIO.swift` | AVAudioEngine and AVAudioSession around `TapeCore`. |
| `Tapes/Model/Recorder.swift` | The one `@Observable` model. Every control action is a method here. |
| `Tapes/Model/Tape.swift` | `TapeMeta` and `TapeStore` (disk format). |
| `Tapes/Design/Theme.swift` | All tokens: `Palette`, `Typo`, `Motion`, `Haptics`. |
| `Tapes/Fonts` | Geist Mono (in use) and Geist, with the Open Font License. Registered at launch. |
| `Tapes/Views` | The faceplate and its parts. `EditView.swift` is the dark bed under the faceplate, where the tape is cut. |
| `web` | The landing page: one static `index.html` and its images. No build step. |
| `appstore` | Store listing text (`README.md`), the framed screenshots for both required sizes, the product page header and search artwork, and the scripts that compose them. |
| `.claude/skills/appstore-release` | A copy of the general `appstore-release` skill. Its source is `~/Desktop/projects/skills/appstore-release`; edit it there and run `sync.sh` beside it, which also updates `~/.claude/skills` and other projects: version, listing text, screenshots, artwork, archive, submission sheet. What is particular to this app is in `appstore/NOTES.md`. |
| `Shared` | Code compiled into both the app and the Live Activity extension: `RecordingAttributes` and `LiveTheme`. |
| `TapesLive` | The widget extension that draws the recording Live Activity (Lock Screen and Dynamic Island). |
| `TapesUITests` | End-to-end tests that drive the app through its controls on the seeded demo tape. A change to a control's behaviour needs its test changed or added here. |

## Rules

**Layout**
- Read `Packages/GridKit/README.md` first. Its contract is columns and rows together, from the first pass, verified, on every layout. That goes for the landing page in `web` as well.
- Every part that should be on the grid carries `.gridChecked()`. `testEveryPartSitsOnTheGrid` fails if one is off; a new layout or orientation gets added to that test.
- Every height, gap, padding and line height is a multiple of 4pt. Write `Rhythm.u(n)`, not a bare number.
- Horizontal positions come from the column grid: `grid.gutter`, `grid.span(n)`, `UnitRow`. No hand-tuned widths. A control is a whole number of columns wide and fills them; do not centre a narrower control in a column or split a span by eye.
- In landscape every part starts and ends on a row band (see `docs/DESIGN.md`). Parts in different panes share edges.
- Text on the faceplate uses `.faceType(.role)`. Do not call `.font()` on faceplate text.
- Sizes that differ between iPhone and iPad come from `Metrics` (in `Theme.swift`), read from the environment. Do not branch on the device in a view.
- Check all four layouts (iPhone upright and on its side, iPad upright and on its side) with the grid overlay on before calling layout work done.
- iPhone Duo is two more screens: closed (466 × 678, compact, `Metrics.short`) and open (669 × 951, the two-pane layout at phone sizes). A freshly booted Duo simulator is closed; `simctl io <device> screenshot --display=LCD` captures the outer display and `--display=LCD-1` the inner. Opening it or turning the inner display takes Device Hub (`Xcode.app/Contents/Applications/DeviceHub.app`); there is no command for it. Half open, the two panes stand either side of the fold, or break their rows at it when the device is upright (`Fold` in `FaceplateView.swift`); a layout change there must stay one view tree so the move animates.

**Design**
- There are three finishes (Light, Dark, Green). Text on a key or in a well uses `Palette.ink`/`inkSecondary`; text on the faceplate itself uses `Palette.label`/`legend`. Check a visual change in all three.
- Colours, type, springs and durations come from `Theme.swift`. No literals in views. A new value means a new token and a line in the docs.
- `Palette.signal` (orange) means recording or the playhead. `Palette.lamp` (green) means something is switched on. Nothing else is coloured.
- One control per function. Do not add modes that change what an existing control does. Cutting (the scissors) is a second surface under the faceplate, dark in every finish so it cannot be mistaken for it; it is the only one.
- State is shown on the control (lamp, position, fill) and confirmed in the display readout. No toasts or banners.

**Motion and haptics**
- Use the `Motion` tokens. Controls under a finger follow it directly, with no animation; springs are for release and for state changes.
- Tape movement is never animated by SwiftUI. It is the audio engine's playhead, read once per frame.
- Haptics go through `Haptics`, which honours the user's setting.

**Audio**
- `TapeCore.render` and `TapeCore.write` run on audio threads: no allocation, locks, Swift arrays, logging or Objective-C there.
- Closures given to AVAudioEngine are created in `AudioIO` (not main-actor isolated). Creating them in a `@MainActor` type crashes on the audio thread under Swift 6.
- New transport behaviour goes into `TapeCore` with a test in `TapeEngineTests`, then gets wired up in `Recorder`.

**Scope**
- Views do not touch `TapeCore` except to read `recorder.position` and track lengths for drawing.
- The app is called Tapes ("Vibe Tapes" on the App Store and under its icon; it began as Spule). Its bundle identifier is `co.alfajor.tapes`. It has its own design. It is inspired by Reel's feature set, not a copy of its interface: do not reproduce Reel's name, artwork or layout.

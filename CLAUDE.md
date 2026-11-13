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
xcodebuild -project Spule.xcodeproj -scheme Spule \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build
(cd Packages/TapeEngine && swift test)              # tape transport and mix, no device needed
(cd Packages/GridKit && swift test)                 # grid arithmetic
xcodebuild -project Spule.xcodeproj -scheme Spule \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build test   # end-to-end UI tests (about 4 minutes)
```

`Spule.xcodeproj` is generated from `project.yml`. Edit `project.yml`, never the project file.

Debug launch arguments: `-seedDemoTape` fills an empty tape with synthetic notes, cues and a loop;
`-autoplay` starts playback after loading; `-showsGrid YES` draws the layout grid;
`-resetTapes` empties the shelf first (the UI tests use it); `-showTapes` opens the tapes sheet;
`-landscape` turns the window on its side (the way to check landscape in a simulator).

## Layout of the code

| Path | What lives there |
| --- | --- |
| `Packages/GridKit` | Local package. Baseline unit (`Rhythm`), column grid (`ColumnGrid`, `GridContainer`, `UnitRow`), rhythm-locked type (`TypeSpec`, `.rhythm()`), debug `GridOverlay`. No third-party "GridKit" exists for this; this one is ours. |
| `Packages/TapeEngine` | Local package, pure Swift. `TapeCore`: the tape in memory, the playhead, render, record, loop, click, bounce. |
| `Spule/Audio/AudioIO.swift` | AVAudioEngine and AVAudioSession around `TapeCore`. |
| `Spule/Model/Recorder.swift` | The one `@Observable` model. Every control action is a method here. |
| `Spule/Model/Tape.swift` | `TapeMeta` and `TapeStore` (disk format). |
| `Spule/Design/Theme.swift` | All tokens: `Palette`, `Typo`, `Motion`, `Haptics`. |
| `Spule/Fonts` | Geist Mono (in use) and Geist, with the Open Font License. Registered at launch. |
| `Spule/Views` | The faceplate and its parts. |
| `web` | The landing page: one static `index.html` and its images. No build step. |
| `SpuleUITests` | End-to-end tests that drive the app through its controls on the seeded demo tape. A change to a control's behaviour needs its test changed or added here. |

## Rules

**Layout**
- Every height, gap, padding and line height is a multiple of 4pt. Write `Rhythm.u(n)`, not a bare number.
- Horizontal positions come from the column grid: `grid.gutter`, `grid.span(n)`, `UnitRow`. No hand-tuned widths. A control is a whole number of columns wide and fills them; do not centre a narrower control in a column or split a span by eye.
- In landscape every part starts and ends on a row band (see `docs/DESIGN.md`). Parts in different panes share edges.
- Text on the faceplate uses `.rhythm(Typo.x)`. Do not call `.font()` on faceplate text.
- Check all three layouts (compact, regular width, and compact-height landscape) with the grid overlay on before calling layout work done.

**Design**
- There are three finishes (Light, Dark, Green). Text on a key or in a well uses `Palette.ink`/`inkSecondary`; text on the faceplate itself uses `Palette.label`/`legend`. Check a visual change in all three.
- Colours, type, springs and durations come from `Theme.swift`. No literals in views. A new value means a new token and a line in the docs.
- `Palette.signal` (orange) means recording or the playhead. `Palette.lamp` (green) means something is switched on. Nothing else is coloured.
- One control per function. Do not add modes that change what an existing control does.
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
- The app is called Tapes (it was Spule; the Xcode target, folders, scheme and bundle identifier `app.spule.recorder` still carry the old name, and stay that way unless a rename is asked for). It has its own design. It is inspired by Reel's feature set, not a copy of its interface: do not reproduce Reel's name, artwork or layout.

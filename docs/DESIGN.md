# Tapes — design spec

Tokens live in `Tapes/Design/Theme.swift`; grid code in `Packages/GridKit`. This document is the
reasoning and the reference. If a number here and a number in code disagree, fix one of them.

## Principles

Taken from the Braun audio line (SK 4, T 1000, the wall units) and the Bauhaus before it.

1. **Function sets the form.** A part exists because it does something. No ornament, no skeuomorphic texture, no reel artwork.
2. **Order is visible.** Everything sits on one grid. Alignment does the work that boxes and dividers would otherwise do.
3. **Two signal colours, used sparingly.** A grey-white appliance with an orange signal and green pilot lamps.
4. **Honest materials.** Three depths only: raised, flush, sunken. Light comes from above.
5. **Legends are printed, small and lowercase.** The control is the message; the word is a caption.
6. **As little design as possible.** When in doubt, remove.

## Grid

### Baseline
- Unit: **4pt** (`Rhythm.unit`). Write sizes as `Rhythm.u(n)`.
- Every height, vertical gap, padding and line height is a multiple of the unit. Section gaps are 16pt.
- Sizes that depend on the screen are snapped: the dial's diameter is rounded down to 8pt.

### Columns
`ColumnGrid.adaptive(width:compactHeight:)`, applied by `GridContainer` at the root.

| Container | Columns | Margin | Gutter | Devices |
| --- | --- | --- | --- | --- |
| under 600 wide | 12 | 24 | 16 | iPhone upright, iPhone Duo closed, iPad in a narrow split |
| compact height | 24 | 16 | 16 | iPhone on its side, iPhone Duo closed and on its side |
| 600 to 899 wide | 24 | 32 | 16 | iPad portrait, iPhone Duo open (upright) |
| 900 and up | 24 | 40 | 16 | iPad landscape, iPhone Duo open (the way it opens) |

The columns are fine (about 15pt on iPhone, 17 to 30 on iPad) and controls are sized in whole columns:

- A **module** is 3 columns (`ColumnGrid.module`), about 76pt: a quarter of the upright screen. Track keys, wheels and transport keys are one module wide. Play is two modules upright.
- A function key (click, cue, loop) is 2 columns, about 45pt.
- Both phone grids use the same gutter, so a module is the same size upright and sideways.

Rows of controls are placed with `UnitRow(units:spacing:)`, which gives each child a whole number of
columns. The control row is `[3, 3, 2, 2, 2]`: twelve columns, so every control starts and ends on a
column edge. No control is centred in a space wider than itself, and no group is divided by eye.

Insets inside a part (display, tape scale, track key) are 16pt.

Sections are 16pt apart (24 on iPad). A section of keys (the control row, the track keys, the transport) gets 8pt more above it (`Metrics.sectionLead`), so the readouts, the dial and each group of keys read as separate groups. Header words sit flush with the margins.

### Layouts
**Compact** (one column of sections, top to bottom). The stack's height is snapped down to 8pt and
hangs from the top, so every edge is on the baseline grid, the dial's included.

| Section | Height | Columns |
| --- | --- | --- |
| Header | 32 | a gear flush left (tapes and settings), scissors two columns along (they lift the faceplate for cutting), "export" flush right |
| Display | 112 | 12 |
| Tape scale | 56 | 12 |
| Control row | 72 | speed 3, tempo 3, click 2, cue 2, loop 2 |
| Dial | all remaining height | centred, diameter snapped to 8 |
| Track keys | 72 | 3 each |
| Transport | 64 | return 3, record 3, play 6 |

On a short screen (under 700pt of height: iPhone Duo closed, at 466 × 678, and the smallest
iPhones) the faceplate is built `Metrics.short`: sections 12 apart with 4 of lead, the display 96,
the transport 56. The dial gets the 60pt they give back; without it the dial is too small to turn.

A legend never widens its key. On the narrowest columns (Duo closed and on its side, where a key
of two columns is 32pt) the word hangs evenly into the gutters either side.

**Regular** (iPad, and iPhone Duo open). The faceplate is built larger here (`Metrics.large`, below): on a big screen
the phone's sizes look lost. Two panes, top-aligned, height snapped to 8pt, status bar hidden
(it would print the app's name at the top left). The split follows the screen's shape so neither
pane is left empty. iPhone Duo's inner display (669 × 951) is regular both ways too, but it is two
phones wide, not a tablet: it gets the two panes and the mixer at the phone's sizes
(`Metrics.large` starts at a shorter side of 720pt), and keeps its status bar, which the system
puts down the side.

Each pane is a grid of its own, cut from the faceplate's columns (`GridContainer(grid:)`), so its
parts are checked against the pane they sit in. While iPhone Duo is half open, the system reports
the fold as a band to keep clear (`reservedRegions(kind: .division)`, 40pt wide at the middle of
the display). The panes then move apart to stand either side of it, twelve columns each, and
nothing is drawn across the fold; the left pane is the wider one, because the status bar takes a
strip from the right. Opened flat, the band is inactive and the panes close up to one gutter. The
move is sprung (`Motion.fold`). Half open and turned upright, the fold runs across the screen instead. The panes stay where they
are and their rows break at it: header, display, tape scale, wheels and keys above; the dial and
transport below, the dial smaller. In each mixer strip the select key and pan wheel stay above
and the fader, mute and solo start below. Both edges of the break are on the baseline grid.
`-fold 0.55` (debug builds) stands in for a fold at that fraction of the longer side.

| | Left pane | Right pane |
| --- | --- | --- |
| Upright | 16 columns: header, display, scale, control row (speed 5, tempo 5, three keys of 2), dial, transport | 8 columns: the mixer, four strips of 2 |
| On its side | 12 columns: header, display, scale, dial, transport | 12 columns: control row (3, 3, 2, 2, 2) over the mixer, four strips of 3 |

A channel strip, top to bottom: select key, pan wheel, fader, mute, solo. Mute and solo are stacked
so each is a full strip wide (two side by side would be under 44pt). The fader is never longer than
480pt; where the strip is taller, the extra height opens the gaps between its parts evenly.

**Sizes** (`Metrics` in `Theme.swift`; every value a multiple of 4):

| | iPhone | iPad |
| --- | --- | --- |
| Gap between sections | 16 | 24 |
| Header | 32 | 40 |
| Display (inset) | 112 (16) | 152 (24) |
| Tape scale | 56 | 72 |
| Key face, wheel | 48 | 56 |
| Transport | 64 | 88 |
| Fader cap, groove | — | 48×32, 12 |

**Landscape** (compact height, an iPhone on its side). Four row **bands** of equal height, 16pt apart,
are shared by every pane, so parts in different panes have the same top and bottom edges. A band is
a quarter of the usable height snapped down to 8pt (72 on most phones, never under 64).

| Band | Left, 4 modules | Middle, 3 modules | Right, 1 module |
| --- | --- | --- | --- |
| 1 | header (32), then the display | dial | track 1 |
| 2 | display, to the band's bottom edge | dial | track 2 |
| 3 | tape scale, one band tall | dial, to the band's bottom edge | track 3 |
| 4 | control row: wheels and key faces are the band less 24, legends beneath | return, record, play, one module each | track 4 |

The block is centred on the screen's full height, home indicator included, so the space above and below it looks equal. Bands are snapped to 4pt. Compact height is tested before regular width, so the largest
iPhones use this layout on their side, not the two-pane one.

### Debug overlay and checks
Tapes sheet → Show layout grid (or launch with `-showsGrid YES`). Column bands plus a rule every 4pt.
Layout work is checked against it on all three layouts. With the overlay on, any part marked
`.gridChecked()` that is off a column edge or off the baseline is outlined in red, and the UI test
`testEveryPartSitsOnTheGrid` fails. The landscape bands are a `RowGrid`.

## Type

Geist Mono (Vercel) throughout: every character the same width, like the print on a meter or a
typewritten label. Figures never shift as they change. Light, Regular and Medium are bundled in
`Tapes/Fonts` with their SIL Open Font License and registered at launch by `Typo.registerFonts()`.
(The proportional Geist files are still in the folder from before the switch and are not used.)

| Role | Face | iPhone size / line | iPad size / line | Use |
| --- | --- | --- | --- | --- |
| `counter` | Light | 48 / 56 | 64 / 72 | tape counter |
| `counterSmall` | Light | 40 / 56 | 56 / 72 | tape counter where the display is too narrow for the full size |
| `numeral` | Medium | 17 / 24 | 22 / 28 | track numbers |
| `status` | Medium | 12 / 16 | 15 / 20 | display state, uppercase |
| `caption` | Regular | 12 / 16 | 15 / 20 | display second line, "export" |
| `legend` | Regular | 12 / 16 | 13 / 20 | faceplate legends, lowercase |
| scale | Regular | 10 | 12 | scale numerals (Canvas) |

The counter is never cut short. Where the display window is narrow, the level meter drops from 16
perforations to 12, then to 8 with `counterSmall` (iPhone Duo closed and on its side). A status
word too long for what is left shrinks to no less than three quarters of its size.

Text is set with `.faceType(role)`, which picks the size from the faceplate's `Metrics`.

`.faceType` uses GridKit's `.rhythm(spec)`, which sets the font and fixes the line box to the spec's line height, so text keeps the
baseline grid regardless of font metrics. Faceplate text is single-line and fixed-size, like print
on a device. The tapes sheet uses system text styles and follows Dynamic Type.

## Colour

Three finishes (`Theme` in `Theme.swift`). The user picks one in the tapes sheet, where each is shown
as a small tile of the appliance in that finish; until they pick, the app is Light or Dark with the system.
Green is after Braun's grey-green portables: a green body, putty keys and scale, light print on the
body and dark print on the keys.

| Token | Light | Dark | Green | Use |
| --- | --- | --- | --- | --- |
| `surface` | `#ECEAE4` | `#1C1C1B` | `#5E6B64` | faceplate |
| `key` | `#F7F6F2` | `#2B2B29` | `#DCDCCB` | raised parts |
| `recess` | `#DDDAD2` | `#121211` | `#C2C4B2` | sunken parts, unlit lamps |
| `glass` | `#171716` | `#0B0B0A` | `#1B211E` | display window |
| `ink` | `#1A1A19` | `#E9E7E1` | `#1E211E` | marks on raised and sunken parts |
| `inkSecondary` | `#6B6963` | `#918F89` | `#4E5149` | ticks and small print on raised and sunken parts |
| `label` | `#1A1A19` | `#E9E7E1` | `#F1EFE4` | pressable words printed on the faceplate |
| `legend` | `#6B6963` | `#918F89` | `#F1EFE4` | legends printed on the faceplate |
| `displayInk` | `#F2F0EA` | `#ECEAE4` | `#ECEAE0` | display text |
| `displayDim` | `#85837D` | `#7C7A74` | `#8B9089` | inactive display text |
| `signal` | `#E8451E` | `#F05A30` | `#F0621F` | see below |
| `lamp` | `#14D94F` | `#3DFF7A` | `#1FE05A` | see below |
| `hairline` | ink 12 % | white 12 % | ink 16 % | edges |
| `lift` / `sheen` | 0.22 / 0.9 | 0.5 / 0.1 | 0.35 / 0.6 | shadow under, and highlight along the top of, a raised part |

Print on a key or in a well uses `ink` and `inkSecondary`; print on the faceplate itself uses `label`
and `legend`. They are the same colours in Light and Dark and opposite ones in Green, so choose by
what the text sits on. Whites are warm, never pure. Blacks are warm, never pure.

Views read `Palette.x`, which returns the current finish's colour. `FaceplateView` sets the finish
and rebuilds the faceplate when it changes.

**Orange (`signal`) means the tape is being written or read:** recording (record key and its lamp,
REC status, the recording track's lane, meter and lamp) and the playhead (scale needle, dial index mark).
Hot meter dots are the one extension.

**Fluorescent green (`lamp`) means something is switched on:** click, loop, mute, solo, the selected
track, the open tape in the tapes sheet, and the loop's band on the tape scale.

Neither colour is ever decoration.

## Materials

| Depth | Fill | Edge | Shadow |
| --- | --- | --- | --- |
| Raised (`KeyFace`) | `key` | 0.5pt hairline, 1pt top highlight fading to nothing at the middle | y 2, blur 2.5, black at the finish's `lift` |
| Flush | `surface` | none | none |
| Sunken | `recess` | none | none |
| Glass | `glass` | 0.5pt hairline | none |

Corner radii: display 12, tape scale 8, keys 8, fader caps 4, wheel slots 8 and rollers 4, dial round. Continuous corners.
No gradients other than the key highlight and the reflection on the display glass (see `MOTION.md`, Tilt). No blur, no translucency.

## Components

- **Key** (`KeyStyle`): raised face, legend printed beneath, optional lamp on the face. Minimum touch height 48.
- **Lamp**: 8pt dot. Off is `recess`; on is `lamp` green (orange on anything that is recording) with a soft glow of its own colour.
- **Live Activity** (`TapesLive`): the display window in miniature. Glass background, record lamp and "REC n" in orange, the tape's name in dim print, the counter in Geist Mono Light (40pt on the Lock Screen). In the Dynamic Island: the lamp alone when minimal, lamp and counter when compact. Its colours are in `LiveTheme`, shared with the app.
- **App icon**: the dial seen from above on the faceplate colour, with its orange index mark. Light and dark versions in `Tapes/Assets.xcassets`.
- **Wheel**: a thumbwheel. A sunken slot as wide as its module and as tall as a key face (48) holds a raised roller with ridges every 4pt. A 16pt gutter beside the roller carries an ink mark for the value and a thin line for the rest position, if there is one. It is rolled along its axis: up and down for speed and tempo, sideways for pan. It holds at detents (see `MOTION.md`). There are no rotary knobs: a control's shape must show the gesture that works it, and a finger cannot twist a small circle on glass.
- **Dial**: sunken well, 8pt rim, raised platter with 60 ticks (every fifth longer), one groove, an orange index mark, and a flush spindle that does not turn.
- **Track key**: number top left, lamp bottom left, an 8pt level slot on the right, all inset 16 (grey fill is fader position, dark fill is live level).
- **Fader**: 12pt groove that doubles as the meter, 48×32 cap with a centre line, a line across the strip at 100 % that the cap's line meets.
- **Display**: glass window. Words in uppercase `status`; one line of settings beneath.
- **Tape scale**: sunken strip drawn in Canvas.
- **Cutting bed** (`EditView`): `glass` from edge to edge in every finish, with the display's inks. One layout for every screen: a header (two words in `displayInk`, the counter in `status` between them), the timeline filling the height, and four keys of transport height in two pairs.
- **Timeline** (`TimelineLanes`): four lanes 8pt apart, each a rounded bed of `displayInk` at 6 % (3 % when not being cut) with its number at the top left. A piece is a rounded block of `displayInk` at 12 %, its outline of sound at 75 %, a hair of glass between pieces that touch. The picked-up piece is at 26 % with a 1pt `displayInk` outline and full-strength sound. A track not being cut shows its sound at 30 %. Second ticks along the bottom in `displayDim`, longer every five. The playhead is a 1.5pt `signal` line. No new colours.
- **Cutting and the fold** (iPhone Duo half open): with the fold down the screen, the keys part around it, a pair each side, and the playhead stands in the middle of the left side; the timeline runs across. With the fold across the screen, two lanes sit above it and two below.

## Accessibility

- Every control has a spoken label and value. Wheels, faders, track keys, the scale and the dial are adjustable with VoiceOver swipes.
- State is never carried by colour alone: lamps pair with position, words in the display, or a legend ("mute", "solo").
- Touch targets are at least 44pt, except mute and solo keys on the narrowest iPad strips (48pt tall, about 33pt wide), the strips on iPhone Duo open and upright (about 36pt wide), and the click, cue and loop keys on iPhone Duo closed and on its side (32pt wide, a band tall).
- Known gap: faceplate text does not scale with Dynamic Type. Large Content Viewer support is the planned answer.
- Contrast (WCAG ratio, computed): `legend` on `surface` 4.56 in Light and 5.27 in Dark; `displayDim` on `glass` 4.73 and 4.59; `ink` on `surface` 14.5 in Light. Green's `legend` on `surface` is about 4.8 by the same formula; its other pairs have not been computed.

# Tapes — design spec

Tokens live in `Spule/Design/Theme.swift`; grid code in `Packages/GridKit`. This document is the
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
| under 600 wide | 12 | 24 | 16 | iPhone upright, iPad in a narrow split |
| compact height | 24 | 16 | 16 | iPhone on its side |
| 600 to 899 wide | 24 | 32 | 16 | iPad portrait |
| 900 and up | 24 | 40 | 16 | iPad landscape |

The columns are fine (about 15pt on iPhone, 17 to 30 on iPad) and controls are sized in whole columns:

- A **module** is 3 columns (`ColumnGrid.module`), about 76pt: a quarter of the upright screen. Track keys, wheels and transport keys are one module wide. Play is two modules upright.
- A function key (click, cue, loop) is 2 columns, about 45pt.
- Both phone grids use the same gutter, so a module is the same size upright and sideways.

Rows of controls are placed with `UnitRow(units:spacing:)`, which gives each child a whole number of
columns. The control row is `[3, 3, 2, 2, 2]`: twelve columns, so every control starts and ends on a
column edge. No control is centred in a space wider than itself, and no group is divided by eye.

Insets inside a part (display, tape scale, track key) are 16pt. Header words sit flush with the margins.

### Layouts
**Compact** (one column of sections, top to bottom). The stack's height is snapped down to 8pt and
hangs from the top, so every edge is on the baseline grid, the dial's included.

| Section | Height | Columns |
| --- | --- | --- |
| Header | 32 | a gear flush left (tapes and settings), "export" flush right |
| Display | 104 | 12 |
| Tape scale | 56 | 12 |
| Control row | 72 | speed 3, tempo 3, click 2, cue 2, loop 2 |
| Dial | all remaining height | centred, diameter snapped to 8 |
| Track keys | 72 | 3 each |
| Transport | 64 | return 3, record 3, play 6 |

**Regular** (two panes of 12 columns each, top-aligned, height snapped to 8pt): the left pane holds header, display,
scale, dial and transport. The right pane holds the control row and four channel strips that run the
full height. The control row divides the pane into the same twelve parts, so speed sits over strip 1,
tempo over strip 2, and the three keys over strips 3 and 4. The status bar is hidden in this layout: on iPad it prints the app's name at the top left, and the faceplate carries no title.

**Landscape** (compact height, an iPhone on its side). Four row **bands** of equal height, 16pt apart,
are shared by every pane, so parts in different panes have the same top and bottom edges. A band is
a quarter of the usable height snapped down to 8pt (72 on most phones, never under 64).

| Band | Left, 4 modules | Middle, 3 modules | Right, 1 module |
| --- | --- | --- | --- |
| 1 | header (32), then the display | dial | track 1 |
| 2 | display, to the band's bottom edge | dial | track 2 |
| 3 | tape scale, one band tall | dial, to the band's bottom edge | track 3 |
| 4 | control row: wheels and key faces are the band less 24, legends beneath | return, record, play, one module each | track 4 |

The block hangs 16pt from the top. Compact height is tested before regular width, so the largest
iPhones use this layout on their side, not the two-pane one.

### Debug overlay and checks
Tapes sheet → Show layout grid (or launch with `-showsGrid YES`). Column bands plus a rule every 4pt.
Layout work is checked against it on all three layouts. With the overlay on, any part marked
`.gridChecked()` that is off a column edge or off the baseline is outlined in red, and the UI test
`testEveryPartSitsOnTheGrid` fails. The landscape bands are a `RowGrid`.

## Type

Geist Mono (Vercel) throughout: every character the same width, like the print on a meter or a
typewritten label. Figures never shift as they change. Light, Regular and Medium are bundled in
`Spule/Fonts` with their SIL Open Font License and registered at launch by `Typo.registerFonts()`.
(The proportional Geist files are still in the folder from before the switch and are not used.)

| Token | Face | Size / line | Tracking | Use |
| --- | --- | --- | --- | --- |
| `counter` | Light | 40 / 48 | −2 | tape counter |
| `numeral` | Medium | 17 / 24 | 0 | track numbers |
| `status` | Medium | 12 / 16 | +0.2 | display state, uppercase |
| `caption` | Regular | 12 / 16 | −0.2 | display second line, header keys |
| `legend` | Regular | 11 / 16 | −0.2 | faceplate legends, lowercase |
| `scale` | Regular | 9 | — | scale numerals (Canvas) |

`.rhythm(spec)` sets the font and fixes the line box to the spec's line height, so text keeps the
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
- **App icon**: the dial seen from above on the faceplate colour, with its orange index mark. Light and dark versions in `Spule/Assets.xcassets`.
- **Wheel**: a thumbwheel. A sunken slot as wide as its module and as tall as a key face (48) holds a raised roller with ridges every 4pt. A 16pt gutter beside the roller carries an ink mark for the value and a thin line for the rest position, if there is one. It is rolled along its axis: up and down for speed and tempo, sideways for pan. It holds at detents (see `MOTION.md`). There are no rotary knobs: a control's shape must show the gesture that works it, and a finger cannot twist a small circle on glass.
- **Dial**: sunken well, 8pt rim, raised platter with 60 ticks (every fifth longer), one groove, an orange index mark, and a flush spindle that does not turn.
- **Track key**: number top left, lamp bottom left, level slot on the right, all inset 16 (grey fill is fader position, dark fill is live level).
- **Fader**: 8pt groove that doubles as the meter, 40×24 cap with a centre line, a tick at 100 %.
- **Display**: glass window. Words in uppercase `status`; one line of settings beneath.
- **Tape scale**: sunken strip drawn in Canvas.

## Accessibility

- Every control has a spoken label and value. Wheels, faders, track keys, the scale and the dial are adjustable with VoiceOver swipes.
- State is never carried by colour alone: lamps pair with position, words in the display, or a legend ("mute", "solo").
- Touch targets are at least 44pt, except mute and solo keys on the narrowest iPad strips (48pt tall, about 33pt wide).
- Known gap: faceplate text does not scale with Dynamic Type. Large Content Viewer support is the planned answer.
- Contrast (WCAG ratio, computed): `legend` on `surface` 4.56 in Light and 5.27 in Dark; `displayDim` on `glass` 4.73 and 4.59; `ink` on `surface` 14.5 in Light. Green's `legend` on `surface` is about 4.8 by the same formula; its other pairs have not been computed.

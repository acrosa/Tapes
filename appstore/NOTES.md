# Release notes for the appstore-release skill

What is particular to this app. The skill reads this first.

## Facts

| | |
| --- | --- |
| Store name | Vibe Tapes (the app calls itself Tapes) |
| Store page | <https://apps.apple.com/us/app/vibe-tapes/id6834562677> (Apple ID 6834562677) |
| Bundle ID | `co.alfajor.tapes`; the Live Activity extension is `co.alfajor.tapes.live` |
| Team | Alfajor LLC, `49MWCX22SN`, automatic signing |
| Version numbers | `project.yml`: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in **both** the `Tapes` and `TapesLive` targets. Then `xcodegen generate`. |
| Project, scheme | `Tapes.xcodeproj` (generated), scheme `Tapes` |
| Archive | `build/Tapes.xcarchive` |
| Site | `web/` in this repository, deployed at `https://tapes-web.vercel.app`. Privacy: `/privacy.html`. Support: `/support.html`. |
| Privacy | Collects nothing, never uses the network. `Tapes/PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1). |
| Category, rating | Music, 4+ |
| Tests | Commands are in `CLAUDE.md`. |
| Upload | An App Store Connect API key is on the user's Mac in `~/.appstoreconnect/private_keys` (added 14 November 2026). Its Key ID and Issuer ID are not written here; they are in Claude's memory for this project, or ask. Ask before each upload and each submission. The key signs and uploads builds (`xcodebuild -exportArchive` with the key flags) and edits the listing; an earlier key without the Admin role failed with "Cloud signing permission error". |

## Screenshots

`appstore/screenshots/capture.sh` does all of it: iPhone 18 Pro (1206 × 2622, the "iPhone with Dynamic Island (medium display)" slot) and iPad Pro 13-inch (M5),
microphone granted, demo tape seeded.

- `-resetTapes` empties the shelf and `-autorecord` writes onto the tape. **Never pass either to
  a physical device.** `-autorecord` exists only in simulator builds.
- States: light finish playing, dark finish recording, green finish playing, and the three
  finishes together. `-theme light|dark|green` picks the finish; `-landscape` turns the window.
- Captions: "Four tracks. / One tape.", "Plug in a synth. / Press record.",
  "Move the tape / by hand.", "Light, dark / or green., "Cut a take. / Move the pieces." (the cutting
  timeline, launched with `-edit`). Caption font: `Tapes/Fonts/Geist-Medium.otf`.
- iPhone Duo: the `iphone-duo` set is 2853 × 2007: the open device for the first three (inner
  display, `--display=LCD-1`) and the three closed devices for the fourth (outer display,
  `--display=LCD`). The script restarts the Duo simulator first, because a fresh boot is the only
  sure way to have it closed, takes the closed shots, then waits for someone to open it in Device
  Hub. It must be opened flat, not half open: half open, the panes stand apart around the fold.
  No store capture ever shows the layout grid (the user asked, 14 November 2026). On this machine the
  Duo simulator on iOS 27.2 fails to boot ("Invalid argument"); the one on iOS 27.1 works.
- `compose.swift` beside the script is this project's copy of the framing script.
- The Live Activity on the Lock Screen cannot be captured in the simulator; ask for one from
  the phone.

## Artwork

- Chosen on 13 November 2026: a generated macro photograph of the reel (matte off-white disc,
  engraved ticks, one orange dot, the black display out of focus behind). Originals in
  `appstore/artwork/generated` (`v3.png` is the one picked from six).
- Describe the design to Codex as: a Braun appliance of the Dieter Rams era; a large turning
  reel dial with an orange dot, a black glass display with a white monospaced counter, a tape
  scale, ridged thumbwheels, four faders, square keys with tiny lamps; warm off-white (or dark,
  or sage green), one orange accent, one small green lamp.
- Codex tends to draw spoked tape reels and extra keys. The app has one plain dial. Say so.
- `appstore/artwork/from-app/compose.swift` builds all three sizes from one iPad capture of the
  real interface, if generated art is not wanted.

## How the listing reads

- Short, plain, no marketing voice. Use cases first: jam with a synth or drum machine over
  USB-C, catch an idea, build a song in layers, practise a section with the loop.
- No hardware brand names. Do not mention the app that inspired the feature set.
- The app should feel minimal and physical; the listing and images should too.

## Corrections

- 13 November 2026: App Store Connect rejected 1320 × 2868 iPhone screenshots ("File dimensions
  are invalid"). The iPhone slot is now "iPhone with Dynamic Island (medium display)" and takes
  only 1206 × 2622 or 1179 × 2556 (and their landscape forms). The 6.9" size is no longer a slot.

## Pending

- 15 November 2026: build 2 of 1.2 adds hearing a plugged-in instrument through the device; attach
  build 2, not build 1.
- 14 November 2026: version 1.2 (cutting) is built and uploaded (1.2, build 1) but not yet a
  version on App Store Connect: a new version cannot be created while 1.1 is waiting for review.
  When 1.1 is out: create 1.2, set What's New (`appstore/whats-new-1.2.txt`) and the description
  (`appstore/description.txt`), add `05-cut.png` to the three screenshot sets, attach the build.
  The user said not to submit it for review yet. Remove this note when done.

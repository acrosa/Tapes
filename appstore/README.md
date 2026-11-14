# App Store submission: Vibe Tapes 1.1

Everything to paste into App Store Connect, in the order the site asks for it.
Character counts were checked against Apple's limits.

## Before you start

1. **Push the repo** so the privacy and support pages go live on the site (`web/privacy.html`, `web/support.html`). App Store Connect rejects a privacy URL that does not load.
2. **Sign in to Xcode** with the Alfajor LLC Apple ID (Xcode → Settings → Accounts). This is the one thing blocking the upload.
3. **Build**: version 1.1, build 1 was uploaded and attached to the 1.1 version on 14 November 2026, with the listing text and the iPhone Duo screenshots. What is left is pressing Submit for Review.

## App information

| Field | Value |
| --- | --- |
| Name (10/30) | Vibe Tapes |
| Subtitle (24/30) | Four-track tape recorder |
| Bundle ID | co.alfajor.tapes |
| SKU | vibe-tapes-ios |
| Primary language | English (U.S.) |
| Primary category | Music |
| Secondary category | none |
| Content rights | Does not contain, show or access third-party content |
| Age rating | 4+ (answer None or No to every question) |
| Copyright | 2026 Alfajor LLC |

## Pricing and availability

Your call. If unsure: Free, all countries and regions. The app has no in-app purchases.

## App privacy

| Field | Value |
| --- | --- |
| Privacy policy URL | https://tapes-web.vercel.app/privacy.html |
| Data collection | **No, we do not collect data from this app** (label reads "Data Not Collected") |
| Tracking | No |

The build carries a privacy manifest (`Tapes/PrivacyInfo.xcprivacy`) declaring no tracking, no collected data, and UserDefaults for the app's own settings (reason CA92.1).

## Version 1.1

**What's New** (221 of 4000)

```
Vibe Tapes now works on iPhone Duo.

• Closed, it is the same recorder, fitted to the smaller screen.
• Open, the mixer sits beside the reel, with a fader for each track.
• Half open, the controls move clear of the hinge.
```

**Promotional text** (122/170)

```
Plug in a synth, press record, and layer four tracks on one tape. No menus, no accounts. Just a recorder you work by hand.
```

**Description** (1557/4000)

```
Vibe Tapes is a four-track tape recorder for iPhone and iPad. It is one screen with no menus, built like a piece of hardware: every control does one thing and shows its own state.

USE IT TO
• Jam with a synth or drum machine. Plug it into the USB-C port and record it directly. When you stop, the tape plays back through the speaker, so there is nothing to unplug.
• Catch an idea before it goes. Open the app, press record, and sing or play into the microphone.
• Build a song in layers. Record a part, pick the next track, and play over what you already have.
• Practise a hard section. Mark it with cues, switch the loop on, and slow the tape down.

HOW IT WORKS
• Four tracks on a six-minute tape, each with level, pan, mute and solo.
• A reel you turn by hand to move through the tape, with a tick you can feel at every second.
• Tape speed from quarter to four times. Pitch follows speed, as it does on real tape.
• A click with tempo from 40 to 240 bpm.
• Cues and a loop that repeats the section you are in.
• Export mixes the four tracks into one audio file you can share or save.

IN THE BACKGROUND
Recording carries on when you leave the app or lock the screen. A Live Activity shows the take running on the Lock Screen and in the Dynamic Island.

THREE FINISHES
Light, dark or green. On iPad, and on iPhone Duo when it is open, the mixer sits beside the reel, with a fader for each track.

PRIVATE
No account, no ads, no tracking. The app never connects to the internet. Your tapes stay on your device, and you can reach them in the Files app.

Requires iOS 18 or later.
```

**Keywords** (98/100)

```
4-track,multitrack,recorder,synth,looper,cassette,jam,demo,overdub,usb audio,metronome,sketch,band
```

| Field | Value |
| --- | --- |
| Support URL | https://tapes-web.vercel.app/support.html |
| Marketing URL | https://tapes-web.vercel.app |
| Version | 1.1 |
| What's New | above, under the version heading |

## Screenshots

Only the first two sizes are required; Apple scales them for other devices. The iPhone Duo slot is optional until April 2027, and filling it puts an iPhone Duo badge on the product page. Upload in file-name order.

| Slot | Folder | Size |
| --- | --- | --- |
| iPhone with Dynamic Island (medium display) | `appstore/screenshots/iphone` | 1206 × 2622 |
| iPad 13" | `appstore/screenshots/ipad-13` | 2064 × 2752 |
| iPhone Duo, inner display on its side | `appstore/screenshots/iphone-duo` | 2853 × 2007 |

The Duo set shows the app on the open device, the way it opens (01 to 03), and the three finishes on the closed device (04). The slot also takes the outer display at 1398 × 2034. App Store Connect accepted both sizes in the iPhone Duo slot on 14 November 2026.

1. `01-four-tracks.png` — Four tracks. One tape.
2. `02-record.png` — Plug in a synth. Press record.
3. `03-by-hand.png` — Move the tape by hand.
4. `04-finishes.png` — Light, dark or green.

`appstore/screenshots/raw` holds the plain captures (no caption or frame) at the same sizes, in case you would rather upload those. `appstore/screenshots/capture.sh` retakes and reframes the whole set in the simulator.

The app icon comes from the build; `appstore/icon-1024.png` is a copy for anywhere else that asks for one.

## Header and search artwork

The creative assets from Apple's [asset best practices](https://developer.apple.com/app-store/asset-best-practices/). They are optional and separate from screenshots. Upload them in App Store Connect with the version, or through the Asset Library.

The artwork is a generated photograph of the reel as a physical object (made with Codex image generation from the app's design), then scaled to Apple's sizes.

| Asset | File in `appstore/artwork` | Size | Art safe area |
| --- | --- | --- | --- |
| Product page header (21:9) | `header.png` | 3840 × 1646 | 1646 × 661 at x 1097, y 493 |
| Search results (3:2) | `search.png` | 3840 × 2560 | 2168 × 1030 at x 836, y 765 |
| Universal, header and search (16:9) | `universal.png` | 5244 × 2950 | 1402 × 962 at x 1921, y 660 |

All are PNG with no transparency and no text.

- `header.png` is the approved close-up. The reel is taller than the safe area, so the orange dot and the reel's lower edge can be cropped where Apple trims the header. `header-safe.png` is the same scene pulled back so the whole reel fits inside the safe area.
- `search.png` and `universal.png` are pulled back for the same reason; the universal safe area is small.
- `generated` holds the originals as they came out (about half size) and the six first-round variations. `from-app` holds the earlier set composed from real controls, with its script.
- `resize.swift in.png out.png W H` scales an image to an exact size without transparency.

The sizes and safe areas come from Apple's creative assets specification page. Check them against Apple's template for each asset before uploading.

## App review information

| Field | Value |
| --- | --- |
| Sign-in required | No |
| Contact first name, last name, phone, email | yours (Apple only uses these if the reviewer has a question) |
| Attachment | none |

**Notes** (874/4000)

```
Vibe Tapes is a four-track audio recorder. There is no account or sign-in, no purchases and no network access.

To try it: allow the microphone when asked, press the round orange key to record and the wide key to stop. The leftmost key returns to the start; the wide key then plays the take back. Tap a track key (1–4) to choose which track records. The gear at the top left opens the list of tapes and the settings.

Background audio: the app declares the audio background mode because a recording or playback in progress continues when the app leaves the foreground, with a Live Activity showing the take. When the tape is stopped, the app releases the microphone and stops all audio on leaving the foreground.

External hardware is optional. A class-compliant USB audio device can be plugged in and recorded, but everything works with the built-in microphone and speaker.
```

## Questions asked on submit

| Question | Answer |
| --- | --- |
| Export compliance (encryption) | None. Already declared in the build (`ITSAppUsesNonExemptEncryption = NO`), so you should not be asked |
| Advertising identifier (IDFA) | No |
| Version release | Your call. "Manually release this version" lets you pick the day |

## Not in this set

- A Lock Screen shot of the Live Activity. The simulator shows a permission prompt over it; take one on your phone if you want it (record, lock, screenshot) and it can be framed with `compose.swift`.
- An app preview video. Optional.

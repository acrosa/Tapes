---
name: appstore-release
description: Prepare and ship an App Store release of an iOS or iPadOS app - the first submission, a new version, or a refresh of the listing. Bumps the version, writes the listing text and What's New, takes and frames the screenshots, makes the product page header and search artwork (with Codex image generation), builds the archive, and leaves a checked submission sheet in appstore/README.md. With an App Store Connect API key on the machine it also uploads the build, sets the listing and screenshots, and submits for review. Use when the user says "prepare the App Store submission", "new release", "new version", "bump the version", "update the screenshots", "App Store assets", "What's New", "TestFlight", or "ship it to the store".
---

# App Store release

Everything for a release lives in the project's `appstore/` folder. The deliverable is
`appstore/README.md`: one sheet with every field to paste into App Store Connect, in the order
the site asks for it, plus the image files it points to. Keep it true to the build; it is the
thing the user works from.

| Path in the project | What it is |
| --- | --- |
| `appstore/README.md` | The submission sheet. Rewrite it for each release. |
| `appstore/NOTES.md` | What is particular to this app (see below). Read it first; create it on a first run. |
| `appstore/screenshots/capture.sh` | Captures in the simulator and composes the framed set. |
| `appstore/screenshots/iphone`, `ipad-13` | The sets to upload. |
| `appstore/screenshots/raw` | Plain captures, same sizes. |
| `appstore/artwork/header.png`, `search.png`, `universal.png` | Product page header and search artwork. |
| `appstore/artwork/generated` | Codex originals and rejected variations. |

Scripts that come with this skill, in its `scripts` folder (compile with `swiftc -O`):

| Script | Use |
| --- | --- |
| `capture-template.sh` | Starting point for a project's `capture.sh`. |
| `frame-screenshot.swift` | Puts a capture (or three, fanned) under a two-line caption at an exact size. |
| `contact-sheet.swift` | Numbered sheet of images for the user to choose from. |
| `resize.swift` | Scales an image to an exact size as an opaque PNG. |
| `asc.py` | App Store Connect API with a team key: any request, plus screenshot upload, attaching a build, and submitting for review. |

## The project's notes

`appstore/NOTES.md` holds what cannot be worked out again cheaply: bundle ID and store name,
team, where the version numbers are set, the site URLs, simulators and launch arguments used
for screenshots, the captions, which launch arguments are destructive, how the listing should
read, the chosen artwork direction, and anything the user corrected last time. Read it before
doing anything. If it is missing, this is a first run: find those facts in the project
(`project.yml` or the Xcode project, Info.plist, privacy manifest, README, the app's docs), ask
the user only for what the project cannot tell you, and write the file. Add to it whenever the
user corrects something.

## First, work out which kind of release this is

Ask only if it is not clear from the request.

- **First submission.** Do every step below.
- **New version** (new features or fixes). Steps 1, 2, 3, 6, 7 always. Step 4 if anything visible
  changed. Step 5 only if the user wants new artwork.
- **Listing refresh** (text or images, same build). Steps 2, 4 or 5 as asked, then 7. No version
  bump, no archive.

Read `git log` since the last release (a tag, or the commit that last changed the version) and
the app's own docs to learn what changed. Do not describe a feature in the listing that the
build does not have; check the code when unsure.

## 1. Version

Find every place the marketing version and build number are set (XcodeGen `project.yml`, build
settings, Info.plists). App extensions must carry the same two numbers as the app.

- New version: raise the marketing version (ask for the number if it was not given) and set the
  build to 1, or the next number if the project counts builds upward.
- Another build of the same version (a rejected or replaced upload): raise only the build
  number. App Store Connect refuses one it has seen.

Regenerate the project if it is generated.

## 2. Listing text

Write into `appstore/README.md`. Limits are hard; count with a script, not by eye, and print the
count next to each field.

| Field | Limit | Notes |
| --- | --- | --- |
| Name | 30 | Do not change without being asked. |
| Subtitle | 30 | |
| Promotional text | 170 | Can change without a new build. |
| Description | 4000 | |
| Keywords | 100 | Comma-separated, no spaces after commas, no words already in the name. |
| What's New | 4000 | Every version after the first. Not asked for on a first version. |
| Review notes | 4000 | How to try it, a demo account if there is sign-in, why each background mode and permission. |

Also in the sheet: bundle ID, SKU, primary language, categories, content rights, age rating
answers, copyright, privacy policy URL, support URL, marketing URL, the App Privacy answers,
and the export compliance answer.

How the text should read, unless the notes say otherwise:

- Short and plain. No marketing voice, nothing that sounds machine-written.
- Lead with what someone does with the app, then how it works. Use cases before features.
- What's New: what changed for the person using it, most important first, a few lines. No
  "bug fixes and improvements" filler; name the fix.
- No other companies' brand names, no other apps' names, no prices, no claims that cannot be
  checked.

The privacy policy and support URLs must load before submission. If the project has a site,
write or update those pages there. They must match what the app does: check the code for
network calls, analytics, accounts and permissions before writing "collects nothing".

## 3. Checks before building

- A privacy manifest (`PrivacyInfo.xcprivacy`) exists and matches the app: tracking, collected
  data, and a reason for each required-reason API in use (UserDefaults, file timestamps, system
  boot time, disk space, active keyboards).
- Every permission the app asks for has a usage string that says what it is for.
- `ITSAppUsesNonExemptEncryption` is set and true to the code.
- The icon is 1024 × 1024 with no alpha.
- iPad builds without `UIRequiresFullScreen` support all four orientations.
- Run the project's tests. Report failures; do not ship around them.

## 4. Screenshots

Required sizes, as last read (re-check
<https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>
when a new device class ships): "iPhone with Dynamic Island (medium display)" at 1206 × 2622 or
1179 × 2556, and iPad 13" at 2064 × 2752 if the app runs on iPad. Apple scales these for other
devices. PNG or JPEG, no alpha, up to 10 per size. An iPhone Duo slot (`APP_IPHONE_DUO`) exists and becomes
required in April 2027 for apps built with the iOS 27.1 SDK or later: outer display 1398 × 2034,
inner display 2007 × 2853 (or either on its side; App Store Connect took 1398 × 2034 and
2853 × 2007 in November 2026). Capture the inner display with the device opened flat: half open,
an app that respects the fold lays itself out around it. A Duo simulator has two displays; a fresh boot
leaves it closed, `simctl io <device> screenshot --display=LCD` captures the outer one and
`--display=LCD-1` the inner one. Nothing on the command line opens it: that is done by hand in
Device Hub (inside Xcode.app), so ask the user when the inner set is wanted.

The upload page is the authority, not this list: App Store Connect names the accepted sizes
under each slot and rejects anything else with "File dimensions are invalid" (it refused
1320 × 2868, the old 6.9" size, in November 2026). If the user can show that page, read the
sizes from it before capturing. Capture on a simulator whose screen is natively that size;
do not rescale a capture from another device.

If the project has `appstore/screenshots/capture.sh`, run it. Otherwise copy
`scripts/capture-template.sh` there and fill it in. The app needs a way to launch straight into
each state worth showing, with demo data: launch arguments compiled only into debug or
simulator builds. Add them if they are missing.

- **Simulator only** for anything that seeds, resets or writes data. Never pass such an argument
  to a physical device. Compile a destructive one under `#if targetEnvironment(simulator)`.
- Install the app itself, not the UI test runner that sits beside it in the build folder.
- `simctl io screenshot` may be unable to write into the repository; capture to a temporary
  folder and copy.
- Screenshots must show the real app in use. Do not generate them or paint over them.
- Captions are two short lines saying what the person can do. Four to six images is plenty.
- The script ends by printing each file's size. Check they are exact, then look at the images
  (a contact sheet is enough) before saying they are done.
- Things the simulator cannot show from the command line (Lock Screen, Live Activities behind a
  permission prompt): ask the user for a capture from their device.

## 5. Header and search artwork

Optional assets from <https://developer.apple.com/app-store/asset-best-practices/>. Re-read that
page and its creative assets specification before making new ones; sizes and safe areas change.
As last read:

| Asset | Size | Art safe area (from top left) |
| --- | --- | --- |
| Product page header, 21:9 | 3840 × 1646 | 1646 × 661 at x 1097, y 493 |
| Search results, 3:2 | 3840 × 2560 | 2168 × 1030 at x 836, y 765 |
| Universal, 16:9, PNG only | 5244 × 2950 | 1402 × 962 at x 1921, y 660 |

PNG or JPEG, no transparency. No text needed; no logos, prices, URLs, awards or other platforms.

Generate these with the Codex CLI in the app's look, and let the user choose:

1. Make reference images: captures from `appstore/screenshots/raw`, downsized
   (`sips -Z 1400`). Work in a scratch folder, not the repository.
2. Write six different art directions (for example: studio product shot, a scene showing the
   use, a macro of the most recognisable control, a dark version, a colour version, a flat
   graphic poster). Each prompt describes the app's design in words (shapes, materials,
   colours, the one accent), asks for the widest landscape format, the subject in the centre
   with croppable edges, and no text, logos or people. Tell Codex to use its image tool, not to
   draw with code, and the file name to save.
3. Run them in parallel, one image each:
   ```sh
   codex exec --skip-git-repo-check -s workspace-write -i ref.png - < prompt1.txt > log1.txt 2>&1 &
   ```
   Each takes about a minute and saves into the current directory. Output is roughly
   1914 × 822 for 21:9, 1536 × 1024 for 3:2, 1672 × 941 for 16:9.
4. Build a numbered sheet with `contact-sheet.swift`, copy the sheet and images to
   `appstore/artwork/generated`, send the sheet to the user, say which you would pick and what
   each gets wrong about the app, and **stop for their choice**. Do not pick for them.
5. For the chosen image, ask Codex for the other two shapes with the chosen image attached as
   the reference ("recreate this exact scene; the only change is the framing"), stating where
   the subject must sit for that asset's safe area.
6. Scale to exact sizes with `resize.swift` (`resize in.png out.png W H`).
7. Tell the user plainly: these are enlarged 2–3×; whether the subject fits the safe area; and
   which versions are new renders they have not approved yet. Record the chosen direction in
   the notes.

Prompts and reference images go to an outside service. Send only the app's design. Never put the
user's name, email or anything else personal in a prompt.

## 6. Archive and upload

```sh
xcodebuild -project <App>.xcodeproj -scheme <Scheme> -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/<App>.xcarchive archive
```

Check the archive's `Info.plist` shows the new version and build, and that the privacy manifest
is inside the app.

**Ask before uploading, submitting, pushing or tagging**, unless the user has already said to go
ahead with that step for this release. Each is outward-facing, and approval for one is not
approval for the next: "upload the build" does not mean "submit it for review". If the privacy
and support pages live in the repository, they only load once it is pushed and the site has
redeployed, so the push comes before the submission.

### With an App Store Connect API key

The notes (or your memory for the project) say whether there is a key, with its Key ID and
Issuer ID; the `.p8` is in `~/.appstoreconnect/private_keys`. The key covers every app on the
team: touch only the app being released. Never print the key or copy it into the project, and
keep the Key ID and Issuer ID out of a public repository.

- The key must have the **Admin** role to sign an upload. A lesser key edits the listing but
  `-exportArchive` fails with "Cloud signing permission error" (no access to cloud-managed
  distribution certificates). A key's role cannot be changed; the user makes a new one. Without
  the key flags the export fails with "Failed to Use Accounts" even when Xcode is signed in.
  Do not work around either; say what is needed.
- **Read the state first** (`asc.py GET "/v1/apps/<app>/appStoreVersions?limit=5"`, the builds,
  the version's localization and its screenshot sets). The user may already have created the
  version, written What's New, or uploaded images; change only what this release changes.
- A build can only be attached to a version with the **same marketing version**: a 1.0.1 build
  cannot go on version 1.1. Match the project's version to the version on App Store Connect
  before archiving, and use a build number that version has not seen.

Upload, with an export options plist whose `method` is `app-store-connect`, `destination` is
`upload`, `signingStyle` is `automatic` and `teamID` is the team:

```sh
xcodebuild -exportArchive -archivePath build/<App>.xcarchive -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 \
  -authenticationKeyID <KEYID> -authenticationKeyIssuerID <ISSUER>
```

Then, with `ASC_KEY_ID` and `ASC_ISSUER_ID` set, `scripts/asc.py` does the rest:

1. Wait for the build: `GET "/v1/builds?filter[app]=<app>&filter[preReleaseVersion.version]=<version>&sort=-uploadedDate"`
   until `processingState` is `VALID` (a few minutes). Then `asc.py attach <version id> <build id>`.
2. Listing text: `PATCH /v1/appStoreVersionLocalizations/<id>` with `whatsNew`, `description`,
   `promotionalText` or `keywords`. Count the characters before sending.
3. Screenshots: `asc.py screenshots <set id> files…` adds them and waits until Apple accepts them
   (wrong dimensions fail here). When replacing a set, upload the new ones first, then `DELETE`
   the old `appScreenshots`, then set the order with
   `PATCH /v1/appScreenshotSets/<id>/relationships/appScreenshots`. Create a missing set with
   `POST /v1/appScreenshotSets` and its `screenshotDisplayType`.
4. Submit, only when the user says so: `asc.py submit <app id> <version id>`. The version should
   then read `WAITING_FOR_REVIEW`. Tell the user how it is set to release (`releaseType`).

Not in the API, so still the user's: agreements, tax and banking, and the App Privacy answers.

### Without a key

Uploading needs the team's Apple ID signed into Xcode (Settings → Accounts). Give the user the
Organizer steps (Window → Organizer → Distribute App → App Store Connect → Upload) and the
sheet to paste from.

## 7. Finish the sheet and report

`appstore/README.md` must end up with: what the user has to do first; app information; pricing
(their call); privacy answers; this version's text with counts; screenshot and artwork tables;
review information; the questions asked on submit; what is not included. For a new version, put
What's New directly under the version heading.

Then tell the user, briefly:

- what is ready and where it is;
- what was done on App Store Connect, if anything (uploaded, attached, text, images, submitted);
- what only they can do (sign in, upload, paste, contact details, price, pressing Submit);
- what was not verified (tests not run, images not viewed at full size, specs not re-read);
- that nothing was committed, pushed or uploaded, unless they asked for it.

If the project's own docs describe something this release changed, update them in the same pass.

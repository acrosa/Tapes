#!/bin/zsh
# TEMPLATE. Copy to <project>/appstore/screenshots/capture.sh and fill in the block below.
# Captures App Store screenshots in the simulator and composes the framed, captioned set.
# Run from the repository root:  appstore/screenshots/capture.sh
#
# Simulator only. If any launch argument below resets or writes user data, it must never be
# passed to a physical device.
set -euo pipefail

# ---- fill in ---------------------------------------------------------------------------------
PROJECT_FLAG=(-project MyApp.xcodeproj)              # or (-workspace MyApp.xcworkspace)
SCHEME=MyApp
APP_NAME=MyApp.app                                   # the app, not the UI test runner beside it
BUNDLE=com.example.myapp
PHONE_NAME="${PHONE_NAME:-iPhone 18 Pro}"            # medium Dynamic Island slot, 1206 x 2622
PAD_NAME="${PAD_NAME:-iPad Pro 13-inch (M5)}"        # 13" slot, 2064 x 2752; empty if iPhone only
FONT="-"                                             # caption font file, or "-" for Helvetica Neue
GRANTS=()                                            # e.g. (microphone photos) to skip permission alerts
BASE_ARGS=()                                         # launch arguments for every shot (demo data…)
SKILL=~/.claude/skills/appstore-release/scripts      # or .claude/skills/appstore-release/scripts
# ----------------------------------------------------------------------------------------------

OUT=appstore/screenshots; RAW=$OUT/raw; TMP=$(mktemp -d)
udid() { xcrun simctl list devices available | grep -F "$1 (" | sort -r | head -1 | grep -oE '[0-9A-F-]{36}'; }
DEVICES=(); PHONE=$(udid "$PHONE_NAME"); DEVICES+=($PHONE)
PAD=""; [[ -n "$PAD_NAME" ]] && { PAD=$(udid "$PAD_NAME"); DEVICES+=($PAD); }
[[ -n "$PHONE" ]] || { echo "Simulator not found: $PHONE_NAME"; exit 1; }

xcodebuild $PROJECT_FLAG -scheme $SCHEME -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build build | grep -E "error|BUILD" || true
APP=build/Build/Products/Debug-iphonesimulator/$APP_NAME
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

for d in $DEVICES; do
  xcrun simctl boot $d 2>/dev/null || true
  xcrun simctl bootstatus $d >/dev/null
  xcrun simctl install $d "$APP"
  for g in $GRANTS; do xcrun simctl privacy $d grant $g $BUNDLE; done
  xcrun simctl status_bar $d override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 --dataNetwork wifi
done

mkdir -p $RAW
shot() {    # device name launch-arguments…
  local d=$1 n=$2; shift 2
  xcrun simctl terminate $d $BUNDLE >/dev/null 2>&1 || true
  xcrun simctl launch $d $BUNDLE $BASE_ARGS "$@" >/dev/null
  sleep 8
  xcrun simctl io $d screenshot $TMP/$n.png >/dev/null 2>&1     # simctl may not write into the repo
  cp $TMP/$n.png $RAW/$n.png
}
# ---- one line per state; the app needs launch arguments (or deep links) that reach each one ---
shot $PHONE p-home
shot $PHONE p-detail -showDetail
[[ -n "$PAD" ]] && shot $PAD i-home
[[ -n "$PAD" ]] && shot $PAD i-detail -showDetail
# ----------------------------------------------------------------------------------------------
for d in $DEVICES; do xcrun simctl terminate $d $BUNDLE >/dev/null 2>&1 || true; done

swiftc -O $SKILL/frame-screenshot.swift -o $TMP/frame
frame() {  # folder prefix width height
  mkdir -p $OUT/$1
  # ---- one line per store image: file, size, "caption|second line", ink, font, capture(s) ----
  $TMP/frame $OUT/$1/01-home.png $3 $4 "First caption|second line." dark $FONT $RAW/$2-home.png
  $TMP/frame $OUT/$1/02-detail.png $3 $4 "Second caption|second line." dark $FONT $RAW/$2-detail.png
}
frame iphone p 1206 2622
[[ -n "$PAD" ]] && frame ipad-13 i 2064 2752

sips -g pixelWidth -g pixelHeight -g hasAlpha $OUT/*/0*.png | grep -v '^ *$' | paste - - - - | sed 's|.*/screenshots/||'

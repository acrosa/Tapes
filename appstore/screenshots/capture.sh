#!/bin/zsh
# Captures the App Store screenshots in the simulator and composes the framed, captioned set.
# Run from the repository root:  appstore/screenshots/capture.sh
#
# Simulator only. It launches with -resetTapes and -autorecord, which empty the shelf and write
# onto the tape; neither may ever be passed to a physical device.
set -euo pipefail

PHONE_NAME="${PHONE_NAME:-iPhone 18 Pro}"            # "iPhone with Dynamic Island (medium display)" slot, 1206 x 2622
PAD_NAME="${PAD_NAME:-iPad Pro 13-inch (M5)}"        # 13" slot, 2064 x 2752
DUO_NAME="${DUO_NAME:-iPhone Duo}"                   # iPhone Duo slot: inner display 2853 x 2007 (open, on its side); outer is 1398 x 2034
DUO_WAIT="${DUO_WAIT:-600}"                          # seconds to wait for someone to open the Duo in Device Hub; 0 keeps the last open captures
BUNDLE=co.alfajor.tapes
OUT=appstore/screenshots
RAW=$OUT/raw
FONT=Tapes/Fonts/Geist-Medium.otf
TMP=$(mktemp -d)

udid() { xcrun simctl list devices available | grep -F "$1 (" | sort -r | head -1 | grep -oE '[0-9A-F-]{36}'; }
PHONE=$(udid "$PHONE_NAME"); PAD=$(udid "$PAD_NAME")
# The Duo is optional: not every Xcode has it, and a simulator on a newer runtime may refuse to
# boot ("Invalid argument"). Take the first one that boots, or pin one with DUO=<udid>.
# It is restarted on purpose: a Duo simulator is closed when it boots, and nothing on the command
# line opens or closes it, so this is how to be sure the outer display is the live one.
DUO="${DUO:-}"
if [[ -z "$DUO" ]]; then
  for u in $(xcrun simctl list devices available | grep -F "$DUO_NAME (" | grep -oE '[0-9A-F-]{36}'); do
    xcrun simctl shutdown $u 2>/dev/null || true
    if xcrun simctl boot $u 2>/dev/null; then DUO=$u; break; fi
  done
else
  xcrun simctl shutdown $DUO 2>/dev/null || true
fi
[[ -n "$DUO" ]] || echo "No iPhone Duo simulator boots; skipping that set."
[[ -n "$PHONE" && -n "$PAD" ]] || { echo "Simulator not found: '$PHONE_NAME' or '$PAD_NAME'"; exit 1; }

xcodegen generate >/dev/null
xcodebuild -project Tapes.xcodeproj -scheme Tapes -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build build | grep -E "error|BUILD" || true
APP=build/Build/Products/Debug-iphonesimulator/Tapes.app     # not the UI test runner next to it
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

for d in $PHONE $PAD $DUO; do
  xcrun simctl boot $d 2>/dev/null || true
  xcrun simctl bootstatus $d >/dev/null
  xcrun simctl install $d "$APP"
  xcrun simctl privacy $d grant microphone $BUNDLE
  xcrun simctl status_bar $d override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 --dataNetwork wifi
done

mkdir -p $RAW
DISPLAY_ARG=()
shot() {    # device name launch-arguments…
  local d=$1 n=$2; shift 2
  xcrun simctl terminate $d $BUNDLE >/dev/null 2>&1 || true
  xcrun simctl launch $d $BUNDLE -resetTapes -seedDemoTape "$@" >/dev/null
  sleep 8
  xcrun simctl io $d screenshot $DISPLAY_ARG $TMP/$n.png >/dev/null 2>&1     # simctl cannot write into the repo
  cp $TMP/$n.png $RAW/$n.png
}
shot $PHONE p-light-play -theme light -autoplay
shot $PHONE p-dark-rec   -theme dark  -autorecord
shot $PHONE p-green      -theme green -autoplay
shot $PHONE p-land       -theme light -autoplay -landscape
shot $PHONE p-edit       -theme light -edit
shot $PAD   i-light-play -theme light -autoplay
shot $PAD   i-dark-rec   -theme dark  -autorecord
shot $PAD   i-green      -theme green -autoplay
shot $PAD   i-edit       -theme light -edit
if [[ -n "$DUO" ]]; then
  DISPLAY_ARG=(--display=LCD)      # the outer display; the inner one is LCD-1
  shot $DUO d-light-play -theme light -autoplay
  shot $DUO d-dark-rec   -theme dark  -autorecord
  shot $DUO d-green      -theme green -autoplay
  # The open device. Only a person can open it, in Device Hub; wait for the inner display to light.
  inner_live() { xcrun simctl io $DUO screenshot --display=LCD-1 $TMP/probe.png >/dev/null 2>&1 && (( $(stat -f%z $TMP/probe.png) > 300000 )); }
  xcrun simctl launch $DUO $BUNDLE -seedDemoTape >/dev/null
  if ! inner_live && (( DUO_WAIT > 0 )); then
    open -a "$(xcode-select -p)/../Applications/DeviceHub.app" 2>/dev/null || true
    echo "Open the iPhone Duo in Device Hub (the pose buttons under the device). Waiting up to ${DUO_WAIT}s…"
    for ((t = 0; t < DUO_WAIT; t += 5)); do inner_live && break; sleep 5; done
  fi
  if inner_live; then
    DISPLAY_ARG=(--display=LCD-1)
    shot $DUO o-light-play -theme light -autoplay
    shot $DUO o-dark-rec   -theme dark  -autorecord
    shot $DUO o-green      -theme green -autoplay
    shot $DUO o-edit       -theme light -edit
  else
    echo "The Duo was not opened; keeping the open captures already in $RAW, if any."
  fi
  DISPLAY_ARG=()
fi
for d in $PHONE $PAD $DUO; do xcrun simctl terminate $d $BUNDLE >/dev/null 2>&1 || true; done

swiftc -O $OUT/compose.swift -o $TMP/compose
compose() {  # folder prefix width height
  mkdir -p $OUT/$1
  $TMP/compose $OUT/$1/01-four-tracks.png $3 $4 "Four tracks.|One tape." dark $FONT $RAW/$2-light-play.png
  $TMP/compose $OUT/$1/02-record.png $3 $4 "Plug in a synth.|Press record." light $FONT $RAW/$2-dark-rec.png
  $TMP/compose $OUT/$1/03-by-hand.png $3 $4 "Move the tape|by hand." dark $FONT $RAW/$2-green.png
  $TMP/compose $OUT/$1/04-finishes.png $3 $4 "Light, dark|or green." dark $FONT \
    $RAW/$2-light-play.png $RAW/$2-dark-rec.png $RAW/$2-green.png
  $TMP/compose $OUT/$1/05-cut.png $3 $4 "Cut a take.|Move the pieces." light $FONT $RAW/$2-edit.png
}
compose iphone p 1206 2622
compose ipad-13 i 2064 2752
# iPhone Duo: the open device for the first three, the closed one for the three finishes, all on
# a canvas the size and way up of the inner display as it was captured.
if [[ -f $RAW/o-light-play.png && -f $RAW/d-light-play.png ]]; then
  DW=$(sips -g pixelWidth $RAW/o-light-play.png | awk '/pixelWidth/{print $2}')
  DH=$(sips -g pixelHeight $RAW/o-light-play.png | awk '/pixelHeight/{print $2}')
  rm -rf $OUT/iphone-duo; mkdir -p $OUT/iphone-duo
  $TMP/compose $OUT/iphone-duo/01-four-tracks.png $DW $DH "Four tracks.|One tape." dark $FONT $RAW/o-light-play.png
  $TMP/compose $OUT/iphone-duo/02-record.png $DW $DH "Plug in a synth.|Press record." light $FONT $RAW/o-dark-rec.png
  $TMP/compose $OUT/iphone-duo/03-by-hand.png $DW $DH "Move the tape|by hand." dark $FONT $RAW/o-green.png
  $TMP/compose $OUT/iphone-duo/04-finishes.png $DW $DH "Light, dark|or green." dark $FONT \
    $RAW/d-light-play.png $RAW/d-dark-rec.png $RAW/d-green.png
  $TMP/compose $OUT/iphone-duo/05-cut.png $DW $DH "Cut a take.|Move the pieces." light $FONT $RAW/o-edit.png
elif [[ -f $RAW/d-light-play.png ]]; then
  compose iphone-duo d 1398 2034      # no open captures yet: the closed device throughout
fi

sips -g pixelWidth -g pixelHeight -g hasAlpha $OUT/iphone/*.png $OUT/ipad-13/*.png $OUT/iphone-duo/*.png(N) | grep -v '^ *$' | paste - - - - | sed 's|.*/screenshots/||'

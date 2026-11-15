# Tapes — product spec

Version 0.1. iPhone (portrait and landscape), iPhone Duo (closed and open) and iPad (all orientations), iOS 18 or later.

## The idea

Reel (reelaudio.app) proves a phone can be a pocket four-track with a hardware feel. Its cost is
modes: Cue, Pitch and Loop are each a three-state button that changes what the disc and the +/−
buttons do, and many functions are chords (hold Stop + tap another button).

Tapes keeps the instrument and removes the modes:

1. **One control per function.** Speed is a wheel. Loop is a key. The dial always moves the tape.
   Cutting the tape is the one exception: it is a second surface under the faceplate (see
   Cutting), made to look nothing like it, so no control on the faceplate ever changes what it does.
2. **State lives on the control.** A lamp, a pointer or a fill. The display confirms each change in words.
3. **The tape is visible.** A scale shows what is recorded on each track, the cues, the loop and the playhead.
4. **Nothing is hidden behind a chord.** Secondary actions sit in a touch-and-hold menu on the thing they act on.

## The tape

- Four mono tracks, 48 kHz, 32-bit float. Pan places each track in the stereo mix.
- A tape is six minutes long. This is a design limit (it keeps a tape an idea, not a session) and a memory limit (four tracks are held in memory).
- A tape remembers its name, tempo, speed, click, cues, loop and mix.
- Tapes are saved automatically: audio when a take ends, settings shortly after any change.

## Controls

### Display
| Shows | Notes |
| --- | --- |
| Counter | minutes:seconds.hundredths |
| State | STOP, PLAY, REC n. Replaced for 1.4 s by a readout after any change (for example `SPEED 1.25×`, `T2 LEVEL 80`). |
| Level | 16 dots over 48 dB, last three orange. Output level; input level while recording. |
| Tape name, tempo, speed | Tempo is bright when the click is on; speed is bright when it is not 1×. |

Gesture: swipe left or right across the display to step to the next or previous cue. The start of the tape counts as a cue.

### Tape scale
Time ticks, one lane per track (as long as that track's recording), cue marks, loop band, playhead needle.
The scale shows whole minutes: one minute at first, more as the recording grows.

Gesture: touch or drag to move the tape there. A touch within 10pt of a cue lands on the cue.

### Dial
Turns with the tape: half a turn per second at normal speed, clockwise is forward.

| Gesture | Result |
| --- | --- |
| Touch and hold | The tape stops under the finger. |
| Turn | Scrub. Half a turn is one second; the tape follows the finger exactly. |
| Flick and let go | The tape keeps the speed it was given and coasts down (or back up to speed if it was playing). |
| Double-tap | Return to the start. |

The dial is locked while recording.

### Speed wheel
0.25× to 4×, two octaves each way, 1× at the middle of the wheel. The wheel holds at 0.5×, 1× and 2×. Tape-style: pitch and speed move together.
Roll up for faster, down for slower. Double-tap returns to 1×. Recording always runs at 1×.

### Tempo wheel
40 to 240 bpm in whole beats. Sets the click. Roll up or down; two points of travel per beat, with a tick for each. The wheel holds at every ten beats (60, 70, 80 …).

### Click key
Metronome on or off. The click follows the tape position, so it stays on the beat through speed changes and after a jump. It is not recorded.

### Cue key
Press to mark the playhead position. Press again while resting on a mark to remove it.

### Loop key
On or off. On, the tape repeats the section the playhead is in: from the mark before it to the mark
after it. Cues are the marks, along with the start of the tape and the end of the recording.

- The display names the section: "LOOP START–CUE 1", "LOOP CUE 1–CUE 2", "LOOP CUE 2–END", or "LOOP ALL" when there are no cues. The scale shows it as a green band.
- With the loop on, touching a section on the tape scale, or jumping to a cue, moves the loop to that section. A loop is chosen by pointing at it.
- On an empty tape the key refuses and the display reads "NOTHING TO LOOP".

### Track keys (iPhone) and channel strips (iPad)
| Gesture | Result |
| --- | --- |
| Tap | Select the track. Record always records onto the selected track. |
| Drag up or down | Level. Detent at 100 %. |
| Drag sideways | Pan. Detent at centre. |
| Touch and hold | Mute, Solo, Centre pan, Erase track. |

On regular widths each track gets a full strip instead: select key, pan wheel, fader with meter, mute and solo keys.

### Transport
| Key | Result |
| --- | --- |
| Return | Back to the start. |
| Record | Starts recording on the selected track at the playhead, at 1×, while the other tracks play. Press again (or Play) to end the take. Recording over existing audio replaces it from that point (punch-in). |
| Play / Stop | Rolls or stops the tape. Play from the end of the recording starts again from the loop start, or the beginning. Playback stops by itself at the end of the recorded material. |

The first press of Record asks for the microphone. If it is refused, an alert offers Settings.

### Sound in and out (in the sheet behind the gear)
There is nothing to set up. The rule:

- Nothing plugged in: record from the built-in microphone, play through the speaker (or headphones).
- An instrument plugged in (a Roland T-8, an audio interface): record from it. Tape stopped, the instrument is heard live through this device, in headphones if there are any, otherwise the speaker. During a take it is still heard. While the tape plays back, the live sound steps aside and the tape is what is heard.
- The built-in microphone is never passed through: it would feed back into the speaker and echo in headphones.

Where iOS sends an instrument's sound back out through the instrument itself (it has offered some
devices only as such a pair), the speaker is forced between takes so the tape can be heard here,
and released for the take, because forcing the speaker also forces the microphone. In that case
the instrument is not passed through: it already plays itself. `-routeProbe` prints what iOS does
with whatever is plugged in.

Heard on an iPad with a T-8 and AirPods on 15 November 2026: T-8 in, AirPods out, live and on
playback. Over Bluetooth the live sound arrives about a fifth of a second late: fine for a
sequence, late for playing by hand.

If the input is not there when record is pressed, the tape does not roll: the display reads "NO INPUT".

| Setting | What it does |
| --- | --- |
| Input | Automatic (iOS chooses, preferring what was plugged in last), or any input on offer. A chosen input that is no longer plugged in counts as Automatic. So the microphone can be recorded while an instrument stays connected. |
| Hear the input | On by default. Off stops a plugged-in input being passed through; for a USB microphone that sits near the speaker. |

The sheet names the input and output in use.
Tracks are mono: a stereo input is summed. There is no MIDI.

### When the microphone is on
Only when it is needed: for the length of a take, and while a plugged-in instrument is being passed through to be heard. The built-in microphone is only ever on for a take.
The rest of the time the input is disconnected, so iOS shows no microphone indicator while the tape
sits or plays. If the app leaves the foreground with the tape at rest, it stops all audio and
releases the audio session until it returns.

### Recording in the background
Recording carries on when the app leaves the foreground or the device is locked (the audio
background mode). While it does, a Live Activity shows it on the Lock Screen and in the Dynamic
Island: the record lamp, "REC" and the track, the tape's name, and the counter running. It is drawn
as the display window in miniature, dark glass with light print, whatever finish the app is in.
Tapping it opens the app; it has no controls of its own. It ends when recording stops, including
when the tape runs out. The first time, iOS asks whether to allow Live Activities.

### Header
- **The gear** at the top left opens the shelf: open, create, rename (swipe), delete (swipe). Also holds the finish (Light, Dark or Green, each shown as a small preview tile), Haptics, and Show layout grid.
- **The scissors** beside the gear open the cutting controls (below). Dimmed on an empty tape and while recording.
- **export** mixes the tape to a stereo WAV with the current mix and speed and opens the share sheet.

Tape folders are also visible in the Files app (`Tapes/Tapes/<id>/track1.wav` …).

### Cutting

The scissors lift the faceplate away, upwards, and show the bed under it: dark glass from edge to
edge, whatever the finish, so there is no mistaking it for the recorder. It has two words, a
timeline and four keys. The status bar is hidden.

- **cancel** and **done** at the top, with the counter between them. The counter gives way for a
  moment to the word for what was just done ("CUT", "REMOVED").
- **The timeline**: the four tracks as lanes, 48pt to the second (72 on iPad). The tape lies
  still and the playhead travels along it, as on any timeline; when it nears the edge while
  playing, or is moved out of sight, the view glides on to keep it a quarter of the way along.
  **Touch** the tape to put the playhead there. **Drag** to look along the tape. **Pinch** to see
  more of the tape or less: from a tenth of a second across 48pt down to the whole recording on
  the screen, the second under the fingers staying under them. The scale is kept while the app runs. The lane being
  cut shows its pieces, each with the outline of its sound; the other lanes show their sound,
  dimmer, to place a piece against. A ruler runs along the bottom; its marks follow the scale
  (never closer than 8pt) and the longer ones carry the time.
- **Cut, remove, all, play** at the bottom. There is no record key, no dial and no tape scale here.

How it works:

- It opens on the selected track (on all four if that track is empty). **Touch another lane** to
  cut that track instead. **all** cuts the four as one tape, which keeps them in time with each
  other; press it again to go back to one track. Changing what is cut keeps what was done so far.
- **Cut** divides the piece under the playhead in two and picks up the second half. Nothing
  changes in the sound until a piece is moved or removed. A cut needs a hundredth of a second of
  piece on either side.
- **Touch a piece** to pick it up (it is outlined; the playhead goes to the touch as well). Touch an empty stretch of the lane to put it down.
- **Drag a picked-up piece** along the tape. It pulls to the start of the tape, to where it came
  from, and to the edges of other pieces when within 8pt. It cannot leave the tape.
- **Remove** takes the picked-up piece off the tape. The gap stays; nothing else moves.
- **Lay a piece over the end of another** and the two fade across the whole overlap: the longer
  the overlap, the longer the fade. Otherwise a loose end fades over 5 ms, so a cut never clicks.
  Pieces that still join where they were cut play through unchanged.
- What plays is always what is drawn. **done** keeps it and saves the tracks that changed;
  **cancel** puts every track back as it was when the scissors were pressed. Either brings the
  faceplate back down.

Not here yet: undo of a single step, copying a piece, and cutting while recording.

## Compared with Reel

| Reel | Tapes 0.1 |
| --- | --- |
| Cue mode button + / − | Cue key, swipe on display, touch on scale |
| Pitch mode button + disc | Speed wheel |
| Loop mode button + / − | Loop key |
| Hold Stop + … chords | Not used |
| Mixer sheet | Track keys as faders (iPhone), strips always visible (iPad) |
| Rewind / fast-forward keys | Flick the dial, or touch the scale |
| (no editing) | Scissors: cut, move and remove pieces of a track or of the whole tape |
| Stereo tracks, USB multitrack | Mono tracks, built-in or default input |

## Not in 0.1

Listed so nobody assumes they exist: stereo tracks, USB multichannel input and output routing,
input monitoring, count-in, wait-for-sound, record-length, recording into a running loop,
reverse playback, scratch (DJ) mode, resample and master record, MIDI and Ableton Link,
stem export and M4A/AIFF, audio import, iCloud, background recording, time signatures other than 4/4,
loop-point editing by dragging, undo for a take or for a single cut.

## Known limits

- Without headphones the microphone hears the speaker, so overdubs pick up the other tracks.
- External audio is untested with real hardware beyond one report with a Roland T-8 (see Sound, below).
- Take placement uses the latency the system reports. It has not been calibrated per device.
- Export writes the whole tape, not just the loop.

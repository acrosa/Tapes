# Tapes — product spec

Version 0.1. iPhone (portrait and landscape) and iPad (all orientations), iOS 18 or later.

## The idea

Reel (reelaudio.app) proves a phone can be a pocket four-track with a hardware feel. Its cost is
modes: Cue, Pitch and Loop are each a three-state button that changes what the disc and the +/−
buttons do, and many functions are chords (hold Stop + tap another button).

Tapes keeps the instrument and removes the modes:

1. **One control per function.** Speed is a wheel. Loop is a key. The dial always moves the tape.
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
after it. Cues are the marks, along with the start of the tape and the end of the recording, so with
no cues the whole recording loops. The display shows the range ("LOOP 0:04–0:06") and the scale shows
it as a green band. To loop a different section, switch the loop off, move the tape, switch it on.

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

### Header
- **tapes** opens the shelf: open, create, rename (swipe), delete (swipe). Also holds the finish (Light, Dark or Green, each shown as a small preview tile), Haptics, and Show layout grid.
- **export** mixes the tape to a stereo WAV with the current mix and speed and opens the share sheet.

Tape folders are also visible in the Files app (`Spule/Tapes/<id>/track1.wav` …).

## Compared with Reel

| Reel | Tapes 0.1 |
| --- | --- |
| Cue mode button + / − | Cue key, swipe on display, touch on scale |
| Pitch mode button + disc | Speed wheel |
| Loop mode button + / − | Loop key |
| Hold Stop + … chords | Not used |
| Mixer sheet | Track keys as faders (iPhone), strips always visible (iPad) |
| Rewind / fast-forward keys | Flick the dial, or touch the scale |
| Stereo tracks, USB multitrack | Mono tracks, built-in or default input |

## Not in 0.1

Listed so nobody assumes they exist: stereo tracks, USB multichannel input and output routing,
input monitoring, count-in, wait-for-sound, record-length, recording into a running loop,
reverse playback, scratch (DJ) mode, resample and master record, MIDI and Ableton Link,
stem export and M4A/AIFF, audio import, iCloud, background recording, time signatures other than 4/4,
loop-point editing by dragging, undo for a take.

## Known limits

- Without headphones the microphone hears the speaker, so overdubs pick up the other tracks.
- External audio: the app records from whatever input iOS has selected, so a class-compliant USB interface, USB microphone or instrument with USB audio becomes the input when plugged in, summed to mono. There is no input picker and no input monitoring; listen through the interface. Not yet tested with real hardware.
- Take placement uses the latency the system reports. It has not been calibrated per device.
- Export writes the whole tape, not just the loop.

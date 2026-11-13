# Tapes — motion and haptics spec

Tokens: `Motion` and `Haptics` in `Spule/Design/Theme.swift`. Tape physics: `TapeCore` in `Packages/TapeEngine`.

## Principles

1. **Things move because something moved them.** There is no entrance animation, no idle animation, no decoration.
2. **Under the finger, direct. On release, physical.** A control being dragged tracks the finger with no animation at all. Springs are for letting go and for state changes.
3. **The tape is real.** The dial, the needle and the counter are not animated. They display the audio engine's playhead, so what you see is exactly what you hear.
4. **Short.** Nothing in the interface takes longer than 0.4 s to settle. Only the tape itself is allowed inertia.
5. **Touch is confirmed at the moment of contact,** not on release.

## Tokens

| Token | Curve | Use |
| --- | --- | --- |
| `Motion.press` | spring, response 0.18, damping 0.62 | a key travelling down and back; wheels and fader caps being gripped; the dial being held |
| `Motion.settle` | spring, response 0.36, damping 0.82 | a control returning to rest (wheel reset); the record dot changing size |
| `Motion.lamp` | ease-out, 0.12 s | lamps, text-key dimming |
| `Motion.readout` | ease-in-out, 0.16 s | words cross-fading in the display |
| `Motion.readoutHold` | 1.4 s | how long a readout replaces the transport state |
| meters | linear, 0.05 s | level fills (the model updates them 30 times a second, falling 20 % per update) |

`press` is slightly under-damped on purpose: a key overshoots a little on the way back up, like a
sprung switch. `settle` does not overshoot visibly.

## Per component

| Component | Behaviour |
| --- | --- |
| Key | Down: face moves 1.5pt, shadow shrinks from (y 2, blur 2.5) to (y 0.5, blur 0.5), face darkens 3 %. `press` both ways. |
| Track key | Same travel while a level or pan drag is in progress. |
| Wheel | Ridges move with the finger 1:1, so the roller feels attached to the thumb. The value mark crosses its slot over the wheel's travel: 240pt for speed, 400pt for tempo (half a beat per point), 160pt for pan. Double-tap reset uses `settle`. |
| Wheel detents | At a detent the wheel holds its value while the finger keeps moving, then lets go: 16pt of hold (12pt on tempo). The hold is added to the travel, so no value is skipped or made unreachable. Speed holds at 0.5×, 1× and 2×; tempo at every ten beats; pan at centre. |
| Fader | Cap follows the finger 1:1 from where it was grabbed; it never jumps to the touch. |
| Dial | Shrinks to 98.5 % and its shadow tightens while held (`press`). Rotation is the playhead: π radians per second of tape. |
| Record key | The dot shrinks to 70 % while recording (`settle`); the lamp above it lights. |
| Play key | The glyph swaps with a symbol replace transition. |
| Display state | Cross-fade (`readout`). The counter never animates. |
| Tape scale | Redrawn each frame from the playhead. When the scale needs more minutes it changes at once. |
| Sheets | System presentation. |

## Tape physics

The playhead has a rate and a target rate. Each sample, the rate moves a fixed fraction of the way
to the target (a one-pole glide). Four time constants give the transport its character:

| Situation | Time constant | Constant |
| --- | --- | --- |
| Start | 0.09 s | `TapeCore.startTime` |
| Stop | 0.14 s | `TapeCore.stopTime` |
| Speed wheel while playing | 0.04 s | in `setRate` |
| Coast after releasing the dial | 0.45 s | `TapeCore.coastTime` |

- **Scrub.** While the dial is held, the playhead chases the finger's position: its rate is the remaining distance divided by 30 ms, limited to ±16×. Position stays locked to the hand and the pitch follows the hand's speed.
- **Flick.** On release the tape keeps its rate and glides to the resume rate (0 if stopped, the speed setting if playing) with the coast constant.
- **Slow tape is quiet tape.** Output fades in proportion to rate below 0.08×, so a held or stopping tape goes silent instead of buzzing.
- **Ends.** The tape stops dead at 0:00 and at six minutes. Playback also stops at the end of the recorded material.

Change the feel by changing these constants, not by adding animation in the views.

## Haptics

All through `Haptics`, which the Haptics preference can turn off.

| Event | Feedback |
| --- | --- |
| Key goes down | rigid impact, 0.7 (in `KeyStyle`, on press, not release) |
| Track selected | rigid impact, 0.7 |
| Finger lands on the dial or the tape scale | soft impact, 0.7 (`Haptics.touch`) |
| Dial passes each tenth of a second of tape | light impact, 0.35: the lightest tap (`Haptics.fine`) |
| Dial passes each whole second of tape | rigid impact, 0.65 (`Haptics.division`) |
| Tempo changes by one beat | selection tick; rigid impact, 0.5 on every tenth beat (a detent) |
| Jump to a cue | selection tick |
| Value snaps into a detent: speed 0.5×, 1× or 2×, pan centre, level 100 %, either end of a range | rigid impact, 0.5 (`Haptics.snap`) |
| Hard stop: start of tape while scrubbing, tape stopped itself, an action refused | rigid impact, 1.0 (`Haptics.stop`) |

A refused action (moving the dial while recording, switching the loop on with nothing recorded, export of an empty tape)
gives the hard-stop haptic and nothing else. No alert, no shake.

## Reduce Motion

The interface has no travel, parallax or zoom to remove: its motion is 1.5pt key travel, cross-fades
and the tape itself, which is the content. These stay on with Reduce Motion. If larger transitions
are added later, they need a cross-fade alternative.

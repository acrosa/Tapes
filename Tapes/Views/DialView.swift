import SwiftUI
import GridKit

/// The platter. It turns with the tape (half a turn per second at normal speed) and the tape
/// turns with it: hold to stop the tape, turn to scrub, flick to let it coast.
/// Double-tap returns to the start.
struct DialView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(Tilt.self) private var tilt

    @State private var lastAngle: Double?
    @State private var held = false
    @State private var lastDetent = 0

    /// Seconds of tape per fine haptic tap while scrubbing. Whole seconds get a firmer one.
    private let detent = 0.1

    var body: some View {
        GeometryReader { geo in
            let diameter = Rhythm.snapDown(min(geo.size.width, geo.size.height), to: Rhythm.u(2))
            let rim = Rhythm.u(2)
            ZStack {
                Circle().fill(Palette.recess)
                Circle()
                    .fill(Palette.key)
                    .shadow(
                        color: Palette.shadow.opacity(Palette.lift * 1.15),
                        radius: held ? 3 : 8,
                        x: held ? 0 : tilt.x * Motion.shadowDrift * 3,
                        y: held ? 1 : 5 + tilt.y * Motion.shadowDrift * 2
                    )
                    .overlay { Circle().strokeBorder(Palette.hairline, lineWidth: 0.5) }
                    .padding(rim)
                TimelineView(.animation) { _ in
                    DialFace()
                        .rotationEffect(.radians(recorder.position * .pi))
                }
                .padding(rim)
                Circle()
                    .fill(Palette.surface)
                    .overlay { Circle().strokeBorder(Palette.hairline, lineWidth: 0.5) }
                    .frame(width: Rhythm.snap(diameter * 0.16), height: Rhythm.snap(diameter * 0.16))
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(held ? 0.985 : 1)
            .animation(Motion.press, value: held)
            .contentShape(Circle())
            .gesture(scrub(center: CGPoint(x: diameter / 2, y: diameter / 2), radius: diameter / 2))
            .simultaneousGesture(TapGesture(count: 2).onEnded { recorder.returnToStart() })
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement()
        .accessibilityLabel("Tape dial")
        .accessibilityValue(DisplayView.counter(Double(recorder.positionTenths) / 10))
        .accessibilityHint("Turn to move the tape. Double-tap to return to the start.")
        .accessibilityAdjustableAction { direction in
            recorder.seek(to: recorder.position + (direction == .increment ? 1 : -1))
        }
    }

    private func scrub(center: CGPoint, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let dx = drag.location.x - center.x
                let dy = drag.location.y - center.y
                let angle = atan2(dy, dx)
                guard let previous = lastAngle else {
                    guard recorder.beginScrub() else { return }
                    lastAngle = angle
                    lastDetent = Int(recorder.position / detent)
                    held = true
                    Haptics.touch()
                    return
                }
                // Too close to the spindle, the angle is noise: hold, but do not turn.
                guard hypot(dx, dy) > radius * 0.14 else {
                    lastAngle = angle
                    return
                }
                var delta = angle - previous
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                lastAngle = angle
                recorder.scrub(bySeconds: delta / .pi)

                let position = recorder.position
                let step = Int(position / detent)
                if step != lastDetent {
                    let crossedSecond = Int(Double(step) * detent + 0.001) != Int(Double(lastDetent) * detent + 0.001) || step % 10 == 0
                    lastDetent = step
                    if position <= 0.01 {
                        Haptics.stop()
                    } else if crossedSecond {
                        Haptics.division()
                    } else {
                        Haptics.fine()
                    }
                }
            }
            .onEnded { _ in
                lastAngle = nil
                held = false
                recorder.endScrub()
            }
    }
}

/// What is printed on the platter: a ring of ticks, one groove, and the index mark.
private struct DialFace: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2
            for index in 0..<60 {
                let major = index.isMultiple(of: 5)
                let angle = Double(index) / 60 * 2 * .pi
                let outer = radius * 0.925
                let inner = outer - radius * (major ? 0.075 : 0.0375)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                tick.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                context.stroke(tick, with: .color(Palette.inkSecondary.opacity(major ? 0.8 : 0.35)), lineWidth: 1)
            }
            let groove = radius * 0.56
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - groove, y: center.y - groove, width: groove * 2, height: groove * 2)),
                with: .color(Palette.hairline), lineWidth: 1
            )
            let dot = max(8, radius * 0.06)
            let mark = CGRect(x: center.x - dot / 2, y: center.y - radius * 0.79 - dot / 2, width: dot, height: dot)
            context.fill(Path(ellipseIn: mark), with: .color(Palette.signal))
        }
    }
}

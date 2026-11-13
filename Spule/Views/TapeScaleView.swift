import SwiftUI
import GridKit
import TapeEngine

/// The tape drawn as a tuning scale: time ticks, one lane per track showing how far it is
/// recorded, cue marks, the loop region and the playhead needle.
/// Touch or drag anywhere to move the tape there; touches land on nearby cues.
struct TapeScaleView: View {
    @Environment(Recorder.self) private var recorder
    @State private var dragging = false

    @Environment(\.metrics) private var metrics
    var height: CGFloat?
    private let inset = Rhythm.u(4)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                let span = Self.span(content: recorder.core.contentSeconds, position: recorder.position)
                Canvas { context, size in
                    draw(&context, size: size, span: span)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let span = Self.span(content: recorder.core.contentSeconds, position: recorder.position)
                        let width = geo.size.width - 2 * inset
                        var seconds = Double((drag.location.x - inset) / width) * span
                        if let cue = ([0] + recorder.tape.cues).min(by: { abs($0 - seconds) < abs($1 - seconds) }),
                           abs(cue - seconds) / span * width < 10 {
                            seconds = cue
                        }
                        if !dragging {
                            dragging = true
                            Haptics.touch()
                        }
                        recorder.seek(to: min(max(seconds, 0), span))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: height ?? metrics.scale)
        .background(Palette.recess, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Tape scale")
        .accessibilityValue(DisplayView.counter(Double(recorder.positionTenths) / 10))
        .accessibilityAdjustableAction { direction in
            recorder.seek(to: recorder.position + (direction == .increment ? 1 : -1))
        }
    }

    /// Seconds of tape the scale shows: whole minutes, at least one, enough for content and playhead.
    static func span(content: Double, position: Double) -> Double {
        let needed = max(content + 10, position + 1)
        return min(360, max(60, (needed / 60).rounded(.up) * 60))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, span: Double) {
        let width = size.width - 2 * inset
        func x(_ seconds: Double) -> CGFloat { inset + CGFloat(seconds / span) * width }
        func line(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ color: Color, _ lineWidth: CGFloat = 1) {
            var path = Path()
            path.move(to: CGPoint(x: x, y: y0))
            path.addLine(to: CGPoint(x: x, y: y1))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }

        // Loop region, behind everything.
        if let start = recorder.tape.loopIn {
            if let end = recorder.tape.loopOut {
                let band = CGRect(x: x(start), y: 0, width: x(end) - x(start), height: size.height)
                context.fill(Path(band), with: .color(Palette.lamp.opacity(0.22)))
                line(x(end), 0, size.height, Palette.lamp)
            }
            line(x(start), 0, size.height, Palette.lamp)
        }

        // Track lanes.
        let rate = recorder.core.sampleRate
        for track in 0..<TapeCore.trackCount {
            let seconds = Double(recorder.core.length(ofTrack: track)) / rate
            guard seconds > 0 else { continue }
            let armed = recorder.transport == .recording && recorder.selectedTrack == track
            let lane = CGRect(x: inset, y: Rhythm.u(2) + CGFloat(track) * (metrics.large ? 6 : 4), width: max(2, x(seconds) - inset), height: metrics.large ? 3 : 2)
            let color = armed ? Palette.signal : track == recorder.selectedTrack ? Palette.ink : Palette.inkSecondary.opacity(0.6)
            context.fill(Path(roundedRect: lane, cornerRadius: 1), with: .color(color))
        }

        // Time ticks and numerals.
        let (minor, major): (Double, Double) = span <= 60 ? (1, 10) : span <= 180 ? (5, 30) : (10, 60)
        var tick = 0.0
        while tick <= span + 0.001 {
            let isMajor = tick.truncatingRemainder(dividingBy: major) < 0.001
            line(x(tick), size.height - (isMajor ? 12 : 8), size.height - 4, Palette.inkSecondary.opacity(isMajor ? 0.9 : 0.45))
            if isMajor, tick < span {
                let label = Text(String(format: "%d:%02d", Int(tick) / 60, Int(tick) % 60))
                    .font(Typo.scale(large: metrics.large))
                    .foregroundStyle(Palette.inkSecondary)
                context.draw(label, at: CGPoint(x: x(tick) + 3, y: size.height - 9), anchor: .bottomLeading)
            }
            tick += minor
        }

        // Cue marks.
        for cue in recorder.tape.cues where cue <= span {
            var mark = Path()
            mark.move(to: CGPoint(x: x(cue) - 3, y: 0))
            mark.addLine(to: CGPoint(x: x(cue) + 3, y: 0))
            mark.addLine(to: CGPoint(x: x(cue), y: 5))
            mark.closeSubpath()
            context.fill(mark, with: .color(Palette.ink))
        }

        // Playhead needle.
        line(x(min(recorder.position, span)), 0, size.height, Palette.signal, 1.5)
    }
}

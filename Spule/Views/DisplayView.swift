import SwiftUI
import GridKit

/// The display window: tape counter, transport state, level, and the tape's settings.
/// Swipe sideways across it to step between cues.
struct DisplayView: View {
    @Environment(Recorder.self) private var recorder

    @Environment(\.metrics) private var metrics
    /// Defaults to the height the faceplate's size calls for.
    var height: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                    Text(Self.counter(recorder.position))
                        .faceType(.counter)
                        .foregroundStyle(Palette.displayInk)
                }
                .accessibilityLabel("Tape position")
                .accessibilityValue(Self.counter(recorder.position))
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: Rhythm.u(2)) {
                    status
                    DotMeter(level: recorder.transport == .recording ? recorder.levels.input : recorder.levels.output)
                }
                .padding(.top, Rhythm.u(1))
            }
            Spacer(minLength: Rhythm.u(2))
            HStack(spacing: Rhythm.u(3)) {
                Text(recorder.tape.name)
                    .foregroundStyle(Palette.displayInk)
                Spacer(minLength: 0)
                Text("\(Int(recorder.tape.bpm)) bpm")
                    .foregroundStyle(recorder.tape.click ? Palette.displayInk : Palette.displayDim)
                Text(String(format: "%.2f×", recorder.tape.speed))
                    .foregroundStyle(recorder.tape.speed == 1 ? Palette.displayDim : Palette.displayInk)
            }
            .faceType(.caption)
        }
        .padding(metrics.displayInset)
        .frame(height: height ?? metrics.display)
        .background(Palette.glass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { GlassGlare().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                recorder.jumpCue(drag.translation.width < 0 ? 1 : -1)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("display")
        .accessibilityAction(named: "Next cue") { recorder.jumpCue(1) }
        .accessibilityAction(named: "Previous cue") { recorder.jumpCue(-1) }
    }

    private var status: some View {
        let recording = recorder.transport == .recording
        let word = recorder.readout ?? {
            switch recorder.transport {
            case .recording: "Rec \(recorder.selectedTrack + 1)".uppercased()
            case .playing: "PLAY"
            case .stopped: recorder.isBusy ? "LOADING" : "STOP"
            }
        }()
        return HStack(spacing: Rhythm.u(1.5)) {
            if recording && recorder.readout == nil {
                Circle().fill(Palette.signal).frame(width: 8, height: 8)
            }
            Text(word)
                .faceType(.status)
                .foregroundStyle(recording ? Palette.signal : Palette.displayInk)
                .contentTransition(.opacity)
        }
        .animation(Motion.readout, value: word)
    }

    /// Minutes, seconds, hundredths.
    static func counter(_ seconds: Double) -> String {
        let hundredths = Int((max(seconds, 0) * 100).rounded(.down))
        return String(format: "%d:%02d.%02d", hundredths / 6000, hundredths / 100 % 60, hundredths % 100)
    }
}

/// A level meter as a row of perforations, after a speaker grille. The last three run hot.
struct DotMeter: View {
    var level: Float
    @Environment(\.metrics) private var metrics
    private let count = 16

    var body: some View {
        let lit = Int((meterPosition(level) * Double(count)).rounded())
        HStack(spacing: metrics.meterDot) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index < lit ? (index >= count - 3 ? Palette.signal : Palette.displayInk) : Palette.displayDim.opacity(0.35))
                    .frame(width: metrics.meterDot, height: metrics.meterDot)
            }
        }
        .frame(height: Rhythm.u(2))
        .accessibilityHidden(true)
    }
}

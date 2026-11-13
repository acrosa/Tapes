import SwiftUI
import GridKit

/// The display window: tape counter, transport state, level, and the tape's settings.
/// Swipe sideways across it to step between cues.
struct DisplayView: View {
    @Environment(Recorder.self) private var recorder

    var height = Rhythm.u(26)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                    Text(Self.counter(recorder.position))
                        .rhythm(Typo.counter)
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
            .rhythm(Typo.caption)
        }
        .padding(Rhythm.u(4))
        .frame(height: height)
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
                .rhythm(Typo.status)
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
    private let count = 16

    var body: some View {
        let lit = Int((meterPosition(level) * Double(count)).rounded())
        HStack(spacing: Rhythm.u(1)) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index < lit ? (index >= count - 3 ? Palette.signal : Palette.displayInk) : Palette.displayDim.opacity(0.35))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: Rhythm.u(2))
        .accessibilityHidden(true)
    }
}

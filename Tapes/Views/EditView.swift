import SwiftUI
import GridKit
import TapeEngine

/// The bed under the faceplate, where the tape is cut. Dark glass from edge to edge: two words,
/// the four tracks as lanes of a timeline, and four keys.
///
/// The playhead stands still and the tape is dragged beneath it. `cut` divides the piece under the
/// playhead. Touch a piece to pick it up, then drag it along the tape or remove it. Touch another
/// track's lane to cut that track instead; `all` cuts the four together.
struct EditView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.metrics) private var faceMetrics
    @AppStorage("showsGrid") private var showsGrid = false

    var body: some View {
        // The larger build is the tablet's; a phone on its side keeps the phone's sizes.
        let metrics = heightClass == .compact ? Metrics() : faceMetrics
        GridContainer(showsOverlay: showsGrid, compactHeight: heightClass == .compact) { grid in
            GeometryReader { geo in
                let pad = heightClass == .compact ? Rhythm.u(2) : metrics.large ? Rhythm.u(6) : Rhythm.u(2)
                let band = Fold.band(in: geo)
                let across = band.flatMap { $0.width > $0.height ? $0 : nil }
                let down = band.flatMap { $0.height > $0.width ? $0 : nil }
                // Where the lanes begin, so a fold across the screen can be found among them.
                let lanesTop = pad + metrics.header + metrics.gap
                // A fold down the screen parts the keys; the playhead stands in the middle of the left side.
                let left = down?.minX ?? (geo.size.width - grid.gutter) / 2
                let gap = down?.width ?? grid.gutter
                VStack(spacing: metrics.gap) {
                    EditHeader().gridChecked()
                    TimelineLanes(
                        needle: down.map { $0.minX / 2 },
                        fold: across.map { ($0.minY - lanesTop)...($0.maxY - lanesTop) }
                    )
                    .gridChecked()
                    HStack(spacing: gap) {
                        GridContainer(grid: Fold.grid(columns: grid.columns / 2, width: left)) { _ in
                            EditKeys(side: .cutting)
                        }
                        .frame(width: left)
                        GridContainer(grid: Fold.grid(columns: grid.columns / 2, width: geo.size.width - left - gap)) { _ in
                            EditKeys(side: .playing)
                        }
                    }
                    .frame(height: metrics.transport)
                    .padding(.top, metrics.sectionLead)
                }
                .frame(width: geo.size.width, height: Rhythm.snapDown(geo.size.height - 2 * pad, to: Rhythm.u(2)))
                .padding(.top, pad)
                .animation(reduceMotion ? nil : Motion.fold, value: band)
            }
        }
        .environment(\.metrics, metrics)
        .background(Palette.glass.ignoresSafeArea())
    }
}

// MARK: Header

/// Leave without keeping the cuts, the counter, keep them.
private struct EditHeader: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.metrics) private var metrics

    var body: some View {
        let word = recorder.readout
        HStack(spacing: 0) {
            Button("cancel") { recorder.endEdit(keeping: false) }
                .buttonStyle(TextKeyStyle(alignment: .leading, color: Palette.displayInk))
                .accessibilityHint("Puts the tape back as it was")
            Spacer(minLength: 0)
            Button("done") { recorder.endEdit(keeping: true) }
                .buttonStyle(TextKeyStyle(alignment: .trailing, color: Palette.displayInk))
                .accessibilityHint("Keeps the cuts")
        }
        .frame(height: metrics.header)
        .overlay {
            // The counter, or for a moment the word for what was just done.
            TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                Text(word ?? DisplayView.counter(recorder.position))
                    .faceType(.status)
                    .foregroundStyle(Palette.displayInk)
            }
            .contentTransition(.opacity)
            .animation(Motion.readout, value: word)
            .accessibilityElement()
            .accessibilityIdentifier("edit-counter")
            .accessibilityLabel("Tape position")
            .accessibilityValue(DisplayView.counter(Double(recorder.positionHundredths) / 100))
        }
    }
}

// MARK: Timeline

/// The four tracks as lanes, a fixed length of screen to the second, passing under the playhead.
/// The lanes being cut show their pieces; the others show their sound, dimmer, to place a piece
/// against.
///
/// Drag anywhere to move the tape. Touch a piece to pick it up; drag a picked-up piece to move it.
/// Where it is laid over the end of another, the two fade across. Touch a dim lane to cut that track.
struct TimelineLanes: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.metrics) private var metrics
    /// Where the playhead stands, from the leading edge. Nil is the middle.
    var needle: CGFloat?
    /// A band across the lanes to keep clear (a fold): two lanes above it, two below.
    var fold: ClosedRange<CGFloat>?

    /// Points of screen per second of tape: 48, or 72 where the faceplate is built larger.
    private var pointsPerSecond: CGFloat { metrics.large ? Rhythm.u(18) : Rhythm.u(12) }
    private let ticks = Rhythm.u(4)
    private let between = Rhythm.u(2)

    private enum Hold {
        case waiting                        // a finger is down and has not moved yet
        case tape(last: CGFloat)            // dragging the tape
        case piece(id: Int, origin: Int)    // dragging a piece that started at `origin`
    }
    @State private var hold: Hold?

    var body: some View {
        let session = recorder.edit
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 60)) { _ in
                Canvas { context, size in
                    if let session { draw(&context, size: size, session: session) }
                }
            }
            .contentShape(Rectangle())
            .gesture(touch(size: geo.size))
        }
        .accessibilityElement()
        .accessibilityIdentifier("splice")
        .accessibilityLabel("Pieces of tape")
        .accessibilityValue(spoken(session))
        .accessibilityAdjustableAction { recorder.editStep($0 == .increment ? 1 : -1) }
        .accessibilityAction(named: "Move piece earlier") { recorder.editNudge(-0.1) }
        .accessibilityAction(named: "Move piece later") { recorder.editNudge(0.1) }
        .accessibilityAction(named: "Tape back one second") { recorder.seek(to: recorder.position - 1) }
        .accessibilityAction(named: "Tape forward one second") { recorder.seek(to: recorder.position + 1) }
    }

    private func spoken(_ session: EditSession?) -> String {
        guard let session else { return "" }
        let count = session.splice.pieces.count
        let ordered = session.splice.pieces.sorted { $0.start < $1.start }
        let picked = ordered.firstIndex { $0.id == session.selected }.map {
            ", piece \($0 + 1) picked up at \(DisplayView.counter(Double(ordered[$0].start) / recorder.core.sampleRate))"
        } ?? ""
        return "\(count) \(count == 1 ? "piece" : "pieces")\(picked)"
    }

    /// The four lanes, top to bottom, in a view of `size`. Their heights are whole units.
    private func lanes(in size: CGSize) -> [CGRect] {
        let count = TapeCore.trackCount
        let bottom = size.height - ticks
        if let fold, fold.lowerBound > 0, fold.upperBound < bottom {
            let above = Rhythm.snapDown((fold.lowerBound - between) / 2)
            let below = Rhythm.snapDown((bottom - fold.upperBound - between) / 2)
            let lower = Rhythm.snapDown(fold.upperBound) + Rhythm.unit
            return [
                CGRect(x: 0, y: 0, width: size.width, height: above),
                CGRect(x: 0, y: above + between, width: size.width, height: above),
                CGRect(x: 0, y: lower, width: size.width, height: below),
                CGRect(x: 0, y: lower + below + between, width: size.width, height: below)
            ]
        }
        let height = Rhythm.snapDown((bottom - CGFloat(count - 1) * between) / CGFloat(count))
        return (0..<count).map { CGRect(x: 0, y: CGFloat($0) * (height + between), width: size.width, height: height) }
    }

    private func frame(at x: CGFloat, width: CGFloat) -> Int {
        Int(recorder.core.positionFrames + Double((x - (needle ?? width / 2)) / pointsPerSecond) * recorder.core.sampleRate)
    }

    private func track(at y: CGFloat, size: CGSize) -> Int? {
        lanes(in: size).firstIndex { $0.minY - between / 2 <= y && y < $0.maxY + between / 2 }
    }

    /// The piece under a touch, if the touch is on a lane that is being cut.
    private func piece(at point: CGPoint, size: CGSize) -> Piece? {
        guard let session = recorder.edit, let t = track(at: point.y, size: size), session.scope.tracks.contains(t) else { return nil }
        return session.splice.piece(at: frame(at: point.x, width: size.width))
    }

    private func touch(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let rate = recorder.core.sampleRate
                switch hold {
                case nil:
                    // A finger landing on the picked-up piece takes hold of it; anywhere else, of the tape.
                    if let under = piece(at: drag.startLocation, size: size), under.id == recorder.edit?.selected {
                        hold = .piece(id: under.id, origin: under.start)
                        Haptics.touch()
                    } else {
                        hold = .waiting
                    }
                case .waiting:
                    guard abs(drag.translation.width) > 6, recorder.beginScrub() else { return }
                    hold = .tape(last: drag.translation.width)
                case .tape(let last):
                    recorder.scrub(bySeconds: -Double((drag.translation.width - last) / pointsPerSecond))
                    hold = .tape(last: drag.translation.width)
                case .piece(let id, let origin):
                    let moved = Int(Double(drag.translation.width / pointsPerSecond) * rate)
                    recorder.editMove(id, to: origin + moved, reach: Int(Double(Rhythm.u(2) / pointsPerSecond) * rate))
                }
            }
            .onEnded { drag in
                switch hold {
                case .waiting:
                    // A touch that did not move. On a lane that is not being cut: cut that track.
                    // Otherwise pick up what is under it, or put down what was held.
                    if let t = track(at: drag.location.y, size: size), let session = recorder.edit, !session.scope.tracks.contains(t) {
                        recorder.setEditScope(.track(t))
                    } else {
                        let under = piece(at: drag.location, size: size)
                        recorder.editSelect(under?.id == recorder.edit?.selected ? nil : under?.id)
                    }
                case .tape: recorder.endScrub()
                case .piece: recorder.editDrop()
                case nil: break
                }
                hold = nil
            }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, session: EditSession) {
        let rate = recorder.core.sampleRate
        let position = recorder.core.positionFrames
        let scale = Double(pointsPerSecond) / rate              // points per frame
        let middle = needle ?? size.width / 2
        let bin = Double(recorder.editBin)
        func x(_ frame: Double) -> CGFloat { middle + CGFloat((frame - position) * scale) }

        // Seconds along the bottom, a longer tick every five.
        let first = max(0, Int(((position - Double(middle) / scale) / rate).rounded(.up)))
        let last = Int((position + Double(size.width - middle) / scale) / rate)
        if first <= last {
            for second in first...last {
                let long = second.isMultiple(of: 5)
                var tick = Path()
                tick.move(to: CGPoint(x: x(Double(second) * rate), y: size.height - (long ? Rhythm.u(2) : Rhythm.u(1))))
                tick.addLine(to: CGPoint(x: x(Double(second) * rate), y: size.height))
                context.stroke(tick, with: .color(Palette.displayDim), lineWidth: 1)
            }
        }

        /// The outline of `count` frames of track `t` from `source`, drawn in `rect`.
        func wave(_ t: Int, source: Int, in rect: CGRect, opacity: Double) {
            let peaks = session.peaks[t]
            var path = Path()
            var column = max(rect.minX, 0).rounded(.up)
            while column < min(rect.maxX, size.width) {
                let index = Int((Double(source) + Double(column - rect.minX) / scale) / bin)
                let peak = index >= 0 && index < peaks.count ? CGFloat(min(peaks[index], 1)) : 0
                let half = max(0.5, peak.squareRoot() * (rect.height / 2 - Rhythm.u(1)))
                path.move(to: CGPoint(x: column, y: rect.midY - half))
                path.addLine(to: CGPoint(x: column, y: rect.midY + half))
                column += 2
            }
            context.stroke(path, with: .color(Palette.displayInk.opacity(opacity)), lineWidth: 1)
        }

        for (t, lane) in lanes(in: size).enumerated() {
            let cutting = session.scope.tracks.contains(t)
            // The lane itself: a faint bed the length of the screen.
            context.fill(Path(roundedRect: lane, cornerRadius: 8, style: .continuous), with: .color(Palette.displayInk.opacity(cutting ? 0.06 : 0.03)))
            if cutting {
                for piece in session.splice.pieces {
                    let picked = piece.id == session.selected
                    let rect = CGRect(x: x(Double(piece.start)), y: lane.minY, width: CGFloat(Double(piece.count) * scale), height: lane.height)
                    guard rect.maxX > 0, rect.minX < size.width else { continue }
                    // A hair of glass shows between pieces that touch, so a cut can be seen.
                    let body = Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0), cornerRadius: 6, style: .continuous)
                    context.fill(body, with: .color(Palette.displayInk.opacity(picked ? 0.26 : 0.12)))
                    if picked { context.stroke(body, with: .color(Palette.displayInk), lineWidth: 1) }
                    wave(t, source: piece.source.lowerBound, in: rect, opacity: picked ? 1 : 0.75)
                }
            } else {
                let length = recorder.core.length(ofTrack: t)
                let rect = CGRect(x: x(0), y: lane.minY, width: CGFloat(Double(length) * scale), height: lane.height)
                if length > 0, rect.maxX > 0, rect.minX < size.width { wave(t, source: 0, in: rect, opacity: 0.3) }
            }
            let number = context.resolve(
                Text("\(t + 1)")
                    .font(Typo.scale(large: metrics.large))
                    .foregroundStyle(cutting ? Palette.displayInk : Palette.displayDim)
            )
            context.draw(number, at: CGPoint(x: Rhythm.u(2), y: lane.minY + Rhythm.u(1.5)), anchor: .topLeading)
        }

        var line = Path()
        line.move(to: CGPoint(x: middle, y: 0))
        line.addLine(to: CGPoint(x: middle, y: size.height))
        context.stroke(line, with: .color(Palette.signal), lineWidth: 1.5)
    }
}

// MARK: Keys

/// Four keys in two pairs: cut and remove, then all and play. They stand in pairs so a fold down
/// the screen can pass between them.
private struct EditKeys: View {
    enum Side { case cutting, playing }

    @Environment(Recorder.self) private var recorder
    @Environment(\.columnGrid) private var grid
    @Environment(\.metrics) private var metrics
    let side: Side

    var body: some View {
        let rolling = recorder.transport != .stopped
        let picked = recorder.edit?.selected != nil
        let all = recorder.edit?.scope == .all
        UnitRow(units: [1, 1], spacing: grid.gutter) {
            if side == .cutting {
                Button { recorder.editCut() } label: {
                    Image(systemName: "scissors")
                        .font(.system(size: metrics.glyph + 1))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(KeyStyle())
                .gridChecked()
                .accessibilityLabel("Cut")
                .accessibilityHint("Divides the piece under the playhead")

                Button { recorder.editRemove() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: metrics.glyph, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(picked ? 1 : 0.3))
                        .animation(Motion.lamp, value: picked)
                }
                .buttonStyle(KeyStyle())
                .gridChecked()
                .accessibilityLabel("Remove piece")
                .accessibilityHint("Takes the picked-up piece off the tape and leaves the gap")
            } else {
                Button { recorder.toggleEditAll() } label: {
                    Text("all").faceType(.numeral).foregroundStyle(Palette.ink)
                }
                .buttonStyle(KeyStyle())
                .overlay(alignment: .top) {
                    Lamp(on: all).padding(.top, Rhythm.u(2)).allowsHitTesting(false)
                }
                .gridChecked()
                .accessibilityLabel("all")
                .accessibilityValue(all ? "on" : "off")
                .accessibilityHint("Cuts all four tracks together")

                Button { recorder.togglePlay() } label: {
                    Image(systemName: rolling ? "stop.fill" : "play.fill")
                        .font(.system(size: metrics.glyph + 1))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(KeyStyle())
                .gridChecked()
                .accessibilityLabel(rolling ? "Stop" : "Play")
            }
        }
    }
}

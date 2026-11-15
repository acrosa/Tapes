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
                // A fold down the screen parts the keys. The timeline runs across it.
                let left = down?.minX ?? (geo.size.width - grid.gutter) / 2
                let gap = down?.width ?? grid.gutter
                VStack(spacing: metrics.gap) {
                    EditHeader().gridChecked()
                    TimelineLanes(fold: across.map { ($0.minY - lanesTop)...($0.maxY - lanesTop) })
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

/// The four tracks as lanes, a fixed length of screen to the second. The tape lies still and the
/// playhead travels along it; when it nears the edge the view moves on to keep it in sight.
/// The lanes being cut show their pieces; the others show their sound, dimmer, to place a piece
/// against.
///
/// Touch the tape to put the playhead there (and pick up the piece under it). Drag to look along
/// the tape. Drag a picked-up piece to move it; where it is laid over the end of another, the two
/// fade across. Touch a dim lane to cut that track.
struct TimelineLanes: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A band across the lanes to keep clear (a fold): two lanes above it, two below.
    var fold: ClosedRange<CGFloat>?

    /// Points of screen per second of tape. It opens at 48 (72 where the faceplate is built
    /// larger); a pinch changes it, and the choice is kept while the app runs.
    private var pointsPerSecond: CGFloat { zoom ?? (metrics.large ? Rhythm.u(18) : Rhythm.u(12)) }
    @State private var zoom = TimelineLanes.lastZoom
    @MainActor private static var lastZoom: CGFloat?
    /// The closest view: a tenth of a second is 48 points.
    private let closest: CGFloat = 480
    /// What a pinch began from: the scale, and the second of tape under the fingers.
    @State private var pinch: (scale: CGFloat, second: Double)?
    /// When a pinch last moved. For a moment after, fingers on the glass are still the pinch, not
    /// a touch or a drag. (The pinch's own ending is not relied on: it does not always arrive.)
    @State private var pinchMoved = Date.distantPast
    private var pinching: Bool { Date().timeIntervalSince(pinchMoved) < 0.3 }
    private let ticks = Rhythm.u(4)
    private let between = Rhythm.u(2)
    /// Clear lane before the start of the tape, so the first piece is not under the lane's number.
    private let lead = Rhythm.u(8)

    private enum Hold {
        case waiting                            // a finger is down and has not moved yet
        case view(from: Double)                 // dragging the view, which began at this second
        case piece(id: Int, origin: Int)        // dragging a piece that started at `origin`
    }
    @State private var hold: Hold?
    /// The second of tape at the leading edge, and the glide between two such values.
    @State private var glide = Glide(to: 0)

    private struct Glide {
        var from: Double
        var to: Double
        var began: Date

        init(to: Double) {
            from = to
            self.to = to
            began = .distantPast
        }

        func value(at date: Date) -> Double {
            let t = min(max(date.timeIntervalSince(began) / Glide.time, 0), 1)
            let eased = 1 - pow(1 - t, 3)
            return from + (to - from) * eased
        }

        /// Seconds the view takes to move on.
        static let time = 0.35
    }

    var body: some View {
        let session = recorder.edit
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                Canvas { context, size in
                    if let session { draw(&context, size: size, session: session, left: glide.value(at: timeline.date)) }
                }
            }
            .contentShape(Rectangle())
            .gesture(touch(size: geo.size))
            .simultaneousGesture(magnify(width: geo.size.width))
            .onAppear { look(at: recorder.position, width: geo.size.width, glides: false) }
            // The playhead is watched in tenths of a second: often enough to keep it in sight.
            .onChange(of: recorder.positionTenths) { keepInSight(width: geo.size.width) }
            .onChange(of: geo.size.width) { look(at: recorder.position, width: geo.size.width, glides: false) }
        }
        .accessibilityElement()
        .accessibilityIdentifier("splice")
        .accessibilityLabel("Pieces of tape")
        .accessibilityValue(spoken(session))
        .accessibilityAdjustableAction { recorder.editStep($0 == .increment ? 1 : -1) }
        .accessibilityAction(named: "Move piece earlier") { recorder.editNudge(-0.1) }
        .accessibilityAction(named: "Move piece later") { recorder.editNudge(0.1) }
        .accessibilityAction(named: "Playhead back one second") { recorder.seek(to: recorder.position - 1) }
        .accessibilityAction(named: "Playhead forward one second") { recorder.seek(to: recorder.position + 1) }
    }

    // MARK: The view along the tape

    /// The earliest and latest second the leading edge may show.
    private func limits(width: CGFloat) -> ClosedRange<Double> {
        let first = -Double(lead / pointsPerSecond)
        let shown = Double(width / pointsPerSecond)
        let end = max(recorder.core.contentSeconds, Double(recorder.edit?.splice.end ?? 0) / recorder.core.sampleRate)
        return first...max(first, end - shown / 2)
    }

    private func move(to second: Double, width: CGFloat, glides: Bool) {
        let range = limits(width: width)
        let target = min(max(second, range.lowerBound), range.upperBound)
        let now = Date()
        if glides, !reduceMotion {
            glide = { var g = Glide(to: target); g.from = glide.value(at: now); g.began = now; return g }()
        } else {
            glide = Glide(to: target)
        }
    }

    /// Shows `second` a quarter of the way along.
    private func look(at second: Double, width: CGFloat, glides: Bool) {
        let shown = Double(width / pointsPerSecond)
        // A tape that fits is shown from its start.
        let fits = recorder.core.contentSeconds + Double(lead / pointsPerSecond) <= shown
        move(to: fits ? -.infinity : second - shown / 4, width: width, glides: glides)
    }

    /// Moves the view on when the playhead has left it or is about to. Not while a finger is on it.
    private func keepInSight(width: CGFloat) {
        guard hold == nil else { return }
        let shown = Double(width / pointsPerSecond)
        let along = (recorder.position - glide.to) / shown
        let playing = recorder.transport == .playing
        if along < 0 || along > 1 || (playing && along > 0.9) { look(at: recorder.position, width: width, glides: true) }
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

    private func seconds(at x: CGFloat) -> Double {
        glide.value(at: Date()) + Double(x / pointsPerSecond)
    }

    private func frame(at x: CGFloat) -> Int { Int(seconds(at: x) * recorder.core.sampleRate) }

    private func track(at y: CGFloat, size: CGSize) -> Int? {
        lanes(in: size).firstIndex { $0.minY - between / 2 <= y && y < $0.maxY + between / 2 }
    }

    /// The piece under a touch, if the touch is on a lane that is being cut.
    private func piece(at point: CGPoint, size: CGSize) -> Piece? {
        guard let session = recorder.edit, let t = track(at: point.y, size: size), session.scope.tracks.contains(t) else { return nil }
        return session.splice.piece(at: frame(at: point.x))
    }

    /// Pinch to see more of the tape or less. The second under the fingers stays under them.
    /// The furthest view shows the whole recording with a little to spare.
    private func magnify(width: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                if pinch == nil || !pinching {
                    pinch = (pointsPerSecond, seconds(at: value.startLocation.x))
                    // Two fingers are not a touch or a drag: let go of whatever one finger began.
                    if case .piece = hold { recorder.editDrop() }
                    hold = nil
                }
                pinchMoved = Date()
                guard let pinch else { return }
                let furthest = max(1, (width - lead) / CGFloat(max(recorder.core.contentSeconds * 1.1, 4)))
                let scale = min(max(pinch.scale * value.magnification, min(furthest, closest)), closest)
                zoom = scale
                TimelineLanes.lastZoom = scale
                move(to: pinch.second - Double(value.startLocation.x / scale), width: width, glides: false)
            }
            .onEnded { _ in pinch = nil }
    }

    private func touch(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard !pinching else { return }
                let rate = recorder.core.sampleRate
                switch hold {
                case nil:
                    // A finger landing on the picked-up piece takes hold of it; anywhere else, of the view.
                    if let under = piece(at: drag.startLocation, size: size), under.id == recorder.edit?.selected {
                        hold = .piece(id: under.id, origin: under.start)
                        Haptics.touch()
                    } else {
                        hold = .waiting
                    }
                case .waiting:
                    guard abs(drag.translation.width) > 6 else { return }
                    hold = .view(from: glide.value(at: Date()) + Double(drag.translation.width / pointsPerSecond))
                case .view(let from):
                    move(to: from - Double(drag.translation.width / pointsPerSecond), width: size.width, glides: false)
                case .piece(let id, let origin):
                    let moved = Int(Double(drag.translation.width / pointsPerSecond) * rate)
                    recorder.editMove(id, to: origin + moved, reach: Int(Double(Rhythm.u(2) / pointsPerSecond) * rate))
                }
            }
            .onEnded { drag in
                defer { hold = nil }
                guard !pinching else { return }
                switch hold {
                case .waiting:
                    // A touch that did not move puts the playhead there. On a lane that is not being
                    // cut it also turns to that track; otherwise it picks up the piece under it.
                    recorder.seek(to: max(0, seconds(at: drag.location.x)))
                    if let t = track(at: drag.location.y, size: size), let session = recorder.edit, !session.scope.tracks.contains(t) {
                        recorder.setEditScope(.track(t))
                    } else {
                        recorder.editSelect(piece(at: drag.location, size: size)?.id)
                    }
                case .piece:
                    recorder.editDrop()
                    // A touch on the picked-up piece that did not move it still places the playhead.
                    if abs(drag.translation.width) < 6 { recorder.seek(to: max(0, seconds(at: drag.location.x))) }
                case .view, nil: break
                }
            }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, session: EditSession, left: Double) {
        let rate = recorder.core.sampleRate
        let position = recorder.core.positionFrames
        let scale = Double(pointsPerSecond) / rate              // points per frame
        let bin = Double(recorder.editBin)
        func x(_ frame: Double) -> CGFloat { CGFloat((frame - left * rate) * scale) }

        // The ruler along the bottom. Its divisions follow the scale, so marks are never crowded:
        // a mark at least every 8 points, a longer one with the time at least every 64.
        let steps: [Double] = [0.1, 0.5, 1, 5, 10, 30, 60]
        let minor = steps.first { CGFloat($0) * pointsPerSecond >= Rhythm.u(2) } ?? 60
        let major = steps.first { $0 > minor && CGFloat($0) * pointsPerSecond >= Rhythm.u(16) } ?? 120
        let shown = Double(size.width / pointsPerSecond)
        let firstMark = max(0, Int((left / minor).rounded(.up)))
        let lastMark = Int((left + shown) / minor)
        if firstMark <= lastMark {
            for mark in firstMark...lastMark {
                let second = Double(mark) * minor
                let long = (second / major).rounded() * major == (second * 10).rounded() / 10
                let at = x(second * rate)
                var tick = Path()
                tick.move(to: CGPoint(x: at, y: size.height - (long ? Rhythm.u(2) : Rhythm.u(1))))
                tick.addLine(to: CGPoint(x: at, y: size.height))
                context.stroke(tick, with: .color(Palette.displayDim), lineWidth: 1)
                if long {
                    let whole = Int(second)
                    let tenths = Int((second * 10).rounded()) % 10
                    let text = major < 1 ? String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths) : String(format: "%d:%02d", whole / 60, whole % 60)
                    let label = context.resolve(Text(text).font(Typo.scale(large: metrics.large)).foregroundStyle(Palette.displayDim))
                    context.draw(label, at: CGPoint(x: at + 3, y: size.height - 6), anchor: .bottomLeading)
                }
            }
        }

        /// The outline of `count` frames of track `t` from `source`, drawn in `rect`.
        func wave(_ t: Int, source: Int, in rect: CGRect, opacity: Double) {
            let peaks = session.peaks[t]
            var path = Path()
            var column = max(rect.minX, 0).rounded(.up)
            while column < min(rect.maxX, size.width) {
                // The loudest of the bins this column covers, so a far view loses no peaks.
                let index = Int((Double(source) + Double(column - rect.minX) / scale) / bin)
                let next = Int((Double(source) + Double(column + 2 - rect.minX) / scale) / bin)
                var loudest: Float = 0
                if index >= 0, index < peaks.count {
                    for i in index..<min(max(next, index + 1), peaks.count) { loudest = max(loudest, peaks[i]) }
                }
                let peak = CGFloat(min(loudest, 1))
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
        line.move(to: CGPoint(x: x(position), y: 0))
        line.addLine(to: CGPoint(x: x(position), y: size.height))
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
                    Text("ALL").faceType(.status).foregroundStyle(Palette.ink)
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

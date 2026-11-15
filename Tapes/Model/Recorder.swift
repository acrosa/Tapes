import ActivityKit
import SwiftUI
import TapeEngine

struct Levels: Equatable {
    var tracks = [Float](repeating: 0, count: TapeCore.trackCount)
    var output: Float = 0
    var input: Float = 0
}

/// What an edit cuts: one track, or all four as one tape.
enum EditScope: Hashable {
    case track(Int)
    case all

    var tracks: [Int] {
        switch self {
        case .track(let t): [t]
        case .all: Array(0..<TapeCore.trackCount)
        }
    }
}

/// An edit in progress: the pieces, which one is picked up, and the outline of each track (its
/// loudest sample every hundredth of a second): for a track being cut, of the sound the pieces
/// were cut from; for the others, of the track as it is.
struct EditSession: Equatable {
    var scope: EditScope
    var splice: Splice
    var selected: Int?
    var peaks: [[Float]]
}

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// The app's one model: the loaded tape, the transport, and every action a control can take.
/// Views read state from here and call these methods; nothing else talks to the engine.
@MainActor @Observable
final class Recorder {
    enum Transport { case stopped, playing, recording }

    private(set) var transport = Transport.stopped
    private(set) var tape: TapeMeta
    private(set) var tapes: [TapeMeta]
    private(set) var selectedTrack = 0
    /// A transient word shown in the display in place of the transport state.
    private(set) var readout: String?
    private(set) var levels = Levels()
    private(set) var isBusy = false
    /// The inputs on offer and the names of what is in use. Refreshed when devices come and go.
    private(set) var inputs: [AudioPort] = []
    private(set) var inputName: String?
    private(set) var outputName: String?
    /// The playhead in whole tenths of a second. The playhead itself is not observable (views
    /// read it once per frame); this is, so spoken values on the dial and scale stay current.
    private(set) var positionTenths = 0
    /// The same in hundredths, for the display's spoken value, which must match the counter.
    private(set) var positionHundredths = 0
    /// Bumped when routing changes, so views reading the stored choices redraw.
    private(set) var routeRevision = 0
    /// Set while the tape is being cut. The faceplate shows the edit controls instead.
    private(set) var edit: EditSession?
    var micDenied = false
    var exportItem: ExportItem?

    @ObservationIgnored private let io = AudioIO()
    @ObservationIgnored private var readoutTask: Task<Void, Never>?
    @ObservationIgnored private var metaSave: Task<Void, Never>?
    @ObservationIgnored private var audioSave: Task<Void, Never>?
    @ObservationIgnored private var wasScrubbing = false
    /// Tracks as they were when editing began (those an edit has changed), for cancel.
    @ObservationIgnored private var editOriginals: [Int: [Float]] = [:]
    /// What the pieces of the current scope are cut from.
    @ObservationIgnored private var editBase: [Int: [Float]] = [:]
    /// The single track last cut, for coming back from `all`.
    @ObservationIgnored private var editTrack = 0
    @ObservationIgnored private var liveActivityID: String?
    #if DEBUG
    @ObservationIgnored private var seeded = false
    #endif

    /// The tape itself. Views read the playhead from here once per frame.
    var core: TapeCore { io.core }

    static let speedRange = 0.25...4.0
    static let tempoRange = 40.0...240.0

    init() {
        #if DEBUG
        // `-resetTapes`: start from an empty shelf. Used by the end-to-end tests.
        if ProcessInfo.processInfo.arguments.contains("-resetTapes") {
            try? FileManager.default.removeItem(at: TapeStore.root)
        }
        #endif
        var all = TapeStore.list()
        if all.isEmpty {
            let first = TapeMeta(name: "Tape 01")
            TapeStore.save(first)
            all = [first]
        }
        tape = all[0]
        tapes = all
        io.start()
        io.onRouteChange = { [weak self] in
            Task { @MainActor in self?.refreshRoute() }
        }
        applyRouting()
        syncCore()
        Task.detached { await Self.endLiveActivities(id: nil) }
        Task { await self.loadAudio() }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.poll()
            }
        }
    }

    // MARK: Transport

    var position: Double { core.positionSeconds }

    func togglePlay() {
        switch transport {
        case .recording: finishRecording()
        case .playing:
            core.stop()
            transport = .stopped
        case .stopped:
            let end = core.contentSeconds
            if end > 0, position >= end - 0.02 { core.seek(toSeconds: tape.loopIn ?? 0) }
            core.play(rate: tape.speed)
            transport = .playing
        }
    }

    func toggleRecord() {
        guard edit == nil else { return refuse() }
        if transport == .recording {
            finishRecording()
            return
        }
        Task {
            guard await io.ensureInput() else {
                micDenied = true
                return
            }
            guard transport != .recording else { return }
            guard await io.setRecording(true) else {
                // Nothing to record from. Say so; do not roll a silent tape.
                _ = await io.setRecording(false)
                refuse()
                flash("No input")
                return
            }
            guard transport != .recording else { return }
            refreshRoute()
            core.beginRecording(track: selectedTrack, latencyFrames: io.roundTripLatencyFrames)
            transport = .recording
            startLiveActivity()
        }
    }

    private func finishRecording() {
        let track = selectedTrack
        core.endRecording()
        core.stop()
        transport = .stopped
        Task {
            _ = await io.setRecording(false)
            refreshRoute()
        }
        endLiveActivity()
        syncLoop()
        tape.duration = core.contentSeconds
        touch()
        saveAudio(track: track)
        flash("Saved to track \(track + 1)")
    }

    // MARK: Foreground and background

    /// With the tape at rest, the app stops all audio when it leaves the foreground and picks
    /// it up again on return. A tape that is playing or recording carries on.
    func enteredBackground() {
        guard transport == .stopped else { return }
        io.suspend()
    }

    func becameActive() {
        io.resume()
        refreshRoute()
    }

    // MARK: Sound in and out

    /// "" means automatic: iOS picks, preferring whatever was plugged in last.
    var inputChoice: String {
        get { UserDefaults.standard.string(forKey: "inputID") ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: "inputID")
            applyRouting()
        }
    }

    /// Play back through this device's speaker when a USB instrument is connected. While a take
    /// is being recorded the sound has to go through the instrument, so it applies between takes.
    var playsThroughSpeaker: Bool {
        get { UserDefaults.standard.object(forKey: "speakerOutput") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "speakerOutput")
            applyRouting()
        }
    }

    /// Pass the input through to the output so it can be heard.
    var hearsInput: Bool {
        get { UserDefaults.standard.bool(forKey: "hearInput") }
        set {
            UserDefaults.standard.set(newValue, forKey: "hearInput")
            applyRouting()
        }
    }

    private func applyRouting() {
        let choice = inputChoice
        io.setRouting(AudioRouting(inputID: choice.isEmpty ? nil : choice, speaker: playsThroughSpeaker, monitor: hearsInput))
        refreshRoute()
    }

    /// Asks for the microphone if it has not been asked yet, so the inputs can be listed.
    func prepareInputs() {
        Task {
            guard await io.ensureInput() else { return }
            applyRouting()
        }
    }

    private func refreshRoute() {
        inputs = io.inputs
        let names = io.routeNames
        inputName = names.input
        outputName = names.output
        routeRevision += 1
    }

    // MARK: Live Activity

    /// Shows the recording on the Lock Screen and in the Dynamic Island. Recording carries on
    /// when the app leaves the foreground (the audio background mode), and this is how it stays
    /// in sight. The counter there is a system timer, so nothing needs sending while it runs.
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RecordingAttributes.ContentState(track: selectedTrack + 1, tapeZero: Date().addingTimeInterval(-position))
        let activity = try? Activity.request(
            attributes: RecordingAttributes(tapeName: tape.name),
            content: ActivityContent(state: state, staleDate: nil)
        )
        liveActivityID = activity?.id
    }

    private func endLiveActivity() {
        guard let id = liveActivityID else { return }
        liveActivityID = nil
        Task.detached { await Self.endLiveActivities(id: id) }
    }

    /// Ends the activity with `id`, or every recording activity if `id` is nil: a recording
    /// that was cut short (the app was closed) leaves its activity behind.
    private nonisolated static func endLiveActivities(id: String?) async {
        for activity in Activity<RecordingAttributes>.activities where id == nil || activity.id == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func returnToStart() {
        guard transport != .recording else { return refuse() }
        core.seek(toSeconds: 0)
        flash("Start")
    }

    func seek(to seconds: Double) {
        guard transport != .recording else { return }
        core.seek(toSeconds: seconds)
    }

    // MARK: Dial

    /// False if the tape cannot be moved by hand right now (it is recording).
    func beginScrub() -> Bool {
        guard transport != .recording else {
            refuse()
            return false
        }
        core.beginScrub()
        wasScrubbing = true
        return true
    }

    func scrub(bySeconds seconds: Double) {
        guard wasScrubbing else { return }
        core.scrub(bySeconds: seconds)
    }

    func endScrub() {
        guard wasScrubbing else { return }
        wasScrubbing = false
        core.endScrub(resumeRate: transport == .playing ? tape.speed : 0)
    }

    // MARK: Tracks and mix

    func select(track: Int) {
        guard transport != .recording else { return refuse() }
        selectedTrack = track
        flash("Track \(track + 1)")
    }

    func setVolume(_ track: Int, _ value: Double) {
        var v = min(max(value, 0), 1)
        if abs(v - TrackMix.unity) < 0.02 { v = TrackMix.unity }
        guard v != tape.tracks[track].volume else { return }
        if v == TrackMix.unity || v == 0 || v == 1 { Haptics.snap() }
        tape.tracks[track].volume = v
        applyMix()
        flash("T\(track + 1) level \(Int((v / TrackMix.unity * 100).rounded()))")
    }

    func setPan(_ track: Int, _ value: Double) {
        var p = min(max(value, -1), 1)
        if abs(p) < 0.08 { p = 0 }
        guard p != tape.tracks[track].pan else { return }
        if p == 0 || abs(p) == 1 { Haptics.snap() }
        tape.tracks[track].pan = p
        applyMix()
        let amount = Int((abs(p) * 100).rounded())
        flash("T\(track + 1) pan " + (p == 0 ? "centre" : p < 0 ? "L\(amount)" : "R\(amount)"))
    }

    func toggleMute(_ track: Int) {
        tape.tracks[track].mute.toggle()
        applyMix()
        flash("T\(track + 1) " + (tape.tracks[track].mute ? "muted" : "on"))
    }

    func toggleSolo(_ track: Int) {
        tape.tracks[track].solo.toggle()
        applyMix()
        flash("T\(track + 1) " + (tape.tracks[track].solo ? "solo" : "solo off"))
    }

    func erase(track: Int) {
        guard transport != .recording else { return refuse() }
        core.erase(track: track)
        tape.duration = core.contentSeconds
        touch()
        saveAudio(track: track)
        flash("Track \(track + 1) erased")
    }

    func hasAudio(_ track: Int) -> Bool { core.length(ofTrack: track) > 0 }

    private func applyMix() {
        let anySolo = tape.tracks.contains(where: \.solo)
        for (index, mix) in tape.tracks.enumerated() {
            let audible = anySolo ? mix.solo : !mix.mute
            let gain = audible ? pow(mix.volume / TrackMix.unity, 2) : 0
            let angle = (mix.pan + 1) / 2 * .pi / 2
            // Equal power, normalised so centre is unity on both sides.
            core.setGain(track: index, left: Float(gain * cos(angle) * 2.0.squareRoot()), right: Float(gain * sin(angle) * 2.0.squareRoot()))
        }
        touch()
    }

    // MARK: Speed, tempo, click

    /// Tape speed on a 0…1 scale, logarithmic, with 1× at the centre.
    var speedPosition: Double {
        get { (log2(tape.speed) + 2) / 4 }
        set {
            var speed = pow(2, min(max(newValue, 0), 1) * 4 - 2)
            if abs(log2(speed)) < 0.07 { speed = 1 }
            guard speed != tape.speed else { return }
            if speed == 0.5 || speed == 1 || speed == 2 { Haptics.snap() }
            tape.speed = speed
            if transport == .playing { core.setRate(speed) }
            touch()
            flash(String(format: "Speed %.2f×", speed))
        }
    }

    /// Tempo on a 0…1 scale across `tempoRange`.
    var tempoPosition: Double {
        get { (tape.bpm - Self.tempoRange.lowerBound) / (Self.tempoRange.upperBound - Self.tempoRange.lowerBound) }
        set {
            let span = Self.tempoRange.upperBound - Self.tempoRange.lowerBound
            let bpm = (Self.tempoRange.lowerBound + min(max(newValue, 0), 1) * span).rounded()
            guard bpm != tape.bpm else { return }
            if bpm.truncatingRemainder(dividingBy: 10) == 0 { Haptics.snap() } else { Haptics.tick() }
            tape.bpm = bpm
            syncClick()
            touch()
            flash("Tempo \(Int(bpm))")
        }
    }

    func resetSpeed() { speedPosition = 0.5 }

    func toggleClick() {
        tape.click.toggle()
        syncClick()
        touch()
        flash(tape.click ? "Click on" : "Click off")
    }

    // MARK: Cues and loop

    /// Drops a cue at the playhead, or lifts the cue the playhead is resting on.
    func toggleCue() {
        let here = position
        if let index = tape.cues.firstIndex(where: { abs($0 - here) < 0.15 }) {
            tape.cues.remove(at: index)
            flash("Cue cleared")
        } else {
            tape.cues.append(here)
            tape.cues.sort()
            flash("Cue \(tape.cues.firstIndex(of: here)! + 1)")
        }
        touch()
    }

    /// Jumps to the next (`+1`) or previous (`-1`) cue. The start of the tape counts as a cue.
    func jumpCue(_ direction: Int) {
        guard transport != .recording else { return refuse() }
        let points = [0] + tape.cues
        let here = position
        let grace = transport == .playing ? 0.4 : 0.05
        let target = direction > 0 ? points.first { $0 > here + 0.05 } : points.last { $0 < here - grace }
        guard let target else { return refuse() }
        core.seek(toSeconds: target)
        Haptics.tick()
        flash(target == 0 ? "Start" : "Cue \(tape.cues.firstIndex(of: target)! + 1)")
        moveLoopToPlayhead()
    }

    var isLooping: Bool { tape.loopIn != nil && tape.loopOut != nil }

    /// Switches the loop on or off. On, the tape repeats the section the playhead is in:
    /// from the mark before it to the mark after it. The start of the tape and the end of
    /// the recording count as marks, so with no cues the whole recording loops.
    func toggleLoop() {
        guard transport != .recording else { return refuse() }
        if isLooping {
            tape.loopIn = nil
            tape.loopOut = nil
            flash("Loop off")
        } else {
            guard setLoop(around: position) else {
                refuse()
                flash("Nothing to loop")
                return
            }
        }
        syncLoop()
        touch()
    }

    /// With the loop on, moves it to the section the playhead is now in. Called after the tape
    /// has been sent somewhere by hand (a touch on the scale, a jump to a cue), so a loop is
    /// chosen by pointing at it.
    func moveLoopToPlayhead() {
        guard isLooping, transport != .recording else { return }
        let before = tape.loopIn
        guard setLoop(around: position), tape.loopIn != before else { return }
        syncLoop()
        touch()
    }

    /// Sets the loop to the section around `seconds` and says which. False on an empty tape.
    private func setLoop(around seconds: Double) -> Bool {
        let end = core.contentSeconds
        guard end > 0.05 else { return false }
        let cues = tape.cues.filter { $0 > 0.05 && $0 < end - 0.05 }
        let marks = [0] + cues + [end]
        // Past the last mark, the last section is the one meant.
        let index = min(marks.lastIndex { $0 <= seconds + 0.01 } ?? 0, marks.count - 2)
        tape.loopIn = marks[index]
        tape.loopOut = marks[index + 1]
        func name(_ mark: Int) -> String {
            mark == 0 ? "Start" : mark == marks.count - 1 ? "End" : "Cue \(mark)"
        }
        flash(cues.isEmpty ? "Loop all" : "Loop \(name(index))–\(name(index + 1))")
        return true
    }

    // MARK: Library

    func newTape() {
        let number = (tapes.count + 1).formatted(.number.precision(.integerLength(2)))
        let meta = TapeMeta(name: "Tape \(number)")
        TapeStore.save(meta)
        tapes.insert(meta, at: 0)
        open(meta)
    }

    func open(_ meta: TapeMeta) {
        guard meta.id != tape.id, !isBusy else { return }
        if transport == .recording { finishRecording() }
        core.stop()
        transport = .stopped
        flushMeta()
        Task {
            await audioSave?.value
            tape = meta
            core.seek(toSeconds: 0)
            syncCore()
            await loadAudio()
        }
    }

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = tapes.firstIndex(where: { $0.id == id }) else { return }
        tapes[index].name = name
        TapeStore.save(tapes[index])
        if id == tape.id { tape.name = name }
    }

    func delete(_ id: UUID) {
        guard id != tape.id else { return }
        tapes.removeAll { $0.id == id }
        TapeStore.delete(id)
    }

    /// Mixes the tape down at the current speed and offers the file to the share sheet.
    func export() {
        guard core.contentEnd > 0, !isBusy else { return refuse() }
        if transport == .recording { finishRecording() }
        isBusy = true
        flash("Mixing down")
        let core = core, speed = tape.speed, name = tape.name
        Task {
            let url = await Task.detached { TapeStore.bounce(core, speed: speed, name: name) }.value
            isBusy = false
            exportItem = url.map(ExportItem.init)
        }
    }

    // MARK: Cutting

    var isEditing: Bool { edit != nil }

    /// Frames of tape per entry of `EditSession.peaks`.
    var editBin: Int { Int(core.sampleRate / 100) }

    /// Opens the edit on the selected track, or on all four if it is empty.
    func beginEdit() {
        guard transport != .recording, !isBusy, core.contentEnd > 0 else { return refuse() }
        editOriginals = [:]
        editTrack = (0..<TapeCore.trackCount).first(where: hasAudio) ?? 0
        openEdit(hasAudio(selectedTrack) ? .track(selectedTrack) : .all)
    }

    /// Changes what is being cut. What was done so far stays done, and the pieces start again
    /// from the sound as it now is.
    func setEditScope(_ scope: EditScope) {
        guard let edit, edit.scope != scope else { return }
        guard scope.tracks.contains(where: hasAudio) else { return refuse() }
        openEdit(scope)
        Haptics.tick()
    }

    /// Switches between cutting all four tracks together and the track that was being cut before.
    func toggleEditAll() {
        guard let edit else { return }
        setEditScope(edit.scope == .all ? .track(editTrack) : .all)
    }

    private func openEdit(_ scope: EditScope) {
        if case .track(let t) = scope { editTrack = t }
        editBase = [:]
        var length = 0
        var peaks: [[Float]] = []
        for t in 0..<TapeCore.trackCount {
            let samples = core.withTrack(t) { Array($0) }
            peaks.append(samples.withUnsafeBufferPointer { Waveform.peaks($0, bin: editBin) })
            guard scope.tracks.contains(t), !samples.isEmpty else { continue }
            editBase[t] = samples
            length = max(length, samples.count)
        }
        edit = EditSession(scope: scope, splice: Splice(length: length, capacity: core.capacity), selected: nil, peaks: peaks)
    }

    /// Cuts the piece under the playhead in two and picks up the second half.
    func editCut() {
        let frame = Int(core.positionFrames)
        guard var session = edit, session.splice.cut(at: frame) else { return refuse() }
        session.selected = session.splice.pieces.last { $0.start == frame }?.id
        edit = session
        Haptics.snap()
        flash("Cut")
    }

    func editSelect(_ id: Int?) {
        guard edit != nil, edit?.selected != id else { return }
        edit?.selected = id
        if id != nil { Haptics.tick() }
    }

    /// Picks up the next or previous piece along the tape and moves the tape to its start.
    func editStep(_ direction: Int) {
        guard let session = edit else { return }
        let ordered = session.splice.pieces.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return refuse() }
        let current = ordered.firstIndex { $0.id == session.selected }
        let next = current.map { min(max($0 + direction, 0), ordered.count - 1) } ?? (direction > 0 ? 0 : ordered.count - 1)
        editSelect(ordered[next].id)
        seek(to: Double(ordered[next].start) / core.sampleRate)
    }

    /// Takes the picked-up piece off the tape. The gap stays; nothing else moves.
    func editRemove() {
        guard var session = edit, let id = session.selected else { return refuse() }
        session.splice.remove(id)
        session.selected = nil
        edit = session
        applyEdit()
        flash("Removed")
    }

    /// Moves a piece while it is being dragged. Only the picture changes; `editDrop` makes the sound.
    /// Returns the frame it was put at, which may have snapped to a neighbour.
    @discardableResult
    func editMove(_ id: Int, to start: Int, reach: Int) -> Int {
        guard var session = edit, let before = session.splice.piece(id)?.start else { return start }
        let snapped = session.splice.snapped(id, start: start, reach: reach)
        session.splice.move(id, to: snapped)
        edit = session
        let after = session.splice.piece(id)?.start ?? snapped
        if after != before, after != start { Haptics.snap() }
        return after
    }

    func editDrop() {
        applyEdit()
    }

    /// Moves the picked-up piece by a fraction of a second, for VoiceOver and Switch Control.
    func editNudge(_ seconds: Double) {
        guard let session = edit, let piece = session.selected.flatMap({ session.splice.piece($0) }) else { return refuse() }
        editMove(piece.id, to: piece.start + Int(seconds * core.sampleRate), reach: 0)
        applyEdit()
    }

    /// Writes the pieces onto the tape, so what plays is what is drawn.
    private func applyEdit() {
        guard let session = edit else { return }
        let fade = Int(core.sampleRate * Recorder.editFade)
        for (t, base) in editBase {
            if editOriginals[t] == nil { editOriginals[t] = base }
            let out = base.withUnsafeBufferPointer { session.splice.render(from: $0, fade: fade) }
            out.withUnsafeBufferPointer { core.replace(track: t, with: $0) }
        }
        tape.duration = core.contentSeconds
    }

    /// Seconds a loose piece takes to fade in and out, so a cut never clicks.
    static let editFade = 0.005

    /// Leaves the edit. `keeping` saves the tape as it now is; otherwise every track goes back
    /// to how it was when the edit began.
    func endEdit(keeping: Bool) {
        guard edit != nil else { return }
        let changed = editOriginals
        edit = nil
        editBase = [:]
        editOriginals = [:]
        if keeping {
            for t in changed.keys.sorted() { saveAudio(track: t) }
            if !changed.isEmpty { flash("Edited") }
        } else {
            for (t, samples) in changed {
                samples.withUnsafeBufferPointer { core.replace(track: t, with: $0) }
            }
        }
        tape.duration = core.contentSeconds
        if core.positionSeconds > core.contentSeconds { core.seek(toSeconds: core.contentSeconds) }
        if keeping, !changed.isEmpty { touch() }
    }

    // MARK: Internals

    private func refuse() {
        Haptics.stop()
    }

    private func flash(_ text: String) {
        readout = text.uppercased()
        readoutTask?.cancel()
        readoutTask = Task {
            try? await Task.sleep(for: Motion.readoutHold)
            if !Task.isCancelled { readout = nil }
        }
    }

    private func syncCore() {
        applyMixQuietly()
        syncLoop()
        syncClick()
    }

    private func applyMixQuietly() {
        let modified = tape.modified
        applyMix()
        metaSave?.cancel()
        tape.modified = modified
    }

    private func syncLoop() {
        if let start = tape.loopIn, let end = tape.loopOut {
            core.setLoop(start...end)
        } else {
            core.setLoop(nil)
        }
    }

    private func syncClick() {
        core.setClick(on: tape.click, bpm: tape.bpm)
    }

    /// Marks the tape as changed and saves its metadata shortly after the last change.
    private func touch() {
        tape.modified = Date()
        metaSave?.cancel()
        metaSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { flushMeta() }
        }
    }

    private func flushMeta() {
        metaSave?.cancel()
        TapeStore.save(tape)
        if let index = tapes.firstIndex(where: { $0.id == tape.id }) { tapes[index] = tape }
    }

    private func saveAudio(track: Int) {
        let core = core, id = tape.id, previous = audioSave
        audioSave = Task.detached {
            await previous?.value
            TapeStore.saveTrack(track, of: core, tape: id)
        }
    }

    private func loadAudio() async {
        isBusy = true
        let core = core, id = tape.id
        await Task.detached { TapeStore.loadAudio(tape: id, into: core) }.value
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedDemoTape"), core.contentEnd == 0, !seeded {
            seeded = true       // only the tape loaded at launch, not every empty tape opened later
            seedDemoTape()
        }
        #endif
        tape.duration = core.contentSeconds
        isBusy = false
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-autoplay") { togglePlay() }
        // `-edit`: open the cutting controls with the tape cut in two places and a piece picked up.
        if ProcessInfo.processInfo.arguments.contains("-edit") {
            beginEdit()
            for seconds in [2.0, 4.5] {
                core.seek(toSeconds: seconds)
                editCut()
            }
            core.seek(toSeconds: 3.5)
        }
        #if targetEnvironment(simulator)
        // For store screenshots. Simulator only: it writes onto the tape, so it must never
        // be possible on a device with real tapes on it.
        if ProcessInfo.processInfo.arguments.contains("-autorecord") { toggleRecord() }
        #endif
        if ProcessInfo.processInfo.arguments.contains("-routeCheck") {
            // Switches the route as a take would, without recording anything, so it can be
            // read from the console. Safe on a device with tapes on it.
            _ = await io.ensureInput()
            applyRouting()
            try? await Task.sleep(for: .seconds(2))
            _ = await io.setRecording(true)
            try? await Task.sleep(for: .seconds(2))
            _ = await io.setRecording(false)
            try? await Task.sleep(for: .seconds(2))
            refreshRoute()
            print("ROUTE after: in=\(inputName ?? "none") out=\(outputName ?? "none")")
        }
        if ProcessInfo.processInfo.arguments.contains("-routeProbe") {
            _ = await io.ensureInput()
            io.probeRoutes()
        }
        #endif
    }

    private func poll() {
        io.keepAlive()
        let peaks = core.takePeaks()
        var next = levels
        func fall(_ old: Float, _ new: Float) -> Float {
            let value = max(new, old * 0.8)
            return value < 0.001 ? 0 : value
        }
        for index in next.tracks.indices { next.tracks[index] = fall(levels.tracks[index], peaks.tracks[index]) }
        next.output = fall(levels.output, max(peaks.outL, peaks.outR))
        next.input = fall(levels.input, peaks.input)
        if next != levels { levels = next }
        let tenths = Int(position * 10)
        if tenths != positionTenths { positionTenths = tenths }
        let hundredths = Int(position * 100)
        if hundredths != positionHundredths { positionHundredths = hundredths }

        if core.takeEndFlag() {
            Haptics.stop()
            if transport == .recording { finishRecording() } else { transport = .stopped }
        }
    }

    #if DEBUG
    /// Fills two tracks with synthetic notes so the app can be exercised without a microphone.
    private func seedDemoTape() {
        let rate = core.sampleRate
        func notes(_ pitches: [Double], every beat: Double, decay: Double) -> [Float] {
            var out = [Float](repeating: 0, count: Int(rate * beat * Double(pitches.count)))
            for (n, pitch) in pitches.enumerated() where pitch > 0 {
                let start = Int(Double(n) * beat * rate)
                for i in 0..<Int(beat * rate) {
                    let t = Double(i) / rate
                    out[start + i] = Float(sin(2 * .pi * pitch * t) * exp(-t / decay) * 0.4)
                }
            }
            return out
        }
        let bass = notes([55, 0, 55, 65.4, 55, 0, 49, 0, 55, 0, 55, 65.4, 73.4, 0, 65.4, 0], every: 0.5, decay: 0.25)
        let lead = notes([440, 523.3, 659.3, 523.3, 392, 493.9, 587.3, 493.9], every: 1, decay: 0.5)
        bass.withUnsafeBufferPointer { core.load(track: 0, offset: 0, $0) }
        lead.withUnsafeBufferPointer { core.load(track: 1, offset: 0, $0) }
        tape.cues = [2, 4, 6]
        tape.loopIn = 4
        tape.loopOut = 6
        syncLoop()
    }
    #endif
}

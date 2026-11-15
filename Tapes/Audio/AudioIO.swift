import AVFoundation
import TapeEngine

/// An input the device offers: its own microphone, or something plugged in.
struct AudioPort: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let builtIn: Bool
}

/// Where sound comes from and goes to, as the user has set it.
struct AudioRouting: Equatable, Sendable {
    /// The input to record from. Nil lets iOS choose (it prefers whatever was plugged in last).
    var inputID: String?
    /// Pass a plugged-in input through to the output, so the instrument is heard on this device.
    var monitor = true
}

/// Connects a `TapeCore` to the device: one source node that pulls the tape's output,
/// and (once the microphone is allowed) an input tap that feeds `TapeCore.write`.
///
/// Deliberately not main-actor isolated: the render and tap closures are created here so
/// they carry no actor isolation and can run on the audio threads.
final class AudioIO: @unchecked Sendable {
    let core = TapeCore(sampleRate: 48_000, seconds: 360)

    private let engine = AVAudioEngine()
    private let inputMixer = AVAudioMixerNode()
    private let monitor = AVAudioMixerNode()
    private var inputReady = false
    private var observers: [NSObjectProtocol] = []
    private var routing = AudioRouting()
    private var recording = false
    private var playing = false
    private var overriding = false
    private var inputEngaged = false
    private var suspended = false
    /// Called on the main queue when inputs or outputs come and go.
    var onRouteChange: (@Sendable () -> Void)?

    private var stereo: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: core.sampleRate, channels: 2)! }
    private var mono: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: core.sampleRate, channels: 1)! }

    init() {
        let core = core
        let source = AVAudioSourceNode(format: stereo) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            core.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: stereo)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // The input changed (a USB interface or headset was plugged in or pulled out):
            // its channel count and sample rate may differ, so connect it afresh.
            self?.rewireInput()
            self?.restart()
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            // A device arriving or leaving resets the speaker override, so set the routing again.
            // Our own changes also land here; those only need the monitor rechecked.
            // Our own changes also land here; `applyRouting` only acts when something is out of place.
            self?.applyRouting(lookingAgain: reason == .newDeviceAvailable || reason == .oldDeviceUnavailable)
            self?.logRoute("changed (reason \(raw))")
            self?.onRouteChange?()
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.restart() }
        })
    }

    /// Starts output. Wires the microphone too if it has already been allowed.
    func start() {
        let allowed = AVAudioApplication.shared.recordPermission == .granted
        configureSession(input: allowed)
        if allowed { wireInput() }
        restart()
        applyRouting()
    }

    /// Asks for the microphone if needed and wires it in. False if recording is not possible.
    func ensureInput() async -> Bool {
        if inputReady { return true }
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        engine.stop()
        configureSession(input: true)
        wireInput()
        restart()
        applyRouting()
        return inputReady
    }

    // MARK: Routing

    /// The inputs on offer. Empty until the microphone has been allowed.
    var inputs: [AudioPort] {
        guard inputReady else { return [] }
        return (AVAudioSession.sharedInstance().availableInputs ?? []).map {
            AudioPort(id: $0.uid, name: $0.portName, builtIn: $0.portType == .builtInMic)
        }
    }

    /// Names of the input and output in use, for the settings sheet.
    var routeNames: (input: String?, output: String?) {
        let route = AVAudioSession.sharedInstance().currentRoute
        return (route.inputs.first?.portName, route.outputs.first?.portName)
    }

    func setRouting(_ new: AudioRouting) {
        routing = new
        applyRouting()
        updateEngagement()
    }

    /// While the tape plays back, the live input steps aside so the recording is what is heard.
    func setPlaying(_ on: Bool) {
        playing = on
        updateMonitor()
        logRoute(on ? "playing" : "not playing")
    }

    /// Tells the routing whether the tape is recording, and waits for the input to be in place.
    /// Returns false if there is no working input to record from.
    ///
    /// See `applyRouting` for where the sound goes during a take and between takes.
    func setRecording(_ on: Bool) async -> Bool {
        recording = on
        applyRouting()
        updateEngagement()
        guard on else { return true }
        // A route change restarts the engine; give it a moment to come back with the input.
        for _ in 0..<20 {
            if engine.isRunning, inputEngaged, inputIsAsWanted { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !engine.isRunning {
            // It did not come back by itself (seen after a device is pulled out): rebuild the input side.
            engine.stop()
            inputEngaged = false
            updateEngagement()
        }
        if !inputEngaged { updateEngagement() }
        logRoute("ready to record, engine running=\(engine.isRunning)")
        return engine.isRunning && inputEngaged
    }

    /// An input other than the built-in microphone is on offer.
    private var externalInputAvailable: Bool {
        AVAudioSession.sharedInstance().availableInputs?.contains { $0.portType != .builtInMic } ?? false
    }

    /// The input the user chose, if it is still plugged in. Otherwise nil: automatic.
    private var chosenInput: AVAudioSessionPortDescription? {
        guard let id = routing.inputID else { return nil }
        return AVAudioSession.sharedInstance().availableInputs?.first { $0.uid == id }
    }

    private var inputIsAsWanted: Bool {
        let current = AVAudioSession.sharedInstance().currentRoute.inputs.first
        if let chosen = chosenInput { return current?.uid == chosen.uid }
        return !externalInputAvailable || current?.portType != .builtInMic
    }

    /// The route's input is something plugged in, not the device's own microphone.
    private var onExternalInput: Bool {
        guard let input = AVAudioSession.sharedInstance().currentRoute.inputs.first else { return false }
        return input.portType != .builtInMic
    }

    /// iOS has sent the sound back out through the device it is recording from.
    private var pairedWithInput: Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        guard let input = route.inputs.first, input.portType != .builtInMic else { return false }
        return route.outputs.contains { $0.portType == input.portType && $0.portName == input.portName }
    }

    /// Sets the route. There is nothing to choose but the input:
    /// - the sound goes where iOS sends it (speaker, or headphones if there are any);
    /// - if iOS pairs an instrument's input with the instrument's own output, the speaker is
    ///   forced between takes so the tape can be heard here, and released for the take, because
    ///   forcing the speaker also forces the microphone.
    ///
    /// `lookingAgain`: something was plugged in or taken away, so release the speaker first and
    /// see where iOS sends the sound by itself. Headphones are hidden while the speaker is forced.
    private func applyRouting(lookingAgain: Bool = false) {
        guard inputReady else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // Only touch the override when it has to change: every change is a route change,
            // which comes back here.
            if overriding, lookingAgain || recording {
                try session.overrideOutputAudioPort(.none)
                overriding = false
            }
            if !overriding {
                let wanted = chosenInput
                if session.preferredInput?.uid != wanted?.uid {
                    try session.setPreferredInput(wanted)
                }
                if !recording, pairedWithInput {
                    try session.overrideOutputAudioPort(.speaker)
                    overriding = true
                }
            }
        } catch {
            print("Audio routing: \(error)")
        }
        updateEngagement()
        updateMonitor()
        logRoute("applied")
    }

    private func logRoute(_ why: String) {
        #if DEBUG
        let route = AVAudioSession.sharedInstance().currentRoute
        let ins = route.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outs = route.outputs.map(\.portType.rawValue).joined(separator: ",")
        print("ROUTE \(why): in=[\(ins)] out=[\(outs)] monitor=\(monitor.outputVolume)")
        #endif
    }

    #if DEBUG
    /// `-routeProbe`: tries each way of routing with whatever is plugged in and prints what iOS does.
    /// This is how the pairing rule in `setRecording` was established.
    func probeRoutes() {
        let session = AVAudioSession.sharedInstance()
        func attempt(_ label: String, _ body: () throws -> Void) {
            do { try body() } catch { print("PROBE \(label) threw: \(error.localizedDescription)") }
            Thread.sleep(forTimeInterval: 0.6)
            let ins = session.currentRoute.inputs.map { "\($0.portName)<\($0.portType.rawValue)>" }.joined(separator: ",")
            let outs = session.currentRoute.outputs.map { "\($0.portName)<\($0.portType.rawValue)>" }.joined(separator: ",")
            print("PROBE \(label): in=[\(ins)] out=[\(outs)]")
        }
        engine.stop()
        let external = { session.availableInputs?.first { $0.portType != .builtInMic } }
        attempt("1 playAndRecord plain") {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP])
            try session.setActive(true)
            try session.setPreferredInput(nil)
            try session.overrideOutputAudioPort(.none)
        }
        attempt("2 defaultToSpeaker option") {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        }
        attempt("3 override speaker") { try session.overrideOutputAudioPort(.speaker) }
        attempt("4 override speaker + prefer external") { try session.setPreferredInput(external()) }
        attempt("5 prefer external, then override speaker") {
            try session.overrideOutputAudioPort(.none)
            try session.setPreferredInput(external())
            try session.overrideOutputAudioPort(.speaker)
        }
        attempt("6 multiRoute") {
            try session.overrideOutputAudioPort(.none)
            try session.setCategory(.multiRoute, mode: .default, options: [])
        }
        attempt("7 multiRoute + prefer external") { try session.setPreferredInput(external()) }
        print("PROBE done. Relaunch the app to restore its normal audio setup.")
    }
    #endif

    /// A plugged-in input is passed to the output so the instrument is heard here: while the
    /// tape is stopped and during a take, not while it plays back (then the tape is what is
    /// heard). Never the device's own microphone (it would feed back, or echo in headphones),
    /// and never back into the instrument the input came from (it already plays itself).
    private func updateMonitor() {
        monitor.outputVolume = routing.monitor && !playing && onExternalInput && !pairedWithInput ? 1 : 0
    }

    /// Input + output latency in frames, used to place a take where it was heard.
    var roundTripLatencyFrames: Int {
        let session = AVAudioSession.sharedInstance()
        let seconds = session.inputLatency + session.outputLatency + session.ioBufferDuration
        return Int(seconds * core.sampleRate)
    }

    private func configureSession(input: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if input {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                // A session with an input silences the Taptic Engine unless told otherwise.
                try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            } else {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setPreferredSampleRate(core.sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Audio session: \(error)")
        }
    }

    /// Builds the input side of the graph, without the microphone on it. The input node is only
    /// connected while it is needed (`engageInput`), so the microphone is not held open, and
    /// iOS does not show its indicator, while the tape is simply sitting or playing.
    private func wireInput() {
        guard !inputReady else { return }
        engine.attach(inputMixer)
        engine.attach(monitor)
        engine.connect(inputMixer, to: monitor, format: mono)
        engine.connect(monitor, to: engine.mainMixerNode, format: mono)
        // The monitor is what pulls the input chain. It is silent unless the user asks to hear
        // the input (see `updateMonitor`).
        monitor.outputVolume = 0

        let core = core
        inputMixer.installTap(onBus: 0, bufferSize: 1024, format: mono) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            core.write(samples, count: Int(buffer.frameLength))
        }
        inputReady = true
    }

    /// The input is wanted for a take, and for as long as a plugged-in instrument is being heard.
    private var inputWanted: Bool { recording || (routing.monitor && onExternalInput) }

    /// Connects or disconnects the input node to match `inputWanted`.
    private func updateEngagement() {
        guard inputReady, inputWanted != inputEngaged else { return }
        engine.stop()
        if inputWanted {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            if format.channelCount > 0, format.sampleRate > 0 {
                engine.connect(input, to: inputMixer, format: format)
                inputEngaged = true
            }
        } else {
            engine.disconnectNodeOutput(engine.inputNode)
            inputEngaged = false
        }
        restart()
        updateMonitor()
    }

    // MARK: Leaving the foreground

    /// Stops all audio and gives the session back. For when the app leaves the foreground with
    /// the tape at rest: nothing is playing, nothing is recording, nothing should be running.
    func suspend() {
        guard !recording, !suspended else { return }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        suspended = true
    }

    /// Starts the engine again if something stopped it behind our back. Cheap; called often.
    func keepAlive() {
        if !suspended, !engine.isRunning { restart() }
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        try? AVAudioSession.sharedInstance().setActive(true)
        restart()
        applyRouting()
    }

    /// Reconnects the input node in whatever format the current input device has.
    private func rewireInput() {
        guard inputReady, inputEngaged else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        engine.disconnectNodeOutput(input)
        engine.connect(input, to: inputMixer, format: format)
        updateMonitor()
    }

    private func restart() {
        guard !engine.isRunning, !suspended else { return }
        do {
            try engine.start()
        } catch {
            print("Audio engine: \(error)")
        }
    }
}

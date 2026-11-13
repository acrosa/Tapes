import AVFoundation
import TapeEngine

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
    }

    /// Asks for the microphone if needed and wires it in. False if recording is not possible.
    func ensureInput() async -> Bool {
        if inputReady { return true }
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        engine.stop()
        configureSession(input: true)
        wireInput()
        restart()
        return inputReady
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

    private func wireInput() {
        guard !inputReady else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }

        engine.attach(inputMixer)
        engine.attach(monitor)
        engine.connect(input, to: inputMixer, format: format)
        engine.connect(inputMixer, to: monitor, format: mono)
        engine.connect(monitor, to: engine.mainMixerNode, format: mono)
        // The monitor exists so the input chain is pulled by the output; it stays silent.
        monitor.outputVolume = 0

        let core = core
        inputMixer.installTap(onBus: 0, bufferSize: 1024, format: mono) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            core.write(samples, count: Int(buffer.frameLength))
        }
        inputReady = true
    }

    /// Reconnects the input node in whatever format the current input device has.
    private func rewireInput() {
        guard inputReady else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        engine.disconnectNodeOutput(input)
        engine.connect(input, to: inputMixer, format: format)
    }

    private func restart() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Audio engine: \(error)")
        }
    }
}

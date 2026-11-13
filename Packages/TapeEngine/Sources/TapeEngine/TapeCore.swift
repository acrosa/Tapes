import Foundation

/// Peak levels since the last `takePeaks()` call, linear 0…1+.
public struct Peaks: Sendable, Equatable {
    public var tracks: [Float]
    public var outL: Float
    public var outR: Float
    public var input: Float
}

/// A four-track tape held in memory, with one fractional playhead.
///
/// The playhead has a rate and a target rate; the rate glides towards the target with a
/// time constant, which is what makes start, stop, varispeed, scrub and flick all behave
/// like a physical transport. Everything that produces sound goes through `render`.
///
/// Threading: `render` runs on the realtime audio thread, `write` on the input tap thread,
/// everything else on the control (main) thread. Shared fields are plain scalars and
/// fixed-size C arrays, read and written without locks. A torn or stale read costs at most
/// one audio block of slightly wrong gain or position, which is the accepted trade for a
/// render path that never blocks or allocates.
public final class TapeCore: @unchecked Sendable {
    public static let trackCount = 4

    public let sampleRate: Double
    /// Tape length in frames.
    public let capacity: Int

    private let tracks: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let lengths: UnsafeMutablePointer<Int>
    private let gains: UnsafeMutablePointer<Float>      // L, R per track
    private let peaks: UnsafeMutablePointer<Float>      // 4 tracks, outL, outR, input

    private var playhead: Double = 0
    private var rate: Double = 0
    private var targetRate: Double = 0
    private var glide: Double = 1
    private var rolling = false
    private var scrubbing = false
    private var scrubTarget: Double = 0
    private var endFlag = false

    private var recTrack = -1
    private var recHead = 0

    private var loopOn = false
    private var loopIn: Double = 0
    private var loopOut: Double = 0

    private var clickOn = false
    private var beatFrames: Double
    private var beatsPerBar = 4
    private let clickGain: Float = 0.5

    /// Seconds for the tape to reach speed, to come to rest, and to coast after a flick.
    public static let startTime = 0.09
    public static let stopTime = 0.14
    public static let coastTime = 0.45

    public init(sampleRate: Double = 48_000, seconds: Double = 360) {
        self.sampleRate = sampleRate
        self.capacity = Int(sampleRate * seconds)
        self.beatFrames = sampleRate * 60 / 120
        tracks = .allocate(capacity: Self.trackCount)
        for t in 0..<Self.trackCount {
            // calloc: pages stay uncommitted until a track is actually recorded.
            tracks[t] = calloc(capacity, MemoryLayout<Float>.stride)!.assumingMemoryBound(to: Float.self)
        }
        lengths = .allocate(capacity: Self.trackCount)
        lengths.initialize(repeating: 0, count: Self.trackCount)
        gains = .allocate(capacity: Self.trackCount * 2)
        gains.initialize(repeating: 1, count: Self.trackCount * 2)
        peaks = .allocate(capacity: Self.trackCount + 3)
        peaks.initialize(repeating: 0, count: Self.trackCount + 3)
    }

    deinit {
        for t in 0..<Self.trackCount { free(tracks[t]) }
        tracks.deallocate()
        lengths.deallocate()
        gains.deallocate()
        peaks.deallocate()
    }

    // MARK: Position

    public var positionFrames: Double { playhead }
    public var positionSeconds: Double { playhead / sampleRate }
    public var currentRate: Double { rate }
    public var isRecording: Bool { recTrack >= 0 }

    /// Frames up to the end of the longest track.
    public var contentEnd: Int {
        var end = 0
        for t in 0..<Self.trackCount { end = max(end, lengths[t]) }
        return end
    }

    public var contentSeconds: Double { Double(contentEnd) / sampleRate }

    public func length(ofTrack t: Int) -> Int { lengths[t] }

    public func seek(toSeconds seconds: Double) {
        let frame = min(max(seconds * sampleRate, 0), Double(capacity - 2))
        playhead = frame
        scrubTarget = frame
    }

    // MARK: Transport

    private func coefficient(_ seconds: Double) -> Double {
        1 - exp(-1 / (max(seconds, 0.0005) * sampleRate))
    }

    /// Rolls the tape towards `rate` (1 = normal speed).
    public func play(rate: Double) {
        glide = coefficient(Self.startTime)
        targetRate = rate
        rolling = true
    }

    /// Changes speed while rolling, with a short glide.
    public func setRate(_ rate: Double) {
        guard rolling else { return }
        glide = coefficient(0.04)
        targetRate = rate
    }

    public func stop() {
        glide = coefficient(Self.stopTime)
        targetRate = 0
        rolling = false
    }

    /// The playhead starts chasing `scrubTarget`; move it with `scrub(bySeconds:)`.
    public func beginScrub() {
        scrubTarget = playhead
        scrubbing = true
    }

    public func scrub(bySeconds seconds: Double) {
        scrubTarget = min(max(scrubTarget + seconds * sampleRate, 0), Double(capacity - 2))
    }

    /// Releases the tape. It keeps the speed the hand gave it and coasts towards `resumeRate`.
    public func endScrub(resumeRate: Double) {
        glide = coefficient(Self.coastTime)
        targetRate = resumeRate
        rolling = resumeRate != 0
        scrubbing = false
    }

    /// True once after the tape stopped itself (end of content or end of tape).
    public func takeEndFlag() -> Bool {
        guard endFlag else { return false }
        endFlag = false
        return true
    }

    // MARK: Loop and click

    /// Loops between two positions in seconds; `nil` clears the loop.
    public func setLoop(_ range: ClosedRange<Double>?) {
        loopOn = false
        guard let range, range.upperBound - range.lowerBound > 0.02 else { return }
        loopIn = range.lowerBound * sampleRate
        loopOut = range.upperBound * sampleRate
        loopOn = true
    }

    public func setClick(on: Bool, bpm: Double, beatsPerBar: Int = 4) {
        beatFrames = sampleRate * 60 / max(bpm, 1)
        self.beatsPerBar = max(1, beatsPerBar)
        clickOn = on
    }

    // MARK: Mix

    public func setGain(track t: Int, left: Float, right: Float) {
        gains[t * 2] = left
        gains[t * 2 + 1] = right
    }

    public func takePeaks() -> Peaks {
        var result = Peaks(tracks: [], outL: peaks[4], outR: peaks[5], input: peaks[6])
        for t in 0..<Self.trackCount { result.tracks.append(peaks[t]) }
        for i in 0..<(Self.trackCount + 3) { peaks[i] = 0 }
        return result
    }

    // MARK: Recording

    /// Starts recording onto `track` at the playhead, at normal speed.
    /// `latencyFrames` is the input + output round trip, so what was played to the
    /// tape lands where the performer heard it.
    public func beginRecording(track: Int, latencyFrames: Int) {
        loopOn = false
        rate = 1
        targetRate = 1
        rolling = true
        recHead = Int(playhead) - latencyFrames
        recTrack = track
    }

    public func endRecording() {
        recTrack = -1
    }

    /// Input tap entry point: meters the input and, while recording, writes it to tape.
    public func write(_ input: UnsafePointer<Float>, count: Int) {
        var peak: Float = 0
        for i in 0..<count { peak = max(peak, abs(input[i])) }
        peaks[6] = max(peaks[6], peak)

        let t = recTrack
        guard t >= 0 else { return }
        let head = recHead
        let from = max(0, -head)
        let to = min(count, capacity - head)
        if to > from {
            let destination = tracks[t]
            for i in from..<to { destination[head + i] = input[i] }
            lengths[t] = max(lengths[t], head + to)
        }
        recHead = head + count
    }

    // MARK: Track storage

    public func erase(track t: Int) {
        let length = lengths[t]
        lengths[t] = 0
        if length > 0 { tracks[t].update(repeating: 0, count: length) }
    }

    public func eraseAll() {
        for t in 0..<Self.trackCount { erase(track: t) }
    }

    /// Copies `samples` onto `track` starting at frame `offset`.
    public func load(track t: Int, offset: Int, _ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress, offset >= 0, offset < capacity else { return }
        let count = min(samples.count, capacity - offset)
        (tracks[t] + offset).update(from: base, count: count)
        lengths[t] = max(lengths[t], offset + count)
    }

    /// The recorded samples of `track`.
    public func withTrack<T>(_ t: Int, _ body: (UnsafeBufferPointer<Float>) throws -> T) rethrows -> T {
        try body(UnsafeBufferPointer(start: tracks[t], count: lengths[t]))
    }

    // MARK: Render

    @inline(__always)
    private func mix(at position: Double, skipping skip: Int, metering: Bool) -> (Float, Float) {
        let index = Int(position)
        let fraction = Float(position - Double(index))
        var left: Float = 0
        var right: Float = 0
        for t in 0..<Self.trackCount where t != skip {
            guard index + 1 < lengths[t] else { continue }
            let samples = tracks[t]
            let a = samples[index]
            let sample = a + (samples[index + 1] - a) * fraction
            let gl = gains[t * 2]
            let gr = gains[t * 2 + 1]
            left += sample * gl
            right += sample * gr
            if metering {
                let level = abs(sample) * max(gl, gr)
                if level > peaks[t] { peaks[t] = level }
            }
        }
        return (left, right)
    }

    @inline(__always)
    private func click(at position: Double) -> Float {
        let beat = (position / beatFrames).rounded(.down)
        let phase = position - beat * beatFrames
        guard phase < 0.03 * sampleRate else { return 0 }
        let frequency: Double = Int(beat) % beatsPerBar == 0 ? 1760 : 1320
        let envelope = exp(-phase / (0.006 * sampleRate))
        return Float(sin(2 * .pi * frequency * phase / sampleRate) * envelope) * clickGain
    }

    /// Fills `frames` stereo frames and advances the playhead. Realtime safe.
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        var position = playhead
        var r = rate
        let recording = recTrack
        let end = Double(contentEnd)
        let last = Double(capacity - 2)
        let scrubGlide = coefficient(0.004)
        let chase = 0.03 * sampleRate
        var peakL: Float = 0
        var peakR: Float = 0

        for i in 0..<frames {
            if recording >= 0 {
                r = 1
            } else if scrubbing {
                let wanted = min(max((scrubTarget - position) / chase, -16), 16)
                r += (wanted - r) * scrubGlide
            } else {
                r += (targetRate - r) * glide
                if targetRate == 0, abs(r) < 0.0005 { r = 0 }
            }

            var l: Float = 0
            var rr: Float = 0
            if r != 0 {
                (l, rr) = mix(at: position, skipping: recording, metering: true)
                // Fade as the tape slows, so a held or stopping tape is silent, not a stuck sample.
                let fade = Float(min(1, abs(r) / 0.08))
                l *= fade
                rr *= fade
                if clickOn, rolling, !scrubbing, r > 0 {
                    let c = click(at: position)
                    l += c
                    rr += c
                }
            }
            left[i] = l
            right[i] = rr
            peakL = max(peakL, abs(l))
            peakR = max(peakR, abs(rr))

            position += r

            if loopOn, !scrubbing, r > 0, position >= loopOut, position - r < loopOut {
                position = loopIn + (position - loopOut)
            }
            if position <= 0 {
                position = 0
                if r < 0 { r = 0 }
            } else if position >= last {
                position = last
                if rolling || r > 0 {
                    r = 0
                    targetRate = 0
                    rolling = false
                    endFlag = true
                }
            } else if rolling, recording < 0, !scrubbing, r > 0, end > 0, position >= end, position - r < end {
                // Playback ran off the end of the recorded material: stop there.
                position = end
                r = 0
                targetRate = 0
                rolling = false
                endFlag = true
            }
        }

        playhead = position
        rate = r
        if peakL > peaks[4] { peaks[4] = peakL }
        if peakR > peaks[5] { peaks[5] = peakR }
    }

    // MARK: Bounce

    /// Offline stereo mixdown of the whole tape with the current mix, played at `speed`.
    public func bounce(speed: Double = 1) -> (left: [Float], right: [Float]) {
        let end = contentEnd
        guard end > 1, speed > 0 else { return ([], []) }
        let count = Int(Double(end - 1) / speed)
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)
        for i in 0..<count {
            (left[i], right[i]) = mix(at: Double(i) * speed, skipping: -1, metering: false)
        }
        return (left, right)
    }
}

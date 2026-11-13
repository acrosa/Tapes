import Testing
import Foundation
@testable import TapeEngine

private let sr = 1_000.0

/// A core at 1 kHz whose track 0 holds a ramp: sample n has value n / 1000.
private func rampCore(frames: Int = 500) -> TapeCore {
    let core = TapeCore(sampleRate: sr, seconds: 4)
    let ramp = (0..<frames).map { Float($0) / 1000 }
    ramp.withUnsafeBufferPointer { core.load(track: 0, offset: 0, $0) }
    for t in 0..<TapeCore.trackCount { core.setGain(track: t, left: 1, right: 1) }
    return core
}

@discardableResult
private func run(_ core: TapeCore, frames: Int) -> (left: [Float], right: [Float]) {
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)
    left.withUnsafeMutableBufferPointer { l in
        right.withUnsafeMutableBufferPointer { r in
            core.render(frames: frames, left: l.baseAddress!, right: r.baseAddress!)
        }
    }
    return (left, right)
}

@Test func stoppedTapeIsSilentAndDoesNotMove() {
    let core = rampCore()
    core.seek(toSeconds: 0.1)
    let out = run(core, frames: 64)
    #expect(out.left.allSatisfy { $0 == 0 })
    #expect(core.positionFrames == 100)
}

@Test func playbackReachesSpeedAndAppliesGain() {
    let core = rampCore()
    core.setGain(track: 0, left: 0.5, right: 0.25)
    core.play(rate: 1)
    run(core, frames: 400)   // well past the start glide
    #expect(abs(core.currentRate - 1) < 0.02)
    let before = core.positionFrames
    let out = run(core, frames: 1)
    let expected = Float(before) / 1000
    #expect(abs(out.left[0] - expected * 0.5) < 0.002)
    #expect(abs(out.right[0] - expected * 0.25) < 0.002)
}

@Test func playbackStopsAtEndOfContentAndFlagsIt() {
    let core = rampCore(frames: 300)
    core.play(rate: 1)
    run(core, frames: 1_000)
    #expect(core.positionFrames == 300)
    #expect(core.currentRate == 0)
    #expect(core.takeEndFlag())
    #expect(!core.takeEndFlag())
}

@Test func loopWrapsBackToLoopIn() {
    let core = rampCore()
    core.setLoop(0.1...0.2)
    core.seek(toSeconds: 0.1)
    core.play(rate: 1)
    run(core, frames: 950)
    #expect(core.positionFrames >= 100)
    #expect(core.positionFrames < 200)
    #expect(!core.takeEndFlag())
}

@Test func recordingWritesAtThePlayheadMinusLatency() {
    let core = TapeCore(sampleRate: sr, seconds: 4)
    core.seek(toSeconds: 0.5)
    core.beginRecording(track: 2, latencyFrames: 20)
    let input = [Float](repeating: 0.5, count: 100)
    input.withUnsafeBufferPointer { core.write($0.baseAddress!, count: 100) }
    core.endRecording()
    #expect(core.length(ofTrack: 2) == 580)
    core.withTrack(2) { samples in
        #expect(samples[479] == 0)
        #expect(samples[480] == 0.5)
        #expect(samples[579] == 0.5)
    }
    #expect(core.takePeaks().input == 0.5)
}

@Test func recordingTrackIsMutedWhileItRecords() {
    let core = rampCore()
    core.seek(toSeconds: 0.1)
    core.beginRecording(track: 0, latencyFrames: 0)
    let out = run(core, frames: 50)
    #expect(out.left.allSatisfy { $0 == 0 })
    #expect(core.positionFrames == 150)
}

@Test func scrubChasesTheHandAndRestsThere() {
    let core = rampCore()
    core.beginScrub()
    core.scrub(bySeconds: 0.2)
    run(core, frames: 600)
    #expect(abs(core.positionFrames - 200) < 1)
    core.endScrub(resumeRate: 0)
    run(core, frames: 2_000)
    #expect(core.currentRate == 0)
    #expect(abs(core.positionFrames - 200) < 2)
}

@Test func scrubbingBackwardsStopsAtTheStartOfTheTape() {
    let core = rampCore()
    core.seek(toSeconds: 0.05)
    core.beginScrub()
    core.scrub(bySeconds: -1)
    run(core, frames: 600)
    #expect(core.positionFrames < 0.5)   // the chase approaches the start asymptotically
}

@Test func bounceAtDoubleSpeedIsHalfAsLong() {
    let core = rampCore(frames: 401)
    let normal = core.bounce(speed: 1)
    let fast = core.bounce(speed: 2)
    #expect(normal.left.count == 400)
    #expect(fast.left.count == 200)
    #expect(abs(fast.left[100] - 0.2) < 0.0001)
}

@Test func eraseClearsLengthAndSamples() {
    let core = rampCore()
    core.erase(track: 0)
    #expect(core.contentEnd == 0)
    core.play(rate: 1)
    let out = run(core, frames: 200)
    #expect(out.left.allSatisfy { $0 == 0 })
}

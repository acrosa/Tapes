import Testing
@testable import TapeEngine

/// A recording where sample n has the value n + 1, so a sample says where it came from.
private func ramp(_ count: Int) -> [Float] { (0..<count).map { Float($0 + 1) } }

private func render(_ splice: Splice, _ source: [Float], fade: Int = 0) -> [Float] {
    source.withUnsafeBufferPointer { splice.render(from: $0, fade: fade) }
}

@Test func aNewSpliceIsTheWholeRecording() {
    let splice = Splice(length: 2_000, capacity: 10_000)
    #expect(splice.pieces.count == 1)
    #expect(splice.end == 2_000)
    #expect(!splice.isChanged)
    #expect(render(splice, ramp(2_000), fade: 100) == ramp(2_000))
}

@Test func cuttingChangesNothingYouCanHear() {
    var splice = Splice(length: 4_000, capacity: 10_000)
    let cut1 = splice.cut(at: 1_000)
    #expect(cut1)
    let cut2 = splice.cut(at: 2_500)
    #expect(cut2)
    #expect(splice.pieces.count == 3)
    #expect(!splice.isChanged)
    // Pieces that still join where they were cut play through with no fade.
    #expect(render(splice, ramp(4_000), fade: 200) == ramp(4_000))
}

@Test func aCutNeedsAPieceUnderItAndRoomEitherSide() {
    var splice = Splice(length: 4_000, capacity: 10_000)
    let cut3 = splice.cut(at: 5_000)
    #expect(!cut3)
    let cut4 = splice.cut(at: Splice.shortest - 1)
    #expect(!cut4)
    let cut5 = splice.cut(at: 4_000 - Splice.shortest + 1)
    #expect(!cut5)
    #expect(splice.pieces.count == 1)
}

@Test func removingLeavesSilenceAndMovesNothing() {
    var splice = Splice(length: 3_000, capacity: 10_000)
    splice.cut(at: 1_000)
    splice.cut(at: 2_000)
    let middle = splice.piece(at: 1_500)!
    splice.remove(middle.id)
    #expect(splice.isChanged)
    let out = render(splice, ramp(3_000))
    #expect(out.count == 3_000)
    #expect(out[999] == 1_000)
    #expect(out[1_000..<2_000].allSatisfy { $0 == 0 })
    #expect(out[2_000] == 2_001)
}

@Test func aMovedPieceTakesItsSoundWithItAndStaysOnTheTape() {
    var splice = Splice(length: 2_000, capacity: 5_000)
    splice.cut(at: 1_000)
    let second = splice.piece(at: 1_500)!
    splice.move(second.id, to: 3_000)
    let out = render(splice, ramp(2_000))
    #expect(out.count == 4_000)
    #expect(out[1_500] == 0)
    #expect(out[3_000] == 1_001)
    #expect(out[3_999] == 2_000)
    splice.move(second.id, to: 9_000)
    #expect(splice.piece(second.id)!.end == 5_000)
    splice.move(second.id, to: -50)
    #expect(splice.piece(second.id)!.start == 0)
}

@Test func piecesLaidOverEachOtherFadeAcrossTheOverlap() {
    // A constant recording, so the sum through a crossfade should stay at one.
    let source = [Float](repeating: 1, count: 4_000)
    var splice = Splice(length: 4_000, capacity: 10_000)
    splice.cut(at: 2_000)
    let second = splice.piece(at: 3_000)!
    splice.move(second.id, to: 1_500)                  // 500 frames over the end of the first
    let out = render(splice, source, fade: 10)
    #expect(out.count == 3_500)
    #expect(out[1_500..<2_000].allSatisfy { abs($0 - 1) < 0.01 })
    #expect(abs(out[1_000] - 1) < 0.0001)
    #expect(abs(out[2_500] - 1) < 0.0001)
}

@Test func aLoosePieceFadesInAndOut() {
    let source = [Float](repeating: 1, count: 3_000)
    var splice = Splice(length: 3_000, capacity: 10_000)
    splice.cut(at: 1_000)
    splice.cut(at: 2_000)
    splice.remove(splice.piece(at: 500)!.id)
    splice.remove(splice.piece(at: 2_500)!.id)
    let out = render(splice, source, fade: 100)
    #expect(out[1_000] == 0)
    #expect(out[1_050] == 0.5)
    #expect(out[1_500] == 1)
    #expect(out[1_999] == 0)
}

@Test func aPieceSnapsToItsOwnPlaceAndToItsNeighbours() {
    var splice = Splice(length: 3_000, capacity: 10_000)
    splice.cut(at: 1_000)
    splice.cut(at: 2_000)
    let last = splice.piece(at: 2_500)!
    splice.remove(splice.piece(at: 1_500)!.id)
    #expect(splice.snapped(last.id, start: 1_030, reach: 50) == 1_000)   // against the end of the first
    #expect(splice.snapped(last.id, start: 1_980, reach: 50) == 2_000)   // home
    #expect(splice.snapped(last.id, start: 1_500, reach: 50) == 1_500)
}

@Test func aShorterTrackEditedWithTheOthersStaysInRange() {
    var splice = Splice(length: 2_000, capacity: 10_000)
    splice.cut(at: 1_000)
    splice.move(splice.piece(at: 1_500)!.id, to: 3_000)
    let out = render(splice, ramp(1_200))              // this track only reaches 1 200
    #expect(out.count == 4_000)
    #expect(out[3_199] == 1_200)
    #expect(out[3_200] == 0)
}

@Test func peaksAreTheLoudestSampleOfEachBin() {
    let samples: [Float] = [0.1, -0.5, 0.2, 0.3, -0.9, 0, 0.4]
    #expect(samples.withUnsafeBufferPointer { Waveform.peaks($0, bin: 3) } == [0.5, 0.9, 0.4])
}

@Test func replacingATrackClearsWhatWasBeyondIt() {
    let core = TapeCore(sampleRate: 1_000, seconds: 4)
    ramp(2_000).withUnsafeBufferPointer { core.load(track: 1, offset: 0, $0) }
    ramp(500).withUnsafeBufferPointer { core.replace(track: 1, with: $0) }
    #expect(core.length(ofTrack: 1) == 500)
    ramp(1_000).withUnsafeBufferPointer { core.load(track: 1, offset: 1_000, $0) }
    core.withTrack(1) { track in
        #expect(track[499] == 500)
        #expect(track[500..<1_000].allSatisfy { $0 == 0 })
    }
}

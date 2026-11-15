/// A length of recorded sound placed on the tape: `source` is where it was when editing began,
/// `start` is where it sits now. Both in frames.
public struct Piece: Identifiable, Equatable, Sendable {
    public let id: Int
    public var source: Range<Int>
    public var start: Int

    public var count: Int { source.count }
    public var end: Int { start + source.count }
    /// True when the piece has not moved from where it was recorded.
    public var isHome: Bool { start == source.lowerBound }
}

/// The edit of a tape as a list of pieces. It begins as one piece, the whole recording; cutting
/// divides pieces, and each can then be moved or removed. Removing leaves silence: nothing else
/// moves. Later pieces in the list lie on top of earlier ones.
///
/// The list holds no sound. `render` builds the edited track from the samples as they were.
public struct Splice: Equatable, Sendable {
    public private(set) var pieces: [Piece] = []
    /// Tape length in frames. No piece is placed beyond it.
    public let capacity: Int
    /// Length of the recording the pieces were cut from.
    public let length: Int
    private var nextID = 0

    /// The shortest piece a cut may leave, in frames.
    public static let shortest = 480

    public init(length: Int, capacity: Int) {
        self.capacity = capacity
        self.length = min(length, capacity)
        if length > 0 { pieces = [Piece(id: 0, source: 0..<min(length, capacity), start: 0)] }
        nextID = 1
    }

    /// The frame after the last piece.
    public var end: Int { pieces.map(\.end).max() ?? 0 }

    /// True once anything differs from the recording: a piece moved or removed.
    public var isChanged: Bool {
        pieces.contains { !$0.isHome } || pieces.reduce(0) { $0 + $1.count } != length
    }

    /// The piece under `frame`; the topmost one where pieces overlap.
    public func piece(at frame: Int) -> Piece? {
        pieces.last { $0.start <= frame && frame < $0.end }
    }

    public func piece(_ id: Int) -> Piece? { pieces.first { $0.id == id } }

    /// Divides every piece under `frame` in two there. Returns false if no piece is under it or
    /// the cut would leave a piece shorter than `shortest`.
    @discardableResult
    public mutating func cut(at frame: Int) -> Bool {
        var done = false
        for index in pieces.indices.reversed() {
            let piece = pieces[index]
            let offset = frame - piece.start
            guard offset >= Self.shortest, piece.count - offset >= Self.shortest else { continue }
            let middle = piece.source.lowerBound + offset
            pieces[index].source = piece.source.lowerBound..<middle
            pieces.insert(Piece(id: nextID, source: middle..<piece.source.upperBound, start: frame), at: index + 1)
            nextID += 1
            done = true
        }
        return done
    }

    public mutating func remove(_ id: Int) {
        pieces.removeAll { $0.id == id }
    }

    /// Puts a piece at `start`, kept on the tape, and lays it on top of the others.
    public mutating func move(_ id: Int, to start: Int) {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else { return }
        var piece = pieces.remove(at: index)
        piece.start = min(max(0, start), max(0, capacity - piece.count))
        pieces.append(piece)
    }

    /// `start`, pulled to where the piece would sit against the tape's beginning, its own place
    /// in the recording, or the edge of another piece, when one of those is within `reach` frames.
    public func snapped(_ id: Int, start: Int, reach: Int) -> Int {
        guard let piece = piece(id) else { return start }
        var targets = [0, piece.source.lowerBound]
        for other in pieces where other.id != id {
            targets.append(other.end)                   // begin where another ends
            targets.append(other.start - piece.count)   // end where another begins
        }
        guard let best = targets.min(by: { abs($0 - start) < abs($1 - start) }), abs(best - start) <= reach else { return start }
        return best
    }

    /// The edited track: every piece copied from `source` to its place and summed.
    ///
    /// A piece fades in and out over `fade` frames so a cut never clicks, except where it still
    /// joins the piece it was cut from, or is the untouched beginning or end of the recording:
    /// those play through unchanged. Where a piece is laid over
    /// the end of another, the two fade across the whole overlap.
    public func render(from source: UnsafeBufferPointer<Float>, fade: Int) -> [Float] {
        var out = [Float](repeating: 0, count: end)
        for piece in pieces {
            var fadeIn = fade, fadeOut = fade
            if piece.isHome, piece.source.lowerBound == 0 { fadeIn = 0 }
            if piece.isHome, piece.source.upperBound == length { fadeOut = 0 }
            for other in pieces where other.id != piece.id {
                if other.end == piece.start, other.source.upperBound == piece.source.lowerBound { fadeIn = 0 }
                if other.start == piece.end, other.source.lowerBound == piece.source.upperBound { fadeOut = 0 }
                if other.start < piece.start, piece.start < other.end, other.end < piece.end {
                    fadeIn = max(fadeIn, other.end - piece.start)
                }
                if piece.start < other.start, other.start < piece.end, piece.end < other.end {
                    fadeOut = max(fadeOut, piece.end - other.start)
                }
            }
            if fadeIn + fadeOut > piece.count {
                let scale = Double(piece.count) / Double(fadeIn + fadeOut)
                fadeIn = Int(Double(fadeIn) * scale)
                fadeOut = Int(Double(fadeOut) * scale)
            }
            let first = piece.source.lowerBound
            let count = min(piece.count, max(0, source.count - first))    // a shorter track, edited with the others
            guard count > 0 else { continue }
            out.withUnsafeMutableBufferPointer { out in
                for i in 0..<count {
                    var gain: Float = 1
                    if i < fadeIn { gain = Float(i) / Float(fadeIn) }
                    let left = piece.count - 1 - i
                    if left < fadeOut { gain = min(gain, Float(left) / Float(fadeOut)) }
                    out[piece.start + i] += source[first + i] * gain
                }
            }
        }
        return out
    }
}

public enum Waveform {
    /// The loudest sample in each run of `bin` frames: enough to draw a track.
    public static func peaks(_ samples: UnsafeBufferPointer<Float>, bin: Int) -> [Float] {
        guard bin > 0, !samples.isEmpty else { return [] }
        var out = [Float](repeating: 0, count: (samples.count + bin - 1) / bin)
        for index in out.indices {
            var peak: Float = 0
            for i in (index * bin)..<min(samples.count, (index + 1) * bin) { peak = max(peak, abs(samples[i])) }
            out[index] = peak
        }
        return out
    }
}

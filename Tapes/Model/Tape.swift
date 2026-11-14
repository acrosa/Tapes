import AVFoundation
import TapeEngine

struct TrackMix: Codable, Equatable, Sendable {
    /// 0…1 fader position. `TrackMix.unity` is 0 dB.
    var volume = TrackMix.unity
    /// −1 (left) … +1 (right).
    var pan = 0.0
    var mute = false
    var solo = false

    static let unity = 0.8
}

/// Everything about a tape except its audio. Stored as `tape.json` beside the track files.
struct TapeMeta: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var created = Date()
    var modified = Date()
    var bpm = 120.0
    var speed = 1.0
    var click = false
    /// Cue positions in seconds, ascending.
    var cues: [Double] = []
    var loopIn: Double?
    var loopOut: Double?
    var tracks = [TrackMix](repeating: TrackMix(), count: TapeCore.trackCount)
    /// Length of recorded material in seconds.
    var duration = 0.0
}

/// Tapes on disk: `Documents/Tapes/<id>/tape.json` plus `track1.wav` … `track4.wav`
/// (mono, 32-bit float, 48 kHz). The folder is visible in the Files app.
enum TapeStore {
    static var root: URL {
        URL.documentsDirectory.appending(path: "Tapes", directoryHint: .isDirectory)
    }

    static func folder(_ id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private static func trackURL(_ id: UUID, _ track: Int) -> URL {
        folder(id).appending(path: "track\(track + 1).wav")
    }

    /// All tapes, most recently modified first.
    static func list() -> [TapeMeta] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return folders
            .compactMap { try? Data(contentsOf: $0.appending(path: "tape.json")) }
            .compactMap { try? decoder.decode(TapeMeta.self, from: $0) }
            .sorted { $0.modified > $1.modified }
    }

    static func save(_ meta: TapeMeta) {
        do {
            try FileManager.default.createDirectory(at: folder(meta.id), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(meta).write(to: folder(meta.id).appending(path: "tape.json"), options: .atomic)
        } catch {
            print("Saving tape: \(error)")
        }
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Writes one track of `core` to disk, or removes its file if the track is empty.
    static func saveTrack(_ track: Int, of core: TapeCore, tape id: UUID) {
        let url = trackURL(id, track)
        try? FileManager.default.removeItem(at: url)
        guard core.length(ofTrack: track) > 0 else { return }
        do {
            try FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
            let format = AVAudioFormat(standardFormatWithSampleRate: core.sampleRate, channels: 1)!
            try core.withTrack(track) { samples in
                try write(channels: [samples], format: format, to: url)
            }
        } catch {
            print("Saving track \(track + 1): \(error)")
        }
    }

    /// Replaces the contents of `core` with the audio of tape `id`.
    static func loadAudio(tape id: UUID, into core: TapeCore) {
        core.eraseAll()
        for track in 0..<TapeCore.trackCount {
            guard let file = try? AVAudioFile(forReading: trackURL(id, track)),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)
            else { continue }
            var offset = 0
            while (try? file.read(into: buffer)) != nil, buffer.frameLength > 0, let data = buffer.floatChannelData {
                let count = Int(buffer.frameLength)
                core.load(track: track, offset: offset, UnsafeBufferPointer(start: data[0], count: count))
                offset += count
            }
        }
    }

    /// Mixes the tape down to a stereo WAV in the temporary directory.
    static func bounce(_ core: TapeCore, speed: Double, name: String) -> URL? {
        let mix = core.bounce(speed: speed)
        guard !mix.left.isEmpty else { return nil }
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: "\(safeName).wav")
        try? FileManager.default.removeItem(at: url)
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: core.sampleRate, channels: 2)!
            try mix.left.withUnsafeBufferPointer { left in
                try mix.right.withUnsafeBufferPointer { right in
                    try write(channels: [left, right], format: format, to: url)
                }
            }
            return url
        } catch {
            print("Bounce: \(error)")
            return nil
        }
    }

    private static func write(channels: [UnsafeBufferPointer<Float>], format: AVAudioFormat, to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let chunk = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)),
              let data = buffer.floatChannelData
        else { return }
        let total = channels.map(\.count).min() ?? 0
        var offset = 0
        while offset < total {
            let count = min(chunk, total - offset)
            for (index, channel) in channels.enumerated() {
                data[index].update(from: channel.baseAddress! + offset, count: count)
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            offset += count
        }
    }
}

import AVFoundation
import NotcherCore

/// Tiny synthesizer: every sound is generated at launch, no audio assets.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [SoundCue: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [SoundCue: TimeInterval] = [:]
    private var nextPlayer = 0
    private var configured = false
    private let sampleRate = 44_100.0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)

    /// Set while rendering previews so nothing makes noise.
    var suppressed = false

    private init() {}

    func play(_ cue: SoundCue) {
        guard Prefs.soundEnabled, !suppressed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[cue], now - last < 0.035 { return }
        lastPlayed[cue] = now
        guard prepare(), let buffer = buffer(for: cue), !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Float(max(0, min(1, Prefs.volume))) * 0.9
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func prepare() -> Bool {
        guard let format else { return false }
        if !configured {
            for _ in 0..<8 {
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
                players.append(node)
            }
            configured = true
        }
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                return false
            }
        }
        return true
    }

    private func buffer(for cue: SoundCue) -> AVAudioPCMBuffer? {
        if let cached = buffers[cue] { return cached }
        guard let format else { return nil }
        let notes = Self.recipe(for: cue)
        let total = notes.map { $0.start + $0.duration }.max() ?? 0.05
        let frames = AVAudioFrameCount(total * sampleRate) + 64
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { channel[i] = 0 }
        var noise = SeededRandom(seed: 99)
        for note in notes {
            let start = Int(note.start * sampleRate)
            let count = Int(note.duration * sampleRate)
            var phase = 0.0
            for i in 0..<count where start + i < Int(frames) {
                let t = Double(i) / sampleRate
                let progress = t / note.duration
                let freq = note.from + (note.to - note.from) * progress
                phase += 2 * .pi * freq / sampleRate
                let sample: Double
                switch note.wave {
                case .sine: sample = sin(phase)
                case .triangle: sample = 2 / .pi * asin(sin(phase))
                case .square: sample = sin(phase) >= 0 ? 0.6 : -0.6
                case .noise: sample = noise.double(-1...1)
                }
                let attack = min(1, t / 0.004)
                let release = pow(max(0, 1 - progress), note.curve)
                channel[start + i] += Float(sample * attack * release * note.gain)
            }
        }
        buffers[cue] = buffer
        return buffer
    }

    // MARK: Recipes

    enum Wave { case sine, triangle, square, noise }

    struct Note {
        var wave: Wave
        var from: Double
        var to: Double
        var start: Double
        var duration: Double
        var gain: Double
        var curve: Double = 1.6
    }

    static func tone(_ wave: Wave, _ from: Double, to: Double? = nil, at start: Double = 0, dur: Double, gain: Double = 0.3, curve: Double = 1.6) -> Note {
        Note(wave: wave, from: from, to: to ?? from, start: start, duration: dur, gain: gain, curve: curve)
    }

    static func arpeggio(_ wave: Wave, _ freqs: [Double], step: Double, length: Double, gain: Double) -> [Note] {
        freqs.enumerated().map { i, f in tone(wave, f, at: Double(i) * step, dur: length, gain: gain) }
    }

    static func recipe(for cue: SoundCue) -> [Note] {
        switch cue {
        case .tick: return [tone(.sine, 1900, dur: 0.022, gain: 0.12)]
        case .select: return [tone(.triangle, 880, to: 1320, dur: 0.06, gain: 0.25)]
        case .launch: return [tone(.square, 330, to: 990, dur: 0.14, gain: 0.12, curve: 1.2), tone(.sine, 660, to: 1980, at: 0.03, dur: 0.16, gain: 0.18)]
        case .jump: return [tone(.square, 360, to: 720, dur: 0.1, gain: 0.12)]
        case .land: return [tone(.noise, 1, dur: 0.035, gain: 0.08)]
        case .coin: return [tone(.square, 988, dur: 0.05, gain: 0.1), tone(.square, 1319, at: 0.05, dur: 0.14, gain: 0.1)]
        case .hit: return [tone(.square, 520, to: 480, dur: 0.05, gain: 0.14)]
        case .wall: return [tone(.triangle, 300, to: 280, dur: 0.04, gain: 0.22)]
        case .brick: return [tone(.square, 700, to: 520, dur: 0.06, gain: 0.11), tone(.noise, 1, dur: 0.02, gain: 0.05)]
        case .eat: return [tone(.triangle, 600, to: 1050, dur: 0.07, gain: 0.3)]
        case .bonus: return arpeggio(.square, [784, 988, 1175, 1568], step: 0.045, length: 0.08, gain: 0.1)
        case .merge: return [tone(.triangle, 523, to: 784, dur: 0.08, gain: 0.28)]
        case .slide: return [tone(.sine, 320, to: 240, dur: 0.045, gain: 0.18)]
        case .flag: return [tone(.triangle, 1046, to: 1175, dur: 0.06, gain: 0.25)]
        case .reveal: return [tone(.sine, 660, to: 990, dur: 0.07, gain: 0.22)]
        case .explode: return [tone(.noise, 1, dur: 0.55, gain: 0.32, curve: 2.4), tone(.sine, 110, to: 38, dur: 0.5, gain: 0.45)]
        case .lose: return [tone(.square, 440, to: 110, dur: 0.42, gain: 0.12, curve: 1.1)]
        case .win: return arpeggio(.triangle, [523, 659, 784, 1046, 1319], step: 0.07, length: 0.16, gain: 0.3)
        case .levelUp: return arpeggio(.square, [659, 784, 988, 1319], step: 0.06, length: 0.1, gain: 0.1)
        case .powerUp: return [tone(.sine, 400, to: 1600, dur: 0.2, gain: 0.25, curve: 1.0)]
        case .error: return [tone(.square, 170, to: 150, dur: 0.09, gain: 0.12)]
        case .ready: return [tone(.sine, 440, dur: 0.06, gain: 0.2)]
        case .go: return [tone(.sine, 880, dur: 0.11, gain: 0.25)]
        case .card: return [tone(.noise, 1, dur: 0.03, gain: 0.08), tone(.sine, 1400, to: 1100, dur: 0.025, gain: 0.08)]
        case .place: return [tone(.triangle, 700, to: 940, dur: 0.06, gain: 0.25)]
        case .harvest: return arpeggio(.triangle, [784, 1046], step: 0.05, length: 0.09, gain: 0.28)
        case .plant: return [tone(.triangle, 300, to: 430, dur: 0.07, gain: 0.3)]
        case .buy: return arpeggio(.square, [1046, 1568], step: 0.05, length: 0.08, gain: 0.1)
        case .flap: return [tone(.triangle, 480, to: 820, dur: 0.06, gain: 0.24)]
        case .note1: return [tone(.triangle, 392, dur: 0.3, gain: 0.32, curve: 1.2)]
        case .note2: return [tone(.triangle, 523.25, dur: 0.3, gain: 0.32, curve: 1.2)]
        case .note3: return [tone(.triangle, 659.25, dur: 0.3, gain: 0.32, curve: 1.2)]
        case .note4: return [tone(.triangle, 783.99, dur: 0.3, gain: 0.32, curve: 1.2)]
        case .march: return [tone(.square, 92, to: 78, dur: 0.08, gain: 0.16, curve: 1.3)]
        case .laser: return [tone(.square, 1500, to: 320, dur: 0.11, gain: 0.07, curve: 1.2)]
        case .thrust: return [tone(.noise, 1, dur: 0.09, gain: 0.05, curve: 0.8)]
        case .key: return [tone(.noise, 1, dur: 0.012, gain: 0.05), tone(.sine, 2300, to: 1700, dur: 0.012, gain: 0.05)]
        case .drop: return [tone(.sine, 520, to: 170, dur: 0.12, gain: 0.26, curve: 1.4)]
        }
    }
}

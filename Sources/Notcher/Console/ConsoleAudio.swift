import AVFoundation
import NotcherCore
import os

/// A single-producer, single-consumer sample queue shared with the audio thread.
final class SampleRing: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var readIndex = 0
    private var writeIndex = 0
    private var stored = 0
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deallocate()
        lock.deallocate()
    }

    var count: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return stored
    }

    func write(_ samples: [Float]) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        for s in samples {
            if stored == capacity {
                // Drop the oldest sample rather than block.
                readIndex = (readIndex + 1) % capacity
                stored -= 1
            }
            storage[writeIndex] = s
            writeIndex = (writeIndex + 1) % capacity
            stored += 1
        }
    }

    /// Fills `out` and pads with silence when the queue runs dry.
    func read(into out: UnsafeMutablePointer<Float>, count: Int, gain: Float) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let available = min(count, stored)
        for i in 0..<available {
            out[i] = storage[readIndex] * gain
            readIndex = (readIndex + 1) % capacity
        }
        stored -= available
        for i in available..<count { out[i] = 0 }
    }

    func clear() {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        readIndex = 0
        writeIndex = 0
        stored = 0
    }
}

/// Plays console audio. The emulator's resampler is nudged faster or slower
/// to keep about 60 ms queued, which avoids both gaps and drift.
final class ConsoleAudio: @unchecked Sendable {
    static let shared = ConsoleAudio()

    private let engine = AVAudioEngine()
    private let ring = SampleRing(capacity: 16_384)
    private var source: AVAudioSourceNode?
    private let gainBox = GainBox()
    private var running = false
    private var configObserver: NSObjectProtocol?
    /// Only touched by the producer (the emulation thread).
    private var smoothedFill: Double = 0

    /// Samples we aim to keep queued.
    static let target = Int(AudioResampler.outputRate * 0.06)

    final class GainBox: @unchecked Sendable {
        var value: Float = 0.8
    }

    private init() {}

    /// Main thread only.
    func start() {
        guard !running else { return }
        if source == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioResampler.outputRate, channels: 1) else { return }
            let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(ring: ring, gain: gainBox))
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
            // Headphones in or out: the engine stops and has to be restarted.
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                guard let self, self.running else { return }
                self.engine.prepare()
                try? self.engine.start()
            }
        }
        ring.clear()
        // A little silence up front so the first frames don't underrun.
        ring.write([Float](repeating: 0, count: Self.target))
        do {
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    /// Built here so the closure doesn't inherit any actor isolation: it runs
    /// on the real-time audio thread.
    private static func renderBlock(ring: SampleRing, gain: GainBox) -> AVAudioSourceNodeRenderBlock {
        { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            ring.read(into: data, count: Int(frameCount), gain: gain.value)
            // Duplicate into any extra channels.
            for extra in buffers.dropFirst() {
                extra.mData?.copyMemory(from: data, byteCount: Int(frameCount) * MemoryLayout<Float>.size)
            }
            return noErr
        }
    }

    /// Main thread only.
    func stop() {
        guard running else { return }
        engine.pause()
        ring.clear()
        running = false
    }

    func setVolume(_ volume: Double, muted: Bool) {
        gainBox.value = muted ? 0 : Float(max(0, min(1, volume))) * 0.9
    }

    /// Queues new samples and returns the rate multiplier the emulator
    /// should use next. Called from the emulation thread.
    func push(_ samples: [Float]) -> Double {
        ring.write(samples)
        let fill = Double(ring.count)
        smoothedFill += (fill - smoothedFill) * 0.05
        // Below target: produce slightly more samples per frame, and vice versa.
        let error = (Double(Self.target) - smoothedFill) / Double(Self.target)
        return 1 + max(-0.01, min(0.01, error * 0.02))
    }

    func flush() {
        ring.clear()
    }
}

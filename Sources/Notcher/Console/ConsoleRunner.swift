import AppKit
import CoreGraphics
import NotcherCore

/// Runs an emulator on its own thread so a heavy frame never stalls the
/// notch. The main thread decides how many frames to run each display
/// refresh; the picture comes back as a `CGImage`.
final class ConsoleRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.notcher.console", qos: .userInteractive)
    /// Only touched on `queue`.
    private let emulator: Emulator
    private let lock = NSLock()
    private var inFlight = false

    let system: ConsoleSystem
    let frameRate: Double
    let screen: FrameImage.Layout

    init(emulator: Emulator) {
        self.emulator = emulator
        system = emulator.system
        frameRate = emulator.frameRate
        screen = FrameImage.layout(for: emulator)
    }

    /// Runs `frames` frames, unless the previous batch is still going (then
    /// this refresh is skipped rather than queued). `done` gets the newest
    /// picture on the main thread.
    func run(frames: Int, buttons: ConsoleButtons, audio: Bool, done: @escaping @MainActor (CGImage?) -> Void) {
        lock.lock()
        if inFlight {
            lock.unlock()
            return
        }
        inFlight = true
        lock.unlock()
        queue.async { [self] in
            emulator.buttons = buttons
            for _ in 0..<frames { emulator.runFrame() }
            let samples = emulator.audio.drain()
            if audio {
                emulator.audio.rateAdjust = ConsoleAudio.shared.push(samples)
            }
            let image = FrameImage.make(emulator.frameBuffer, layout: screen)
            lock.lock()
            inFlight = false
            lock.unlock()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { done(image) }
            }
        }
    }

    /// Does something with the emulator between frames and waits for it.
    func sync<T>(_ body: (Emulator) throws -> T) rethrows -> T {
        try queue.sync { try body(emulator) }
    }

    /// The current picture, without running a frame.
    func snapshot() -> CGImage? {
        sync { FrameImage.make($0.frameBuffer, layout: screen) }
    }
}

/// Turns a console frame buffer into an image.
enum FrameImage {
    struct Layout: Equatable {
        var width: Int
        var height: Int
        /// Rows hidden at the top and bottom (NTSC TVs cropped the NES picture).
        var cropTop: Int
        var cropBottom: Int

        var visibleHeight: Int { height - cropTop - cropBottom }
    }

    static func layout(for emulator: Emulator) -> Layout {
        layout(for: emulator.system)
    }

    static func layout(for system: ConsoleSystem) -> Layout {
        switch system {
        case .nes: return Layout(width: 256, height: 240, cropTop: 8, cropBottom: 8)
        case .gameBoy, .gameBoyColor: return Layout(width: 160, height: 144, cropTop: 0, cropBottom: 0)
        }
    }

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func make(_ pixels: [UInt32], layout: Layout) -> CGImage? {
        let rows = layout.visibleHeight
        guard pixels.count >= layout.width * layout.height else { return nil }
        let data = pixels.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress else { return Data() }
            return Data(bytes: base + layout.cropTop * layout.width * 4, count: rows * layout.width * 4)
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        // 0xAARRGGBB words in little-endian memory.
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(
            width: layout.width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: layout.width * 4, space: colorSpace, bitmapInfo: info,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func load(_ data: Data) -> CGImage? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }
}

/// Decides how many console frames to run per display refresh. When the
/// display runs at (a multiple of) the console's rate, frames lock to it for
/// perfectly even motion and the audio resampler absorbs the tiny difference.
struct FramePacer {
    private var accumulator = 0.0
    private var smoothedDT = 1.0 / 60

    mutating func reset() {
        accumulator = 0
    }

    mutating func frames(for dt: Double, rate: Double) -> Int {
        smoothedDT += (dt - smoothedDT) * 0.05
        let displayHz = 1 / max(smoothedDT, 1.0 / 480)
        let ratio = displayHz / rate
        let multiple = max(1, ratio.rounded())
        if abs(ratio - multiple) / multiple < 0.012 {
            // Count refreshes, so a dropped one is caught up next time.
            let refreshes = max(1, (dt * displayHz).rounded())
            accumulator += refreshes / multiple
        } else {
            accumulator += dt * rate
        }
        accumulator = min(accumulator, 4)
        let n = Int(accumulator)
        accumulator -= Double(n)
        return n
    }
}

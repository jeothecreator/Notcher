import Foundation

/// A console Notcher can run ROMs for.
public enum ConsoleSystem: String, Codable, CaseIterable, Sendable {
    case nes
    case gameBoy
    case gameBoyColor

    public var title: String {
        switch self {
        case .nes: return "NES"
        case .gameBoy: return "Game Boy"
        case .gameBoyColor: return "Game Boy Color"
        }
    }

    public var shortTitle: String {
        switch self {
        case .nes: return "NES"
        case .gameBoy: return "GB"
        case .gameBoyColor: return "GBC"
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .nes: return ["nes"]
        case .gameBoy: return ["gb"]
        case .gameBoyColor: return ["gbc"]
        }
    }

    /// Every extension Notcher accepts, lower case.
    public static var allExtensions: [String] {
        allCases.flatMap(\.fileExtensions) + ["cgb", "sgb"]
    }
}

/// Buttons shared by every supported console.
public struct ConsoleButtons: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let a = ConsoleButtons(rawValue: 1 << 0)
    public static let b = ConsoleButtons(rawValue: 1 << 1)
    public static let select = ConsoleButtons(rawValue: 1 << 2)
    public static let start = ConsoleButtons(rawValue: 1 << 3)
    public static let up = ConsoleButtons(rawValue: 1 << 4)
    public static let down = ConsoleButtons(rawValue: 1 << 5)
    public static let left = ConsoleButtons(rawValue: 1 << 6)
    public static let right = ConsoleButtons(rawValue: 1 << 7)
}

public enum EmulatorError: Error, Equatable, CustomStringConvertible {
    case unrecognizedROM
    case unsupportedMapper(String)
    case corruptROM(String)
    case badSaveState

    public var description: String {
        switch self {
        case .unrecognizedROM: return "This file isn't a NES or Game Boy ROM."
        case .unsupportedMapper(let name): return "\(name) cartridges aren't supported yet."
        case .corruptROM(let reason): return "The ROM looks damaged: \(reason)."
        case .badSaveState: return "The saved state couldn't be read."
        }
    }
}

/// A running console. Everything is deterministic: the same ROM, input and
/// number of frames always produce the same picture and sound.
public protocol Emulator: AnyObject {
    var system: ConsoleSystem { get }
    /// Visible picture size in pixels.
    var screenWidth: Int { get }
    var screenHeight: Int { get }
    /// `screenWidth × screenHeight` pixels as 0xAARRGGBB.
    var frameBuffer: [UInt32] { get }
    /// Frames per second of the original hardware.
    var frameRate: Double { get }
    var buttons: ConsoleButtons { get set }
    /// Mono samples at `AudioResampler.outputRate`, filled while frames run.
    var audio: AudioResampler { get }

    func runFrame()
    func reset()

    /// Battery-backed cartridge RAM, or nil when the cartridge has none.
    var batteryRAM: [UInt8]? { get }
    func loadBatteryRAM(_ data: [UInt8])
    /// True when battery RAM changed since the last call to `markBatterySaved()`.
    var batteryDirty: Bool { get }
    func markBatterySaved()

    func saveState() -> [UInt8]
    func loadState(_ data: [UInt8]) throws
}

public enum EmulatorFactory {
    /// Builds the right console for a ROM image.
    public static func make(rom: [UInt8]) throws -> Emulator {
        switch ROMInfo.detect(rom) {
        case .nes?: return try NES(rom: rom)
        case .gameBoy?, .gameBoyColor?: return try GameBoy(rom: rom)
        case nil: throw EmulatorError.unrecognizedROM
        }
    }
}

// MARK: - Audio

/// Turns the console's high-rate sample stream into 44.1 kHz audio by
/// averaging, with a gentle high-pass to remove DC offset. `rateAdjust`
/// lets the player nudge the output rate to keep its buffer level steady.
public final class AudioResampler {
    public static let outputRate = 44_100.0

    public private(set) var samples: [Float] = []
    /// Output rate multiplier, kept within ±1% by the player.
    public var rateAdjust: Double = 1 {
        didSet { rateAdjust = min(1.01, max(0.99, rateAdjust)) }
    }

    private var inputRate: Double
    private var accumulator: Double = 0
    private var weight: Double = 0
    private var phase: Double = 0
    private var capacitor: Double = 0
    private let charge: Double

    public init(inputRate: Double) {
        self.inputRate = inputRate
        charge = pow(0.999_958, 4_194_304 / Self.outputRate)
        samples.reserveCapacity(2048)
    }

    var inputPerOutput: Double { inputRate / (Self.outputRate * rateAdjust) }

    /// Adds `count` input ticks at `level` (roughly -1…1).
    @inline(__always)
    public func push(_ level: Double, count: Int = 1) {
        var remaining = Double(count)
        let step = inputPerOutput
        while phase + remaining >= step {
            let take = step - phase
            accumulator += level * take
            weight += take
            remaining -= take
            emit()
        }
        accumulator += level * remaining
        weight += remaining
        phase += remaining
    }

    private func emit() {
        let value = weight > 0 ? accumulator / weight : 0
        let out = value - capacitor
        capacitor = value - out * charge
        samples.append(Float(max(-1, min(1, out))))
        accumulator = 0
        weight = 0
        phase = 0
    }

    /// Hands over everything produced so far.
    public func drain() -> [Float] {
        let out = samples
        samples.removeAll(keepingCapacity: true)
        return out
    }

    public func clear() {
        samples.removeAll(keepingCapacity: true)
        accumulator = 0
        weight = 0
        phase = 0
    }
}

// MARK: - Save states

/// Little-endian binary writer for save states.
public struct StateWriter {
    public private(set) var bytes: [UInt8] = []

    public init(tag: String, version: UInt8) {
        bytes.append(contentsOf: Array("NTCH".utf8))
        bytes.append(contentsOf: Array(tag.utf8.prefix(4)))
        bytes.append(version)
    }

    public mutating func u8(_ v: UInt8) { bytes.append(v) }
    public mutating func bool(_ v: Bool) { bytes.append(v ? 1 : 0) }
    public mutating func u16(_ v: UInt16) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8(v >> 8))
    }
    public mutating func u32(_ v: UInt32) {
        for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }
    public mutating func u64(_ v: UInt64) {
        for i in 0..<8 { bytes.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) }
    }
    public mutating func int(_ v: Int) { u64(UInt64(bitPattern: Int64(v))) }
    public mutating func double(_ v: Double) { u64(v.bitPattern) }
    public mutating func bytes(_ v: [UInt8]) {
        u32(UInt32(v.count))
        bytes.append(contentsOf: v)
    }
    public mutating func bytes(_ p: UnsafeMutablePointer<UInt8>, count: Int) {
        u32(UInt32(count))
        bytes.append(contentsOf: UnsafeBufferPointer(start: p, count: count))
    }
}

public struct StateReader {
    private let data: [UInt8]
    private var index = 0

    public init(_ bytes: [UInt8], tag: String, version: UInt8) throws {
        data = bytes
        let header = Array("NTCH".utf8) + Array(tag.utf8.prefix(4))
        guard bytes.count > header.count, Array(bytes.prefix(header.count)) == header else { throw EmulatorError.badSaveState }
        index = header.count
        guard try u8() == version else { throw EmulatorError.badSaveState }
    }

    public mutating func u8() throws -> UInt8 {
        guard index < data.count else { throw EmulatorError.badSaveState }
        defer { index += 1 }
        return data[index]
    }
    public mutating func bool() throws -> Bool { try u8() != 0 }
    public mutating func u16() throws -> UInt16 {
        let lo = UInt16(try u8()), hi = UInt16(try u8())
        return lo | hi << 8
    }
    public mutating func u32() throws -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(try u8()) << (8 * UInt32(i)) }
        return v
    }
    public mutating func u64() throws -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(try u8()) << (8 * UInt64(i)) }
        return v
    }
    public mutating func int() throws -> Int { Int(Int64(bitPattern: try u64())) }
    public mutating func double() throws -> Double { Double(bitPattern: try u64()) }
    public mutating func bytes() throws -> [UInt8] {
        let count = Int(try u32())
        guard index + count <= data.count else { throw EmulatorError.badSaveState }
        defer { index += count }
        return Array(data[index..<(index + count)])
    }
    /// Reads into an existing buffer; the stored length must match.
    public mutating func bytes(into p: UnsafeMutablePointer<UInt8>, count: Int) throws {
        let stored = Int(try u32())
        guard stored == count, index + count <= data.count else { throw EmulatorError.badSaveState }
        if count > 0 {
            data.withUnsafeBufferPointer { src in
                p.update(from: src.baseAddress! + index, count: count)
            }
        }
        index += count
    }
}

// MARK: - Memory

/// A fixed-size byte buffer without copy-on-write or bounds-check overhead
/// in the emulators' hot paths.
final class ByteBuffer {
    let pointer: UnsafeMutablePointer<UInt8>
    let count: Int

    init(count: Int, fill: UInt8 = 0) {
        self.count = max(1, count)
        pointer = .allocate(capacity: self.count)
        pointer.initialize(repeating: fill, count: self.count)
    }

    convenience init(_ bytes: [UInt8]) {
        self.init(count: bytes.count)
        load(bytes)
    }

    deinit {
        pointer.deallocate()
    }

    @inline(__always) subscript(_ i: Int) -> UInt8 {
        get { pointer[i] }
        set { pointer[i] = newValue }
    }

    var array: [UInt8] { Array(UnsafeBufferPointer(start: pointer, count: count)) }

    func load(_ bytes: [UInt8]) {
        let n = min(bytes.count, count)
        guard n > 0 else { return }
        bytes.withUnsafeBufferPointer { pointer.update(from: $0.baseAddress!, count: n) }
    }

    func fill(_ value: UInt8) {
        pointer.update(repeating: value, count: count)
    }
}

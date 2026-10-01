import Foundation

/// A Game Boy cartridge: ROM, optional RAM and the memory bank controller
/// (MBC1, MBC2, MBC3 with its real-time clock, or MBC5).
final class GBCartridge {
    enum Controller { case none, mbc1, mbc2, mbc3, mbc5 }

    static let supportedTypes: Set<UInt8> = [
        0x00, 0x01, 0x02, 0x03, 0x05, 0x06, 0x08, 0x09,
        0x0F, 0x10, 0x11, 0x12, 0x13, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E,
    ]
    static let batteryTypes: Set<UInt8> = [0x03, 0x06, 0x09, 0x0F, 0x10, 0x13, 0x1B, 0x1E]

    static func boardName(_ type: UInt8) -> String {
        switch type {
        case 0x00, 0x08, 0x09: return "ROM"
        case 0x01...0x03: return "MBC1"
        case 0x05, 0x06: return "MBC2"
        case 0x0F...0x13: return "MBC3"
        case 0x19...0x1E: return "MBC5"
        case 0x0B...0x0D: return "MMM01"
        case 0x20: return "MBC6"
        case 0x22: return "MBC7"
        case 0xFC: return "Pocket Camera"
        case 0xFE: return "HuC3"
        case 0xFF: return "HuC1"
        default: return String(format: "Type %02X", type)
        }
    }

    let rom: ByteBuffer
    let romBankCount: Int
    let ram: ByteBuffer
    let ramSize: Int
    let controller: Controller
    let hasBattery: Bool
    let hasRTC: Bool
    let rumble: Bool
    private(set) var dirty = false

    var ramEnabled = false
    var romBankLow = 1
    var bankHigh = 0
    var mode = 0
    var ramBank = 0
    var romBank9 = 0

    // MBC3 real-time clock. The counter is kept as "seconds at `rtcBaseTime`".
    var rtcSelect = -1
    var rtcLatched: [UInt8] = [0, 0, 0, 0, 0]
    var rtcLatchArmed = false
    var rtcBaseSeconds: Double = 0
    var rtcBaseTime: Double = 0
    var rtcHalted = false
    var rtcCarry = false
    var now: () -> Double = { Date().timeIntervalSince1970 }

    init(rom image: [UInt8]) throws {
        guard image.count >= 0x150 else { throw EmulatorError.corruptROM("too short") }
        let type = image[0x147]
        guard Self.supportedTypes.contains(type) else {
            throw EmulatorError.unsupportedMapper(Self.boardName(type))
        }
        // Round up to whole 16 KB banks, at least two.
        let banks = max(2, (image.count + 0x3FFF) / 0x4000)
        rom = ByteBuffer(count: banks * 0x4000, fill: 0xFF)
        rom.load(image)
        romBankCount = banks

        let kind: Controller
        switch type {
        case 0x01...0x03: kind = .mbc1
        case 0x05, 0x06: kind = .mbc2
        case 0x0F...0x13: kind = .mbc3
        case 0x19...0x1E: kind = .mbc5
        default: kind = .none
        }
        controller = kind
        hasBattery = Self.batteryTypes.contains(type)
        hasRTC = type == 0x0F || type == 0x10
        rumble = (0x1C...0x1E).contains(type)

        var size: Int
        switch image[0x149] {
        case 1: size = 0x800
        case 2: size = 0x2000
        case 3: size = 0x8000
        case 4: size = 0x20000
        case 5: size = 0x10000
        default: size = 0
        }
        if kind == .mbc2 { size = 0x200 }
        // Some homebrew declares RAM-less carts that still write to A000.
        if size == 0 && (type == 0x08 || type == 0x09 || type == 0x02 || type == 0x03) { size = 0x2000 }
        ramSize = size
        ram = ByteBuffer(count: max(size, 1), fill: 0xFF)
        rtcBaseTime = now()
    }

    // MARK: Access

    @inline(__always) func read(_ addr: UInt16) -> UInt8 {
        let a = Int(addr)
        if a < 0x4000 {
            if controller == .mbc1 && mode == 1 {
                return rom[((bankHigh << 5) % romBankCount) * 0x4000 + a]
            }
            return rom[a]
        }
        if a < 0x8000 {
            return rom[currentROMBank * 0x4000 + (a - 0x4000)]
        }
        // 0xA000-0xBFFF
        guard ramEnabled || controller == .none else { return 0xFF }
        switch controller {
        case .mbc2:
            return ram[a & 0x1FF] | 0xF0
        case .mbc3 where rtcSelect >= 0:
            return rtcLatched[rtcSelect]
        default:
            guard ramSize > 0 else { return 0xFF }
            return ram[(currentRAMBank * 0x2000 + (a - 0xA000)) % ramSize]
        }
    }

    var currentROMBank: Int {
        let bank: Int
        switch controller {
        case .none: bank = 1
        case .mbc1: bank = (bankHigh << 5) | romBankLow
        case .mbc2, .mbc3: bank = romBankLow
        case .mbc5: bank = (romBank9 << 8) | romBankLow
        }
        return bank % romBankCount
    }

    var currentRAMBank: Int {
        switch controller {
        case .mbc1: return mode == 1 ? bankHigh : 0
        case .mbc3, .mbc5: return ramBank
        default: return 0
        }
    }

    func write(_ addr: UInt16, _ value: UInt8) {
        let a = Int(addr)
        if a >= 0xA000 {
            guard ramEnabled || controller == .none else { return }
            switch controller {
            case .mbc2:
                ram[a & 0x1FF] = value & 0x0F
                dirty = true
            case .mbc3 where rtcSelect >= 0:
                writeRTC(rtcSelect, value)
                dirty = true
            default:
                guard ramSize > 0 else { return }
                ram[(currentRAMBank * 0x2000 + (a - 0xA000)) % ramSize] = value
                dirty = true
            }
            return
        }
        switch controller {
        case .none:
            break
        case .mbc1:
            switch a {
            case ..<0x2000: ramEnabled = value & 0x0F == 0x0A
            case ..<0x4000:
                romBankLow = Int(value & 0x1F)
                if romBankLow == 0 { romBankLow = 1 }
            case ..<0x6000: bankHigh = Int(value & 0x03)
            default: mode = Int(value & 1)
            }
        case .mbc2:
            if a < 0x4000 {
                if a & 0x100 == 0 {
                    ramEnabled = value & 0x0F == 0x0A
                } else {
                    romBankLow = Int(value & 0x0F)
                    if romBankLow == 0 { romBankLow = 1 }
                }
            }
        case .mbc3:
            switch a {
            case ..<0x2000: ramEnabled = value & 0x0F == 0x0A
            case ..<0x4000:
                romBankLow = Int(value & 0x7F)
                if romBankLow == 0 { romBankLow = 1 }
            case ..<0x6000:
                if value <= 0x07 {
                    ramBank = Int(value & 0x03)
                    rtcSelect = -1
                } else if hasRTC && (0x08...0x0C).contains(value) {
                    rtcSelect = Int(value) - 0x08
                }
            default:
                if value == 0 {
                    rtcLatchArmed = true
                } else if value == 1 && rtcLatchArmed {
                    latchRTC()
                    rtcLatchArmed = false
                } else {
                    rtcLatchArmed = false
                }
            }
        case .mbc5:
            switch a {
            case ..<0x2000: ramEnabled = value & 0x0F == 0x0A
            case ..<0x3000: romBankLow = Int(value)
            case ..<0x4000: romBank9 = Int(value & 1)
            case ..<0x6000: ramBank = Int(value & (rumble ? 0x07 : 0x0F))
            default: break
            }
        }
    }

    // MARK: RTC

    var rtcSeconds: Double {
        rtcHalted ? rtcBaseSeconds : rtcBaseSeconds + max(0, now() - rtcBaseTime)
    }

    private func latchRTC() {
        var total = Int(rtcSeconds)
        var days = total / 86_400
        if days > 511 {
            rtcCarry = true
            days %= 512
            total = days * 86_400 + total % 86_400
            rtcBaseSeconds = Double(total)
            rtcBaseTime = now()
        }
        rtcLatched[0] = UInt8(total % 60)
        rtcLatched[1] = UInt8((total / 60) % 60)
        rtcLatched[2] = UInt8((total / 3600) % 24)
        rtcLatched[3] = UInt8(days & 0xFF)
        rtcLatched[4] = UInt8((days >> 8) & 1) | (rtcHalted ? 0x40 : 0) | (rtcCarry ? 0x80 : 0)
    }

    private func writeRTC(_ register: Int, _ value: UInt8) {
        let total = Int(rtcSeconds)
        var s = total % 60, m = (total / 60) % 60, h = (total / 3600) % 24, d = (total / 86_400) % 512
        switch register {
        case 0: s = Int(value % 60)
        case 1: m = Int(value % 60)
        case 2: h = Int(value % 24)
        case 3: d = (d & 0x100) | Int(value)
        default:
            d = (d & 0xFF) | (Int(value & 1) << 8)
            rtcCarry = value & 0x80 != 0
            let halt = value & 0x40 != 0
            if halt != rtcHalted {
                rtcHalted = halt
            }
        }
        rtcBaseSeconds = Double(s + m * 60 + h * 3600 + d * 86_400)
        rtcBaseTime = now()
        rtcLatched[register] = value
    }

    // MARK: Battery

    /// Cartridge RAM, followed by 18 bytes of clock state on MBC3 timer carts.
    var batteryData: [UInt8]? {
        guard hasBattery else { return nil }
        var data = ramSize > 0 ? Array(UnsafeBufferPointer(start: ram.pointer, count: ramSize)) : []
        if hasRTC {
            var w = StateWriter(tag: "RTCK", version: 1)
            w.double(rtcSeconds)
            w.double(now())
            w.bool(rtcHalted)
            w.bool(rtcCarry)
            data += w.bytes.dropFirst(9)
        }
        return data
    }

    func loadBattery(_ data: [UInt8]) {
        if ramSize > 0 {
            ram.load(Array(data.prefix(ramSize)))
        }
        if hasRTC && data.count >= ramSize + 18 {
            let tail = Array("NTCHRTCK".utf8) + [1] + Array(data[ramSize..<(ramSize + 18)])
            if var r = try? StateReader(tail, tag: "RTCK", version: 1),
               let seconds = try? r.double(), let savedAt = try? r.double(),
               let halted = try? r.bool(), let carry = try? r.bool() {
                rtcHalted = halted
                rtcCarry = carry
                // Time kept passing while Notcher was closed.
                rtcBaseSeconds = halted ? seconds : seconds + max(0, now() - savedAt)
                rtcBaseTime = now()
            }
        }
        dirty = false
    }

    func markSaved() { dirty = false }

    // MARK: State

    func save(_ w: inout StateWriter) {
        w.bytes(ram.pointer, count: ram.count)
        w.bool(ramEnabled)
        w.int(romBankLow)
        w.int(bankHigh)
        w.int(mode)
        w.int(ramBank)
        w.int(romBank9)
        w.int(rtcSelect)
        w.bytes(rtcLatched)
        w.bool(rtcLatchArmed)
        w.double(rtcSeconds)
        w.bool(rtcHalted)
        w.bool(rtcCarry)
    }

    func load(_ r: inout StateReader) throws {
        try r.bytes(into: ram.pointer, count: ram.count)
        ramEnabled = try r.bool()
        romBankLow = try r.int()
        bankHigh = try r.int()
        mode = try r.int()
        ramBank = try r.int()
        romBank9 = try r.int()
        rtcSelect = try r.int()
        rtcLatched = try r.bytes()
        guard rtcLatched.count == 5 else { throw EmulatorError.badSaveState }
        rtcLatchArmed = try r.bool()
        rtcBaseSeconds = try r.double()
        rtcBaseTime = now()
        rtcHalted = try r.bool()
        rtcCarry = try r.bool()
        dirty = true
    }
}

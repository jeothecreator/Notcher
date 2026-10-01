import Foundation

/// An iNES cartridge with its mapper. Banks are tracked as offsets into PRG
/// (8 KB windows) and CHR (1 KB windows), which keeps every mapper simple.
final class NESCartridge {
    enum Mirroring: UInt8 { case horizontal, vertical, singleLow, singleHigh, fourScreen }

    static let supportedMappers: Set<Int> = [0, 1, 2, 3, 4, 7, 11, 66]

    static func boardName(_ mapper: Int) -> String {
        switch mapper {
        case 0: return "NROM"
        case 1: return "MMC1"
        case 2: return "UxROM"
        case 3: return "CNROM"
        case 4: return "MMC3"
        case 5: return "MMC5"
        case 7: return "AxROM"
        case 9: return "MMC2"
        case 10: return "MMC4"
        case 11: return "Color Dreams"
        case 66: return "GxROM"
        case 69: return "Sunsoft FME-7"
        default: return "Mapper \(mapper)"
        }
    }

    let mapper: Int
    let prg: ByteBuffer
    let chr: ByteBuffer
    let chrIsRAM: Bool
    let prgRAM = ByteBuffer(count: 0x2000)
    let hasBattery: Bool
    let fourScreen: Bool
    var mirroring: Mirroring
    private(set) var dirty = false

    var prgOffsets = [Int](repeating: 0, count: 4)
    var chrOffsets = [Int](repeating: 0, count: 8)

    // MMC1
    var shift: UInt8 = 0x10
    var control: UInt8 = 0x0C
    var chrBank0: UInt8 = 0
    var chrBank1: UInt8 = 0
    var prgBank: UInt8 = 0

    // MMC3
    var bankSelect: UInt8 = 0
    var bankRegisters = [Int](repeating: 0, count: 8)
    var irqLatch: UInt8 = 0
    var irqCounter: UInt8 = 0
    var irqReload = false
    var irqEnabled = false
    var irqPending = false

    // Simple latch mappers
    var latch: UInt8 = 0

    init(rom: [UInt8]) throws {
        guard rom.count >= 16, Array(rom[0..<4]) == ROMInfo.nesMagic else { throw EmulatorError.unrecognizedROM }
        let prgBanks = Int(rom[4])
        let chrBanks = Int(rom[5])
        let flags6 = rom[6], flags7 = rom[7]
        // Old dumps sometimes have junk in bytes 7-15; ignore the high nibble then.
        let dirtyHeader = rom[12] != 0 || rom[13] != 0 || rom[14] != 0 || rom[15] != 0
        let number = Int(flags6 >> 4) | (dirtyHeader ? 0 : Int(flags7 & 0xF0))
        guard Self.supportedMappers.contains(number) else {
            throw EmulatorError.unsupportedMapper(Self.boardName(number))
        }
        mapper = number
        hasBattery = flags6 & 0x02 != 0
        let four = flags6 & 0x08 != 0
        fourScreen = four
        mirroring = four ? .fourScreen : (flags6 & 0x01 != 0 ? .vertical : .horizontal)

        let trainer = flags6 & 0x04 != 0 ? 512 : 0
        let prgStart = 16 + trainer
        let prgSize = prgBanks * 0x4000
        guard prgBanks > 0, rom.count >= prgStart + prgSize else { throw EmulatorError.corruptROM("PRG data is missing") }
        prg = ByteBuffer(Array(rom[prgStart..<(prgStart + prgSize)]))
        if chrBanks == 0 {
            chr = ByteBuffer(count: 0x2000)
            chrIsRAM = true
        } else {
            let chrStart = prgStart + prgSize
            let chrSize = chrBanks * 0x2000
            let available = max(0, min(chrSize, rom.count - chrStart))
            guard available > 0 else { throw EmulatorError.corruptROM("CHR data is missing") }
            let data = Array(rom[chrStart..<(chrStart + available)]) + [UInt8](repeating: 0, count: chrSize - available)
            chr = ByteBuffer(data)
            chrIsRAM = false
        }
        resetBanks()
    }

    var prgBankCount8K: Int { prg.count / 0x2000 }
    var chrBankCount1K: Int { chr.count / 0x400 }

    func resetBanks() {
        shift = 0x10
        control = 0x0C
        chrBank0 = 0
        chrBank1 = 0
        prgBank = 0
        bankSelect = 0
        bankRegisters = [0, 2, 4, 5, 6, 7, 0, 1]
        irqLatch = 0
        irqCounter = 0
        irqReload = false
        irqEnabled = false
        irqPending = false
        latch = 0
        if !fourScreen && mapper == 1 { mirroring = .singleLow }
        updateBanks()
    }

    // MARK: Bank mapping

    private func setPRG32(_ bank: Int) {
        let base = bank * 4
        for i in 0..<4 { prgOffsets[i] = ((base + i) % prgBankCount8K) * 0x2000 }
    }

    private func setPRG16(_ slot: Int, _ bank: Int) {
        let base = bank * 2
        prgOffsets[slot * 2] = ((base) % prgBankCount8K) * 0x2000
        prgOffsets[slot * 2 + 1] = ((base + 1) % prgBankCount8K) * 0x2000
    }

    private func setPRG8(_ slot: Int, _ bank: Int) {
        prgOffsets[slot] = (((bank % prgBankCount8K) + prgBankCount8K) % prgBankCount8K) * 0x2000
    }

    private func setCHR8(_ bank: Int) {
        for i in 0..<8 { chrOffsets[i] = ((bank * 8 + i) % chrBankCount1K) * 0x400 }
    }

    private func setCHR4(_ slot: Int, _ bank: Int) {
        for i in 0..<4 { chrOffsets[slot * 4 + i] = ((bank * 4 + i) % chrBankCount1K) * 0x400 }
    }

    private func setCHR1(_ slot: Int, _ bank: Int) {
        chrOffsets[slot] = (bank % chrBankCount1K) * 0x400
    }

    func updateBanks() {
        let lastPRG16 = prg.count / 0x4000 - 1
        switch mapper {
        case 1:
            if !fourScreen {
                switch control & 3 {
                case 0: mirroring = .singleLow
                case 1: mirroring = .singleHigh
                case 2: mirroring = .vertical
                default: mirroring = .horizontal
                }
            }
            // 512 KB boards use CHR bit 4 to pick the PRG half.
            let outer = prg.count > 0x40000 ? Int(chrBank0 & 0x10) : 0
            let bank = Int(prgBank & 0x0F) | outer
            switch (control >> 2) & 3 {
            case 0, 1:
                setPRG32(bank >> 1)
            case 2:
                setPRG16(0, outer)
                setPRG16(1, bank)
            default:
                setPRG16(0, bank)
                setPRG16(1, (lastPRG16 & 0x0F) | outer)
            }
            if control & 0x10 == 0 {
                setCHR8(Int(chrBank0 >> 1))
            } else {
                setCHR4(0, Int(chrBank0))
                setCHR4(1, Int(chrBank1))
            }
        case 2:
            setPRG16(0, Int(latch))
            setPRG16(1, lastPRG16)
            setCHR8(0)
        case 3:
            setPRG32(0)
            if prg.count == 0x4000 { setPRG16(1, 0) }
            setCHR8(Int(latch & 3))
        case 4:
            let last = prgBankCount8K - 1
            if bankSelect & 0x40 == 0 {
                setPRG8(0, bankRegisters[6])
                setPRG8(2, last - 1)
            } else {
                setPRG8(0, last - 1)
                setPRG8(2, bankRegisters[6])
            }
            setPRG8(1, bankRegisters[7])
            setPRG8(3, last)
            let invert = bankSelect & 0x80 != 0 ? 4 : 0
            setCHR1(0 ^ invert, bankRegisters[0] & 0xFE)
            setCHR1(1 ^ invert, bankRegisters[0] | 1)
            setCHR1(2 ^ invert, bankRegisters[1] & 0xFE)
            setCHR1(3 ^ invert, bankRegisters[1] | 1)
            setCHR1(4 ^ invert, bankRegisters[2])
            setCHR1(5 ^ invert, bankRegisters[3])
            setCHR1(6 ^ invert, bankRegisters[4])
            setCHR1(7 ^ invert, bankRegisters[5])
        case 7:
            setPRG32(Int(latch & 0x07))
            setCHR8(0)
            mirroring = latch & 0x10 != 0 ? .singleHigh : .singleLow
        case 11:
            setPRG32(Int(latch & 0x03))
            setCHR8(Int(latch >> 4))
        case 66:
            setPRG32(Int((latch >> 4) & 0x03))
            setCHR8(Int(latch & 0x03))
        default: // NROM
            setPRG16(0, 0)
            setPRG16(1, lastPRG16)
            setCHR8(0)
        }
    }

    // MARK: CPU side

    @inline(__always) func cpuRead(_ addr: UInt16) -> UInt8? {
        if addr >= 0x8000 {
            let a = Int(addr) - 0x8000
            return prg[prgOffsets[a >> 13] + (a & 0x1FFF)]
        }
        if addr >= 0x6000 {
            return prgRAM[Int(addr) - 0x6000]
        }
        return nil
    }

    func cpuWrite(_ addr: UInt16, _ v: UInt8) {
        if addr < 0x8000 {
            if addr >= 0x6000 {
                prgRAM[Int(addr) - 0x6000] = v
                dirty = true
            }
            return
        }
        switch mapper {
        case 1:
            if v & 0x80 != 0 {
                shift = 0x10
                control |= 0x0C
                updateBanks()
                return
            }
            let complete = shift & 1 != 0
            shift = (shift >> 1) | ((v & 1) << 4)
            if complete {
                switch addr {
                case 0x8000...0x9FFF: control = shift
                case 0xA000...0xBFFF: chrBank0 = shift
                case 0xC000...0xDFFF: chrBank1 = shift
                default: prgBank = shift
                }
                shift = 0x10
                updateBanks()
            }
        case 4:
            let even = addr & 1 == 0
            switch addr {
            case 0x8000...0x9FFF:
                if even { bankSelect = v } else { bankRegisters[Int(bankSelect & 7)] = Int(v) }
                updateBanks()
            case 0xA000...0xBFFF:
                if even && !fourScreen { mirroring = v & 1 == 0 ? .vertical : .horizontal }
            case 0xC000...0xDFFF:
                if even { irqLatch = v } else { irqCounter = 0; irqReload = true }
            default:
                if even {
                    irqEnabled = false
                    irqPending = false
                } else {
                    irqEnabled = true
                }
            }
        case 2, 3, 7, 11, 66:
            latch = v
            updateBanks()
        default:
            break
        }
    }

    // MARK: PPU side

    @inline(__always) func ppuRead(_ addr: UInt16) -> UInt8 {
        let a = Int(addr & 0x1FFF)
        return chr[chrOffsets[a >> 10] + (a & 0x3FF)]
    }

    @inline(__always) func ppuWrite(_ addr: UInt16, _ v: UInt8) {
        guard chrIsRAM else { return }
        let a = Int(addr & 0x1FFF)
        chr[chrOffsets[a >> 10] + (a & 0x3FF)] = v
    }

    /// MMC3's scanline counter, clocked once per rendered line.
    func scanline() {
        guard mapper == 4 else { return }
        if irqCounter == 0 || irqReload {
            irqCounter = irqLatch
            irqReload = false
        } else {
            irqCounter -= 1
        }
        if irqCounter == 0 && irqEnabled {
            irqPending = true
        }
    }

    var irq: Bool { irqPending }

    // MARK: Battery & state

    var batteryData: [UInt8]? { hasBattery ? prgRAM.array : nil }

    func loadBattery(_ data: [UInt8]) {
        prgRAM.load(data)
        dirty = false
    }

    func markSaved() { dirty = false }

    func save(_ w: inout StateWriter) {
        w.bytes(prgRAM.pointer, count: prgRAM.count)
        if chrIsRAM { w.bytes(chr.pointer, count: chr.count) }
        w.u8(mirroring.rawValue)
        for v in [shift, control, chrBank0, chrBank1, prgBank, bankSelect, irqLatch, irqCounter, latch] { w.u8(v) }
        for v in bankRegisters { w.int(v) }
        w.bool(irqReload)
        w.bool(irqEnabled)
        w.bool(irqPending)
    }

    func load(_ r: inout StateReader) throws {
        try r.bytes(into: prgRAM.pointer, count: prgRAM.count)
        if chrIsRAM { try r.bytes(into: chr.pointer, count: chr.count) }
        guard let m = Mirroring(rawValue: try r.u8()) else { throw EmulatorError.badSaveState }
        mirroring = m
        shift = try r.u8(); control = try r.u8(); chrBank0 = try r.u8(); chrBank1 = try r.u8()
        prgBank = try r.u8(); bankSelect = try r.u8(); irqLatch = try r.u8(); irqCounter = try r.u8(); latch = try r.u8()
        for i in 0..<8 { bankRegisters[i] = try r.int() }
        irqReload = try r.bool()
        irqEnabled = try r.bool()
        irqPending = try r.bool()
        let savedMirroring = mirroring
        updateBanks()
        // MMC3 and fixed boards keep whatever mirroring the state recorded.
        if mapper != 1 && mapper != 7 { mirroring = savedMirroring }
        dirty = true
    }
}

import Foundation

/// A Game Boy, or a Game Boy Color when the cartridge asks for one. Acts as
/// the memory bus between the CPU, picture, sound, timer and cartridge.
public final class GameBoy: Emulator {
    public let system: ConsoleSystem
    public let screenWidth = GBPPU.width
    public let screenHeight = GBPPU.height
    public let frameRate = 4_194_304.0 / 70_224.0
    public let audio = AudioResampler(inputRate: 4_194_304)
    public var buttons: ConsoleButtons = [] {
        didSet {
            // Newly pressed buttons raise the joypad interrupt.
            if !buttons.subtracting(oldValue).isEmpty { interruptFlag |= 0x10 }
        }
    }

    public var frameBuffer: [UInt32] { ppu.frame }

    /// Shades used for original Game Boy games.
    public var monochromePalette: [UInt32] {
        get { ppu.dmgColors }
        set { if newValue.count == 4 { ppu.dmgColors = newValue } }
    }

    public static let greenPalette = GBPPU.greenShades
    public static let grayPalette = GBPPU.grayShades

    let cgb: Bool
    let cart: GBCartridge
    private(set) var cpu: GBCPU!
    private(set) var ppu: GBPPU!
    private(set) var apu: GBAPU!
    let wram = ByteBuffer(count: 0x8000)
    let hram = ByteBuffer(count: 0x7F)
    var wramBank = 1

    var interruptEnable: UInt8 = 0
    var interruptFlag: UInt8 = 0x01

    // Timer: DIV is the top byte of a 16-bit counter clocked every T-cycle.
    var divCounter: UInt16 = 0xABCC
    var tima: UInt8 = 0
    var tma: UInt8 = 0
    var tac: UInt8 = 0xF8
    var timaReload = false

    var serialData: UInt8 = 0
    var serialControl: UInt8 = 0x7E
    /// Bytes the game sent over the link port. Test ROMs report results here.
    public private(set) var serialOutput: [UInt8] = []

    var joypadSelect: UInt8 = 0x30

    var dmaActive = false
    var dmaSource: UInt16 = 0
    var dmaIndex = 0
    var dmaDelay = 0

    var hdmaSource: UInt16 = 0
    var hdmaDest: UInt16 = 0
    var hdmaRemaining: UInt8 = 0xFF
    var hdmaActive = false

    var doubleSpeed = false
    var speedArmed = false
    var frameDots = 0

    public init(rom: [UInt8]) throws {
        cart = try GBCartridge(rom: rom)
        let flag = rom[0x143]
        cgb = flag == 0x80 || flag == 0xC0
        system = cgb ? .gameBoyColor : .gameBoy
        apu = GBAPU(audio: audio)
        cpu = GBCPU(bus: self)
        ppu = GBPPU(bus: self, cgb: cgb)
        powerOn()
    }

    private func powerOn() {
        if cgb {
            cpu.a = 0x11; cpu.f = 0x80
            cpu.b = 0x00; cpu.c = 0x00
            cpu.d = 0xFF; cpu.e = 0x56
            cpu.h = 0x00; cpu.l = 0x0D
            divCounter = 0x1EA0
        } else {
            cpu.a = 0x01; cpu.f = 0xB0
            cpu.b = 0x00; cpu.c = 0x13
            cpu.d = 0x00; cpu.e = 0xD8
            cpu.h = 0x01; cpu.l = 0x4D
            divCounter = 0xABCC
        }
        cpu.sp = 0xFFFE
        cpu.pc = 0x0100
        wram.fill(0)
        hram.fill(0)
        if cgb {
            // A plain white CGB palette until the game sets its own.
            ppu.bgPalette.fill(0xFF)
            ppu.objPalette.fill(0xFF)
        }
    }

    public func reset() {
        let battery = batteryRAM
        cpu = GBCPU(bus: self)
        ppu = GBPPU(bus: self, cgb: cgb)
        interruptEnable = 0
        interruptFlag = 0x01
        tima = 0; tma = 0; tac = 0xF8
        timaReload = false
        dmaActive = false
        hdmaActive = false
        doubleSpeed = false
        speedArmed = false
        wramBank = 1
        joypadSelect = 0x30
        cart.romBankLow = 1
        cart.bankHigh = 0
        cart.mode = 0
        cart.ramBank = 0
        cart.romBank9 = 0
        cart.ramEnabled = false
        powerOn()
        if let battery { loadBatteryRAM(battery) }
        audio.clear()
    }

    // MARK: Frames

    public func runFrame() {
        ppu.frameReady = false
        frameDots = 0
        while !ppu.frameReady && frameDots < 70_224 {
            cpu.step()
        }
    }

    // MARK: Clock

    /// One M-cycle of everything except the CPU.
    @inline(__always) func tick() {
        if timaReload {
            timaReload = false
            tima = tma
            interruptFlag |= 0x04
        }
        let old = divCounter
        divCounter &+= 4
        let sequencerBit: UInt16 = doubleSpeed ? 0x2000 : 0x1000
        if old & sequencerBit != 0 && divCounter & sequencerBit == 0 {
            apu.frameSequencerTick()
        }
        if tac & 0x04 != 0 {
            let mask = timerMask
            if old & mask != 0 && divCounter & mask == 0 { incrementTIMA() }
        }
        if dmaActive { stepDMA() }
        let dots = doubleSpeed ? 2 : 4
        ppu.step(dots)
        apu.step(dots)
        frameDots += dots
    }

    private var timerMask: UInt16 {
        switch tac & 3 {
        case 0: return 0x200
        case 1: return 0x08
        case 2: return 0x20
        default: return 0x80
        }
    }

    private func incrementTIMA() {
        if tima == 0xFF {
            tima = 0
            timaReload = true
        } else {
            tima &+= 1
        }
    }

    func stop() {
        if cgb && speedArmed {
            doubleSpeed.toggle()
            speedArmed = false
            divCounter = 0
        }
    }

    // MARK: DMA

    private func stepDMA() {
        if dmaDelay > 0 {
            dmaDelay -= 1
            return
        }
        var source = dmaSource &+ UInt16(dmaIndex)
        if source >= 0xE000 { source &-= 0x2000 }
        ppu.oam[dmaIndex] = read(source)
        dmaIndex += 1
        if dmaIndex >= 160 { dmaActive = false }
    }

    private func copyHDMABlock() {
        for i in 0..<16 {
            let value = read(hdmaSource &+ UInt16(i))
            let dest = 0x8000 | ((hdmaDest &+ UInt16(i)) & 0x1FFF)
            ppu.writeVRAM(dest, value)
        }
        hdmaSource &+= 16
        hdmaDest = (hdmaDest &+ 16) & 0x1FF0
    }

    /// Called by the PPU each time a visible line enters HBlank.
    func hblank() {
        guard hdmaActive else { return }
        copyHDMABlock()
        if hdmaRemaining == 0 {
            hdmaActive = false
            hdmaRemaining = 0xFF
        } else {
            hdmaRemaining -= 1
        }
    }

    private func startHDMA(_ v: UInt8) {
        if hdmaActive && v & 0x80 == 0 {
            hdmaActive = false
            hdmaRemaining |= 0x80
            return
        }
        hdmaRemaining = v & 0x7F
        if v & 0x80 != 0 {
            hdmaActive = true
        } else {
            let blocks = Int(hdmaRemaining) + 1
            for _ in 0..<blocks { copyHDMABlock() }
            hdmaRemaining = 0xFF
            for _ in 0..<(blocks * (doubleSpeed ? 16 : 8)) { tick() }
        }
    }

    // MARK: Memory map

    @inline(__always) func read(_ addr: UInt16) -> UInt8 {
        switch addr >> 12 {
        case 0x0...0x7, 0xA, 0xB:
            return cart.read(addr)
        case 0x8, 0x9:
            return ppu.readVRAM(addr)
        case 0xC, 0xE:
            return wram[Int(addr & 0x0FFF)]
        case 0xD:
            return wram[wramBank * 0x1000 + Int(addr & 0x0FFF)]
        default:
            if addr < 0xFE00 { return wram[wramBank * 0x1000 + Int(addr & 0x0FFF)] }
            if addr < 0xFEA0 { return dmaActive && dmaDelay == 0 ? 0xFF : ppu.oam[Int(addr - 0xFE00)] }
            if addr < 0xFF00 { return 0xFF }
            if addr < 0xFF80 { return readIO(addr) }
            if addr < 0xFFFF { return hram[Int(addr - 0xFF80)] }
            return interruptEnable
        }
    }

    @inline(__always) func write(_ addr: UInt16, _ v: UInt8) {
        switch addr >> 12 {
        case 0x0...0x7, 0xA, 0xB:
            cart.write(addr, v)
        case 0x8, 0x9:
            ppu.writeVRAM(addr, v)
        case 0xC, 0xE:
            wram[Int(addr & 0x0FFF)] = v
        case 0xD:
            wram[wramBank * 0x1000 + Int(addr & 0x0FFF)] = v
        default:
            if addr < 0xFE00 {
                wram[wramBank * 0x1000 + Int(addr & 0x0FFF)] = v
            } else if addr < 0xFEA0 {
                if !(dmaActive && dmaDelay == 0) { ppu.oam[Int(addr - 0xFE00)] = v }
            } else if addr < 0xFF00 {
                return
            } else if addr < 0xFF80 {
                writeIO(addr, v)
            } else if addr < 0xFFFF {
                hram[Int(addr - 0xFF80)] = v
            } else {
                interruptEnable = v
            }
        }
    }

    private func readIO(_ addr: UInt16) -> UInt8 {
        switch addr & 0xFF {
        case 0x00:
            var result: UInt8 = 0xC0 | joypadSelect | 0x0F
            if joypadSelect & 0x10 == 0 {
                if buttons.contains(.right) { result &= ~0x01 }
                if buttons.contains(.left) { result &= ~0x02 }
                if buttons.contains(.up) { result &= ~0x04 }
                if buttons.contains(.down) { result &= ~0x08 }
            }
            if joypadSelect & 0x20 == 0 {
                if buttons.contains(.a) { result &= ~0x01 }
                if buttons.contains(.b) { result &= ~0x02 }
                if buttons.contains(.select) { result &= ~0x04 }
                if buttons.contains(.start) { result &= ~0x08 }
            }
            return result
        case 0x01: return serialData
        case 0x02: return serialControl | (cgb ? 0x7C : 0x7E)
        case 0x04: return UInt8(divCounter >> 8)
        case 0x05: return tima
        case 0x06: return tma
        case 0x07: return tac | 0xF8
        case 0x0F: return interruptFlag | 0xE0
        case 0x10...0x3F: return apu.read(addr)
        case 0x40...0x4B: return ppu.readRegister(addr)
        case 0x4D: return cgb ? (doubleSpeed ? 0x80 : 0) | (speedArmed ? 1 : 0) | 0x7E : 0xFF
        case 0x4F: return cgb ? UInt8(ppu.vramBank) | 0xFE : 0xFF
        case 0x55: return cgb ? hdmaRemaining : 0xFF
        case 0x68...0x6B: return cgb ? ppu.readPalette(addr) : 0xFF
        case 0x70: return cgb ? UInt8(wramBank) | 0xF8 : 0xFF
        default: return 0xFF
        }
    }

    private func writeIO(_ addr: UInt16, _ v: UInt8) {
        switch addr & 0xFF {
        case 0x00:
            joypadSelect = v & 0x30
        case 0x01:
            serialData = v
        case 0x02:
            serialControl = v
            if v & 0x81 == 0x81 {
                // No link partner: the transfer completes and reads back 0xFF.
                serialOutput.append(serialData)
                if serialOutput.count > 4096 { serialOutput.removeFirst(serialOutput.count - 4096) }
                serialData = 0xFF
                serialControl &= 0x7F
                interruptFlag |= 0x08
            }
        case 0x04:
            let old = divCounter
            divCounter = 0
            if tac & 0x04 != 0 && old & timerMask != 0 { incrementTIMA() }
            let sequencerBit: UInt16 = doubleSpeed ? 0x2000 : 0x1000
            if old & sequencerBit != 0 { apu.frameSequencerTick() }
        case 0x05:
            tima = v
            timaReload = false
        case 0x06:
            tma = v
        case 0x07:
            let oldSignal = tac & 0x04 != 0 && divCounter & timerMask != 0
            tac = v | 0xF8
            let newSignal = tac & 0x04 != 0 && divCounter & timerMask != 0
            if oldSignal && !newSignal { incrementTIMA() }
        case 0x0F:
            interruptFlag = v & 0x1F
        case 0x10...0x3F:
            apu.write(addr, v)
        case 0x46:
            ppu.dmaRegister = v
            dmaSource = UInt16(v) << 8
            dmaIndex = 0
            dmaDelay = 1
            dmaActive = true
        case 0x40...0x4B:
            ppu.writeRegister(addr, v)
        case 0x4D:
            if cgb { speedArmed = v & 1 != 0 }
        case 0x4F:
            if cgb { ppu.vramBank = Int(v & 1) }
        case 0x51:
            hdmaSource = UInt16(v) << 8 | (hdmaSource & 0xF0)
        case 0x52:
            hdmaSource = (hdmaSource & 0xFF00) | UInt16(v & 0xF0)
        case 0x53:
            hdmaDest = UInt16(v & 0x1F) << 8 | (hdmaDest & 0xF0)
        case 0x54:
            hdmaDest = (hdmaDest & 0x1F00) | UInt16(v & 0xF0)
        case 0x55:
            if cgb { startHDMA(v) }
        case 0x68...0x6B:
            if cgb { ppu.writePalette(addr, v) }
        case 0x70:
            if cgb { wramBank = max(1, Int(v & 7)) }
        default:
            break
        }
    }

    // MARK: Battery

    public var batteryRAM: [UInt8]? { cart.batteryData }

    public func loadBatteryRAM(_ data: [UInt8]) {
        cart.loadBattery(data)
    }

    public var batteryDirty: Bool { cart.hasBattery && cart.dirty }

    public func markBatterySaved() { cart.markSaved() }

    // MARK: Save states

    static let stateTag = "GBOY"
    static let stateVersion: UInt8 = 1

    public func saveState() -> [UInt8] {
        var w = StateWriter(tag: Self.stateTag, version: Self.stateVersion)
        w.bool(cgb)
        cpu.save(&w)
        ppu.save(&w)
        apu.save(&w)
        cart.save(&w)
        w.bytes(wram.pointer, count: wram.count)
        w.bytes(hram.pointer, count: hram.count)
        w.int(wramBank)
        w.u8(interruptEnable)
        w.u8(interruptFlag)
        w.u16(divCounter)
        w.u8(tima); w.u8(tma); w.u8(tac)
        w.bool(timaReload)
        w.u8(serialData); w.u8(serialControl)
        w.u8(joypadSelect)
        w.bool(dmaActive); w.u16(dmaSource); w.int(dmaIndex); w.int(dmaDelay)
        w.u16(hdmaSource); w.u16(hdmaDest); w.u8(hdmaRemaining); w.bool(hdmaActive)
        w.bool(doubleSpeed); w.bool(speedArmed)
        return w.bytes
    }

    public func loadState(_ data: [UInt8]) throws {
        let backup = saveState()
        do {
            try restore(data)
        } catch {
            // Leave the console exactly as it was.
            try? restore(backup)
            throw error
        }
        audio.clear()
    }

    private func restore(_ data: [UInt8]) throws {
        var r = try StateReader(data, tag: Self.stateTag, version: Self.stateVersion)
        guard try r.bool() == cgb else { throw EmulatorError.badSaveState }
        try cpu.load(&r)
        try ppu.load(&r)
        try apu.load(&r)
        try cart.load(&r)
        try r.bytes(into: wram.pointer, count: wram.count)
        try r.bytes(into: hram.pointer, count: hram.count)
        let bank = try r.int()
        wramBank = max(1, bank & 7)
        interruptEnable = try r.u8()
        interruptFlag = try r.u8()
        divCounter = try r.u16()
        tima = try r.u8(); tma = try r.u8(); tac = try r.u8()
        timaReload = try r.bool()
        serialData = try r.u8(); serialControl = try r.u8()
        joypadSelect = try r.u8()
        dmaActive = try r.bool(); dmaSource = try r.u16(); dmaIndex = try r.int(); dmaDelay = try r.int()
        hdmaSource = try r.u16(); hdmaDest = try r.u16(); hdmaRemaining = try r.u8(); hdmaActive = try r.bool()
        doubleSpeed = try r.bool(); speedArmed = try r.bool()
    }
}

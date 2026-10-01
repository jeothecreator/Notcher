import Foundation

/// A Nintendo Entertainment System (NTSC). Acts as the CPU's memory bus.
public final class NES: Emulator {
    public let system = ConsoleSystem.nes
    public let screenWidth = NESPPU.width
    public let screenHeight = NESPPU.height
    public let frameRate = 60.0988
    public let audio: AudioResampler
    public var buttons: ConsoleButtons = []

    public var frameBuffer: [UInt32] { ppu.frameArray }

    let cart: NESCartridge
    // Constants, so the hot path never retains or unwraps them.
    let cpu: NESCPU
    let ppu: NESPPU
    let apu: NESAPU
    let ram = ByteBuffer(count: 0x800)
    private let image: [UInt8]

    var controllerShift: UInt8 = 0
    var strobe = false
    var openBus: UInt8 = 0

    public init(rom: [UInt8]) throws {
        cart = try NESCartridge(rom: rom)
        image = rom
        let resampler = AudioResampler(inputRate: 1_789_773)
        audio = resampler
        cpu = NESCPU()
        ppu = NESPPU()
        apu = NESAPU(audio: resampler)
        cpu.bus = self
        ppu.bus = self
        apu.bus = self
        cpu.reset()
    }

    /// Like pressing Reset after power-on: everything returns to its starting
    /// state except the cartridge's work RAM (where battery saves live).
    public func reset() {
        let workRAM = cart.prgRAM.array
        if let fresh = try? NES(rom: image) {
            try? restore(fresh.saveState())
        }
        cart.prgRAM.load(workRAM)
        audio.clear()
    }

    var irqLine: Bool { apu.irq || cart.irq }

    // MARK: Frames

    public func runFrame() {
        ppu.frameComplete = false
        // Guard against games that turn rendering off: a frame is ~29,781 CPU cycles.
        let limit = cpu.cycles + 40_000
        while !ppu.frameComplete && cpu.cycles < limit {
            cpu.step()
        }
        apu.flushAudio()
    }

    /// One CPU cycle of PPU and APU time. Kept out of line on purpose: the
    /// CPU calls it from hundreds of places, and inlining three PPU dots into
    /// each of them would bloat the code far past the instruction cache.
    @inline(never) func tick() {
        ppu.step()
        ppu.step()
        ppu.step()
        apu.step()
    }

    // MARK: Memory map

    func read(_ addr: UInt16) -> UInt8 {
        let value: UInt8
        switch addr {
        case 0x0000...0x1FFF:
            value = ram[Int(addr & 0x07FF)]
        case 0x2000...0x3FFF:
            value = ppu.readRegister(addr)
        case 0x4015:
            value = (apu.readStatus() & 0xDF) | (openBus & 0x20)
        case 0x4016:
            let bit = controllerShift & 1
            if !strobe { controllerShift = (controllerShift >> 1) | 0x80 } else { controllerShift = buttons.rawValue }
            value = (openBus & 0xE0) | bit
        case 0x4017:
            value = (openBus & 0xE0)
        case 0x4000...0x401F:
            value = openBus
        default:
            value = cart.cpuRead(addr) ?? openBus
        }
        openBus = value
        return value
    }

    func write(_ addr: UInt16, _ v: UInt8) {
        openBus = v
        switch addr {
        case 0x0000...0x1FFF:
            ram[Int(addr & 0x07FF)] = v
        case 0x2000...0x3FFF:
            ppu.writeRegister(addr, v)
        case 0x4014:
            oamDMA(page: v)
        case 0x4016:
            strobe = v & 1 != 0
            if strobe { controllerShift = buttons.rawValue }
        case 0x4000...0x4017:
            apu.write(addr, v)
        case 0x4018...0x401F:
            break
        default:
            cart.cpuWrite(addr, v)
        }
    }

    /// Sample fetches for the DMC channel (no CPU stall is modelled).
    func dmcRead(_ addr: UInt16) -> UInt8 {
        cart.cpuRead(addr) ?? 0
    }

    /// $4014: copies a page into sprite memory, stalling the CPU 513/514 cycles.
    private func oamDMA(page: UInt8) {
        if cpu.cycles & 1 == 1 {
            cpu.cycles += 1
            tick()
        }
        cpu.cycles += 1
        tick()
        let base = UInt16(page) << 8
        for i in 0..<256 {
            cpu.cycles += 1
            tick()
            let value = read(base | UInt16(i))
            cpu.cycles += 1
            tick()
            ppu.writeRegister(0x2004, value)
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

    static let stateTag = "NES "
    static let stateVersion: UInt8 = 1

    public func saveState() -> [UInt8] {
        var w = StateWriter(tag: Self.stateTag, version: Self.stateVersion)
        w.int(cart.mapper)
        cpu.save(&w)
        ppu.save(&w)
        apu.save(&w)
        cart.save(&w)
        w.bytes(ram.pointer, count: ram.count)
        w.u8(controllerShift)
        w.bool(strobe)
        w.u8(openBus)
        return w.bytes
    }

    public func loadState(_ data: [UInt8]) throws {
        let backup = saveState()
        do {
            try restore(data)
        } catch {
            try? restore(backup)
            throw error
        }
        audio.clear()
    }

    private func restore(_ data: [UInt8]) throws {
        var r = try StateReader(data, tag: Self.stateTag, version: Self.stateVersion)
        guard try r.int() == cart.mapper else { throw EmulatorError.badSaveState }
        try cpu.load(&r)
        try ppu.load(&r)
        try apu.load(&r)
        try cart.load(&r)
        try r.bytes(into: ram.pointer, count: ram.count)
        controllerShift = try r.u8()
        strobe = try r.bool()
        openBus = try r.u8()
    }
}

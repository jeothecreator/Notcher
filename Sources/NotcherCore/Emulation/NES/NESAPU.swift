import Foundation

/// The 2A03's audio: two pulse channels, triangle, noise and the delta
/// modulation channel, mixed with the hardware's non-linear curves.
final class NESAPU {
    static let lengthTable: [UInt8] = [
        10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
        12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
    ]
    static let dutyTable: [UInt8] = [0b0100_0000, 0b0110_0000, 0b0111_1000, 0b1001_1111]
    static let triangleTable: [UInt8] = [
        15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]
    static let noisePeriods: [Int] = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]
    static let dmcRates: [Int] = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54]

    static let pulseMix: [Double] = (0..<31).map { $0 == 0 ? 0 : 95.52 / (8128.0 / Double($0) + 100) }
    static let tndMix: [Double] = (0..<203).map { $0 == 0 ? 0 : 163.67 / (24329.0 / Double($0) + 100) }

    struct Envelope {
        var start = false
        var loop = false
        var constant = false
        var period: UInt8 = 0
        var divider: UInt8 = 0
        var decay: UInt8 = 0

        mutating func clock() {
            if start {
                start = false
                decay = 15
                divider = period
            } else if divider == 0 {
                divider = period
                if decay > 0 {
                    decay -= 1
                } else if loop {
                    decay = 15
                }
            } else {
                divider -= 1
            }
        }

        var volume: UInt8 { constant ? period : decay }
    }

    struct Pulse {
        let ones: Bool // pulse 1 negates with one's complement
        var enabled = false
        var duty: UInt8 = 0
        var step: UInt8 = 0
        var timerPeriod = 0
        var timer = 0
        var length: UInt8 = 0
        var envelope = Envelope()
        var sweepEnabled = false
        var sweepPeriod: UInt8 = 0
        var sweepNegate = false
        var sweepShift: UInt8 = 0
        var sweepDivider: UInt8 = 0
        var sweepReload = false

        var targetPeriod: Int {
            let change = timerPeriod >> Int(sweepShift)
            if sweepNegate {
                return timerPeriod - change - (ones ? 1 : 0)
            }
            return timerPeriod + change
        }

        var muted: Bool { timerPeriod < 8 || targetPeriod > 0x7FF }

        @inline(__always) mutating func clockTimer() {
            if timer == 0 {
                timer = timerPeriod
                step = (step &- 1) & 7
            } else {
                timer -= 1
            }
        }

        mutating func clockSweep() {
            if sweepDivider == 0 && sweepEnabled && sweepShift > 0 && !muted {
                timerPeriod = max(0, targetPeriod)
            }
            if sweepDivider == 0 || sweepReload {
                sweepDivider = sweepPeriod
                sweepReload = false
            } else {
                sweepDivider -= 1
            }
        }

        mutating func clockLength() {
            if !envelope.loop && length > 0 { length -= 1 }
        }

        @inline(__always) var output: UInt8 {
            guard length > 0, !muted else { return 0 }
            guard (NESAPU.dutyTable[Int(duty)] >> step) & 1 != 0 else { return 0 }
            return envelope.volume
        }
    }

    struct Triangle {
        var enabled = false
        var timerPeriod = 0
        var timer = 0
        var step = 0
        var length: UInt8 = 0
        var control = false
        var linearPeriod: UInt8 = 0
        var linear: UInt8 = 0
        var linearReload = false

        @inline(__always) mutating func clockTimer() {
            if timer == 0 {
                timer = timerPeriod
                if length > 0 && linear > 0 && timerPeriod >= 2 {
                    step = (step + 1) & 31
                }
            } else {
                timer -= 1
            }
        }

        mutating func clockLinear() {
            if linearReload {
                linear = linearPeriod
            } else if linear > 0 {
                linear -= 1
            }
            if !control { linearReload = false }
        }

        mutating func clockLength() {
            if !control && length > 0 { length -= 1 }
        }

        @inline(__always) var output: UInt8 { NESAPU.triangleTable[step] }
    }

    struct Noise {
        var enabled = false
        var mode = false
        var timerPeriod = 4
        var timer = 0
        var shift: UInt16 = 1
        var length: UInt8 = 0
        var envelope = Envelope()

        @inline(__always) mutating func clockTimer() {
            if timer == 0 {
                timer = timerPeriod
                let other = mode ? (shift >> 6) & 1 : (shift >> 1) & 1
                let feedback = (shift & 1) ^ other
                shift = (shift >> 1) | (feedback << 14)
            } else {
                timer -= 1
            }
        }

        mutating func clockLength() {
            if !envelope.loop && length > 0 { length -= 1 }
        }

        @inline(__always) var output: UInt8 {
            guard length > 0, shift & 1 == 0 else { return 0 }
            return envelope.volume
        }
    }

    struct DMC {
        var irqEnabled = false
        var loop = false
        var rate = 428
        var timer = 0
        var output: UInt8 = 0
        var sampleAddress: UInt16 = 0xC000
        var sampleLength = 1
        var currentAddress: UInt16 = 0xC000
        var bytesRemaining = 0
        var buffer: UInt8 = 0
        var bufferEmpty = true
        var shiftRegister: UInt8 = 0
        var bitsRemaining = 8
        var silence = true
        var irq = false
    }

    unowned(unsafe) let bus: NES
    let audio: AudioResampler

    var pulse1 = Pulse(ones: true)
    var pulse2 = Pulse(ones: false)
    var triangle = Triangle()
    var noise = Noise()
    var dmc = DMC()

    var frameMode5 = false
    var frameIRQInhibit = false
    var frameIRQ = false
    var frameCycle = 0
    var evenCycle = false

    init(bus: NES, audio: AudioResampler) {
        self.bus = bus
        self.audio = audio
    }

    var irq: Bool { frameIRQ || dmc.irq }

    // MARK: Clock

    /// One CPU cycle.
    @inline(__always) func step() {
        triangle.clockTimer()
        if evenCycle {
            pulse1.clockTimer()
            pulse2.clockTimer()
            noise.clockTimer()
        }
        evenCycle.toggle()
        stepDMC()
        stepFrameCounter()

        let p = Int(pulse1.output) + Int(pulse2.output)
        let tnd = 3 * Int(triangle.output) + 2 * Int(noise.output) + Int(dmc.output)
        let level = NESAPU.pulseMix[p] + NESAPU.tndMix[min(tnd, 202)]
        audio.push(level * 1.4, count: 1)
    }

    private func stepFrameCounter() {
        frameCycle += 1
        if frameMode5 {
            switch frameCycle {
            case 7457: quarterFrame()
            case 14913: quarterFrame(); halfFrame()
            case 22371: quarterFrame()
            case 37281: quarterFrame(); halfFrame()
            case 37282: frameCycle = 0
            default: break
            }
        } else {
            switch frameCycle {
            case 7457: quarterFrame()
            case 14913: quarterFrame(); halfFrame()
            case 22371: quarterFrame()
            case 29828:
                if !frameIRQInhibit { frameIRQ = true }
            case 29829:
                quarterFrame()
                halfFrame()
                if !frameIRQInhibit { frameIRQ = true }
            case 29830:
                if !frameIRQInhibit { frameIRQ = true }
                frameCycle = 0
            default: break
            }
        }
    }

    private func quarterFrame() {
        pulse1.envelope.clock()
        pulse2.envelope.clock()
        noise.envelope.clock()
        triangle.clockLinear()
    }

    private func halfFrame() {
        pulse1.clockLength()
        pulse2.clockLength()
        triangle.clockLength()
        noise.clockLength()
        pulse1.clockSweep()
        pulse2.clockSweep()
    }

    private func stepDMC() {
        if dmc.bufferEmpty && dmc.bytesRemaining > 0 {
            dmc.buffer = bus.dmcRead(dmc.currentAddress)
            dmc.bufferEmpty = false
            dmc.currentAddress = dmc.currentAddress == 0xFFFF ? 0x8000 : dmc.currentAddress + 1
            dmc.bytesRemaining -= 1
            if dmc.bytesRemaining == 0 {
                if dmc.loop {
                    dmc.currentAddress = dmc.sampleAddress
                    dmc.bytesRemaining = dmc.sampleLength
                } else if dmc.irqEnabled {
                    dmc.irq = true
                }
            }
        }
        if dmc.timer > 0 {
            dmc.timer -= 1
            return
        }
        dmc.timer = dmc.rate - 1
        if !dmc.silence {
            if dmc.shiftRegister & 1 != 0 {
                if dmc.output <= 125 { dmc.output += 2 }
            } else {
                if dmc.output >= 2 { dmc.output -= 2 }
            }
        }
        dmc.shiftRegister >>= 1
        dmc.bitsRemaining -= 1
        if dmc.bitsRemaining <= 0 {
            dmc.bitsRemaining = 8
            if dmc.bufferEmpty {
                dmc.silence = true
            } else {
                dmc.silence = false
                dmc.shiftRegister = dmc.buffer
                dmc.bufferEmpty = true
            }
        }
    }

    // MARK: Registers

    func readStatus() -> UInt8 {
        var v: UInt8 = 0
        if pulse1.length > 0 { v |= 0x01 }
        if pulse2.length > 0 { v |= 0x02 }
        if triangle.length > 0 { v |= 0x04 }
        if noise.length > 0 { v |= 0x08 }
        if dmc.bytesRemaining > 0 { v |= 0x10 }
        if frameIRQ { v |= 0x40 }
        if dmc.irq { v |= 0x80 }
        frameIRQ = false
        return v
    }

    func write(_ addr: UInt16, _ v: UInt8) {
        switch addr {
        case 0x4000: writeControl(&pulse1, v)
        case 0x4001: writeSweep(&pulse1, v)
        case 0x4002: pulse1.timerPeriod = (pulse1.timerPeriod & 0x700) | Int(v)
        case 0x4003: writeTimerHigh(&pulse1, v)
        case 0x4004: writeControl(&pulse2, v)
        case 0x4005: writeSweep(&pulse2, v)
        case 0x4006: pulse2.timerPeriod = (pulse2.timerPeriod & 0x700) | Int(v)
        case 0x4007: writeTimerHigh(&pulse2, v)
        case 0x4008:
            triangle.control = v & 0x80 != 0
            triangle.linearPeriod = v & 0x7F
        case 0x400A:
            triangle.timerPeriod = (triangle.timerPeriod & 0x700) | Int(v)
        case 0x400B:
            triangle.timerPeriod = (triangle.timerPeriod & 0xFF) | Int(v & 7) << 8
            if triangle.enabled { triangle.length = NESAPU.lengthTable[Int(v >> 3)] }
            triangle.linearReload = true
        case 0x400C:
            noise.envelope.loop = v & 0x20 != 0
            noise.envelope.constant = v & 0x10 != 0
            noise.envelope.period = v & 0x0F
        case 0x400E:
            noise.mode = v & 0x80 != 0
            noise.timerPeriod = NESAPU.noisePeriods[Int(v & 0x0F)] / 2
        case 0x400F:
            if noise.enabled { noise.length = NESAPU.lengthTable[Int(v >> 3)] }
            noise.envelope.start = true
        case 0x4010:
            dmc.irqEnabled = v & 0x80 != 0
            dmc.loop = v & 0x40 != 0
            dmc.rate = NESAPU.dmcRates[Int(v & 0x0F)]
            if !dmc.irqEnabled { dmc.irq = false }
        case 0x4011:
            dmc.output = v & 0x7F
        case 0x4012:
            dmc.sampleAddress = 0xC000 | (UInt16(v) << 6)
        case 0x4013:
            dmc.sampleLength = Int(v) * 16 + 1
        case 0x4015:
            pulse1.enabled = v & 0x01 != 0
            pulse2.enabled = v & 0x02 != 0
            triangle.enabled = v & 0x04 != 0
            noise.enabled = v & 0x08 != 0
            if !pulse1.enabled { pulse1.length = 0 }
            if !pulse2.enabled { pulse2.length = 0 }
            if !triangle.enabled { triangle.length = 0 }
            if !noise.enabled { noise.length = 0 }
            dmc.irq = false
            if v & 0x10 == 0 {
                dmc.bytesRemaining = 0
            } else if dmc.bytesRemaining == 0 {
                dmc.currentAddress = dmc.sampleAddress
                dmc.bytesRemaining = dmc.sampleLength
            }
        case 0x4017:
            frameMode5 = v & 0x80 != 0
            frameIRQInhibit = v & 0x40 != 0
            if frameIRQInhibit { frameIRQ = false }
            frameCycle = 0
            if frameMode5 {
                quarterFrame()
                halfFrame()
            }
        default:
            break
        }
    }

    private func writeControl(_ p: inout Pulse, _ v: UInt8) {
        p.duty = v >> 6
        p.envelope.loop = v & 0x20 != 0
        p.envelope.constant = v & 0x10 != 0
        p.envelope.period = v & 0x0F
    }

    private func writeSweep(_ p: inout Pulse, _ v: UInt8) {
        p.sweepEnabled = v & 0x80 != 0
        p.sweepPeriod = (v >> 4) & 7
        p.sweepNegate = v & 0x08 != 0
        p.sweepShift = v & 7
        p.sweepReload = true
    }

    private func writeTimerHigh(_ p: inout Pulse, _ v: UInt8) {
        p.timerPeriod = (p.timerPeriod & 0xFF) | Int(v & 7) << 8
        if p.enabled { p.length = NESAPU.lengthTable[Int(v >> 3)] }
        p.step = 0
        p.envelope.start = true
    }

    // MARK: State

    private func saveEnvelope(_ e: Envelope, _ w: inout StateWriter) {
        w.bool(e.start); w.bool(e.loop); w.bool(e.constant); w.u8(e.period); w.u8(e.divider); w.u8(e.decay)
    }

    private func loadEnvelope(_ r: inout StateReader) throws -> Envelope {
        var e = Envelope()
        e.start = try r.bool(); e.loop = try r.bool(); e.constant = try r.bool()
        e.period = try r.u8(); e.divider = try r.u8(); e.decay = try r.u8()
        return e
    }

    private func savePulse(_ p: Pulse, _ w: inout StateWriter) {
        w.bool(p.enabled); w.u8(p.duty); w.u8(p.step); w.int(p.timerPeriod); w.int(p.timer); w.u8(p.length)
        saveEnvelope(p.envelope, &w)
        w.bool(p.sweepEnabled); w.u8(p.sweepPeriod); w.bool(p.sweepNegate); w.u8(p.sweepShift)
        w.u8(p.sweepDivider); w.bool(p.sweepReload)
    }

    private func loadPulse(_ p: inout Pulse, _ r: inout StateReader) throws {
        p.enabled = try r.bool(); p.duty = try r.u8() & 3; p.step = try r.u8() & 7
        p.timerPeriod = try r.int(); p.timer = try r.int(); p.length = try r.u8()
        p.envelope = try loadEnvelope(&r)
        p.sweepEnabled = try r.bool(); p.sweepPeriod = try r.u8(); p.sweepNegate = try r.bool()
        p.sweepShift = try r.u8() & 7; p.sweepDivider = try r.u8(); p.sweepReload = try r.bool()
    }

    func save(_ w: inout StateWriter) {
        savePulse(pulse1, &w)
        savePulse(pulse2, &w)
        w.bool(triangle.enabled); w.int(triangle.timerPeriod); w.int(triangle.timer); w.int(triangle.step)
        w.u8(triangle.length); w.bool(triangle.control); w.u8(triangle.linearPeriod); w.u8(triangle.linear)
        w.bool(triangle.linearReload)
        w.bool(noise.enabled); w.bool(noise.mode); w.int(noise.timerPeriod); w.int(noise.timer)
        w.u16(noise.shift); w.u8(noise.length)
        saveEnvelope(noise.envelope, &w)
        w.bool(dmc.irqEnabled); w.bool(dmc.loop); w.int(dmc.rate); w.int(dmc.timer); w.u8(dmc.output)
        w.u16(dmc.sampleAddress); w.int(dmc.sampleLength); w.u16(dmc.currentAddress); w.int(dmc.bytesRemaining)
        w.u8(dmc.buffer); w.bool(dmc.bufferEmpty); w.u8(dmc.shiftRegister); w.int(dmc.bitsRemaining)
        w.bool(dmc.silence); w.bool(dmc.irq)
        w.bool(frameMode5); w.bool(frameIRQInhibit); w.bool(frameIRQ); w.int(frameCycle); w.bool(evenCycle)
    }

    func load(_ r: inout StateReader) throws {
        try loadPulse(&pulse1, &r)
        try loadPulse(&pulse2, &r)
        triangle.enabled = try r.bool(); triangle.timerPeriod = try r.int(); triangle.timer = try r.int()
        triangle.step = try r.int() & 31
        triangle.length = try r.u8(); triangle.control = try r.bool(); triangle.linearPeriod = try r.u8()
        triangle.linear = try r.u8(); triangle.linearReload = try r.bool()
        noise.enabled = try r.bool(); noise.mode = try r.bool(); noise.timerPeriod = try r.int(); noise.timer = try r.int()
        noise.shift = try r.u16(); noise.length = try r.u8()
        noise.envelope = try loadEnvelope(&r)
        dmc.irqEnabled = try r.bool(); dmc.loop = try r.bool(); dmc.rate = try r.int(); dmc.timer = try r.int()
        dmc.output = try r.u8()
        dmc.sampleAddress = try r.u16(); dmc.sampleLength = try r.int(); dmc.currentAddress = try r.u16()
        dmc.bytesRemaining = try r.int()
        dmc.buffer = try r.u8(); dmc.bufferEmpty = try r.bool(); dmc.shiftRegister = try r.u8()
        dmc.bitsRemaining = try r.int()
        dmc.silence = try r.bool(); dmc.irq = try r.bool()
        frameMode5 = try r.bool(); frameIRQInhibit = try r.bool(); frameIRQ = try r.bool()
        frameCycle = try r.int(); evenCycle = try r.bool()
    }
}

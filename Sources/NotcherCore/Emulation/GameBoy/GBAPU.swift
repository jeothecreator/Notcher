import Foundation

/// Game Boy sound: two pulse channels (one with sweep), a wave channel and a
/// noise channel, mixed to mono.
final class GBAPU {
    struct Pulse {
        var enabled = false
        var dacEnabled = false
        var duty: Int = 0
        var dutyStep = 0
        var length = 0
        var lengthEnabled = false
        var frequency = 0
        var timer = 0
        var volume = 0
        var envelopeInitial = 0
        var envelopeUp = false
        var envelopePeriod = 0
        var envelopeTimer = 0
        // Sweep (channel 1 only)
        var sweepPeriod = 0
        var sweepNegate = false
        var sweepShift = 0
        var sweepTimer = 0
        var sweepEnabled = false
        var shadow = 0

        static let patterns: [UInt8] = [0b0000_0001, 0b1000_0001, 0b1000_0111, 0b0111_1110]

        @inline(__always) mutating func step(_ cycles: Int) {
            timer -= cycles
            while timer <= 0 {
                timer += (2048 - frequency) * 4
                dutyStep = (dutyStep + 1) & 7
            }
        }

        @inline(__always) var output: Int {
            guard enabled else { return 0 }
            return (Pulse.patterns[duty] >> UInt8(7 - dutyStep)) & 1 != 0 ? volume : 0
        }

        mutating func clockLength() {
            if lengthEnabled && length > 0 {
                length -= 1
                if length == 0 { enabled = false }
            }
        }

        mutating func clockEnvelope() {
            guard envelopePeriod != 0 else { return }
            envelopeTimer -= 1
            if envelopeTimer <= 0 {
                envelopeTimer = envelopePeriod
                if envelopeUp && volume < 15 { volume += 1 }
                if !envelopeUp && volume > 0 { volume -= 1 }
            }
        }

        mutating func sweepCalculation() -> Int {
            let delta = shadow >> sweepShift
            let next = sweepNegate ? shadow - delta : shadow + delta
            if next > 2047 { enabled = false }
            return next
        }

        mutating func clockSweep() {
            sweepTimer -= 1
            guard sweepTimer <= 0 else { return }
            sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod
            guard sweepEnabled && sweepPeriod != 0 else { return }
            let next = sweepCalculation()
            if next <= 2047 && sweepShift != 0 {
                shadow = next
                frequency = next
                _ = sweepCalculation()
            }
        }

        mutating func trigger(hasSweep: Bool) {
            enabled = dacEnabled
            if length == 0 { length = 64 }
            timer = (2048 - frequency) * 4
            volume = envelopeInitial
            envelopeTimer = envelopePeriod
            if hasSweep {
                shadow = frequency
                sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod
                sweepEnabled = sweepPeriod != 0 || sweepShift != 0
                if sweepShift != 0 { _ = sweepCalculation() }
            }
        }
    }

    struct Wave {
        var enabled = false
        var dacEnabled = false
        var length = 0
        var lengthEnabled = false
        var frequency = 0
        var timer = 0
        var position = 0
        var volumeCode = 0
        var sample: UInt8 = 0

        mutating func clockLength() {
            if lengthEnabled && length > 0 {
                length -= 1
                if length == 0 { enabled = false }
            }
        }
    }

    struct Noise {
        var enabled = false
        var dacEnabled = false
        var length = 0
        var lengthEnabled = false
        var volume = 0
        var envelopeInitial = 0
        var envelopeUp = false
        var envelopePeriod = 0
        var envelopeTimer = 0
        var shift = 0
        var narrow = false
        var divisor = 0
        var timer = 0
        var lfsr: UInt16 = 0x7FFF

        static let divisors = [8, 16, 32, 48, 64, 80, 96, 112]

        var period: Int { Noise.divisors[divisor] << shift }

        @inline(__always) mutating func step(_ cycles: Int) {
            guard shift < 14 else { return }
            timer -= cycles
            while timer <= 0 {
                timer += period
                let bit = (lfsr ^ (lfsr >> 1)) & 1
                lfsr = (lfsr >> 1) | (bit << 14)
                if narrow { lfsr = (lfsr & ~0x40) | (bit << 6) }
            }
        }

        @inline(__always) var output: Int {
            guard enabled else { return 0 }
            return lfsr & 1 == 0 ? volume : 0
        }

        mutating func clockLength() {
            if lengthEnabled && length > 0 {
                length -= 1
                if length == 0 { enabled = false }
            }
        }

        mutating func clockEnvelope() {
            guard envelopePeriod != 0 else { return }
            envelopeTimer -= 1
            if envelopeTimer <= 0 {
                envelopeTimer = envelopePeriod
                if envelopeUp && volume < 15 { volume += 1 }
                if !envelopeUp && volume > 0 { volume -= 1 }
            }
        }
    }

    let audio: AudioResampler
    var powered = true
    var ch1 = Pulse()
    var ch2 = Pulse()
    var ch3 = Wave()
    var ch4 = Noise()
    var nr50: UInt8 = 0x77
    var nr51: UInt8 = 0xF3
    var sequencerStep = 0
    var registers = [UInt8](repeating: 0, count: 0x20)
    let waveRAM = ByteBuffer(count: 16)

    /// Bits that always read back as 1, for FF10…FF2F.
    static let readMasks: [UInt8] = [
        0x80, 0x3F, 0x00, 0xFF, 0xBF, 0xFF, 0x3F, 0x00, 0xFF, 0xBF,
        0x7F, 0xFF, 0x9F, 0xFF, 0xBF, 0xFF, 0xFF, 0x00, 0x00, 0xBF,
        0x00, 0x00, 0x70, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    ]

    init(audio: AudioResampler) {
        self.audio = audio
        // Values the boot ROM leaves behind.
        let boot: [(Int, UInt8)] = [
            (0x10, 0x80), (0x11, 0xBF), (0x12, 0xF3), (0x13, 0xFF), (0x14, 0xBF),
            (0x16, 0x3F), (0x17, 0x00), (0x18, 0xFF), (0x19, 0xBF),
            (0x1A, 0x7F), (0x1B, 0xFF), (0x1C, 0x9F), (0x1D, 0xFF), (0x1E, 0xBF),
            (0x20, 0xFF), (0x21, 0x00), (0x22, 0x00), (0x23, 0xBF),
        ]
        for (reg, value) in boot { registers[reg - 0x10] = value }
        ch1.duty = 2
        ch1.envelopeInitial = 0xF
        ch1.envelopePeriod = 3
        ch1.dacEnabled = true
        ch2.dacEnabled = false
    }

    // MARK: Timing

    @inline(__always) func step(_ cycles: Int) {
        guard powered else {
            audio.push(0, count: cycles)
            return
        }
        ch1.step(cycles)
        ch2.step(cycles)
        stepWave(cycles)
        ch4.step(cycles)

        var left = 0.0, right = 0.0
        mix(ch1.dacEnabled, ch1.output, 0, &left, &right)
        mix(ch2.dacEnabled, ch2.output, 1, &left, &right)
        mix(ch3.dacEnabled, ch3.enabled ? Int(ch3.sample) >> waveShift : 0, 2, &left, &right)
        mix(ch4.dacEnabled, ch4.output, 3, &left, &right)
        left *= Double(((nr50 >> 4) & 7) + 1) / 8
        right *= Double((nr50 & 7) + 1) / 8
        audio.push((left + right) * 0.125, count: cycles)
    }

    @inline(__always) private func mix(_ dac: Bool, _ digital: Int, _ channel: UInt8, _ left: inout Double, _ right: inout Double) {
        guard dac else { return }
        let analog = Double(digital) / 7.5 - 1
        if nr51 & (0x10 << channel) != 0 { left += analog }
        if nr51 & (0x01 << channel) != 0 { right += analog }
    }

    private var waveShift: Int {
        switch ch3.volumeCode {
        case 0: return 4
        case 1: return 0
        case 2: return 1
        default: return 2
        }
    }

    @inline(__always) private func stepWave(_ cycles: Int) {
        ch3.timer -= cycles
        while ch3.timer <= 0 {
            ch3.timer += (2048 - ch3.frequency) * 2
            ch3.position = (ch3.position + 1) & 31
            let byte = waveRAM[ch3.position >> 1]
            ch3.sample = ch3.position & 1 == 0 ? byte >> 4 : byte & 0x0F
        }
    }

    /// 512 Hz frame sequencer, clocked by the divider.
    func frameSequencerTick() {
        guard powered else { return }
        switch sequencerStep {
        case 0, 4:
            clockLengths()
        case 2, 6:
            clockLengths()
            ch1.clockSweep()
        case 7:
            ch1.clockEnvelope()
            ch2.clockEnvelope()
            ch4.clockEnvelope()
        default:
            break
        }
        sequencerStep = (sequencerStep + 1) & 7
    }

    private func clockLengths() {
        ch1.clockLength()
        ch2.clockLength()
        ch3.clockLength()
        ch4.clockLength()
    }

    // MARK: Registers

    func read(_ addr: UInt16) -> UInt8 {
        let a = Int(addr)
        if a >= 0xFF30 {
            return waveRAM[a - 0xFF30]
        }
        let index = a - 0xFF10
        if a == 0xFF26 {
            var v: UInt8 = powered ? 0xF0 : 0x70
            if ch1.enabled { v |= 1 }
            if ch2.enabled { v |= 2 }
            if ch3.enabled { v |= 4 }
            if ch4.enabled { v |= 8 }
            return v
        }
        if a == 0xFF24 { return nr50 }
        if a == 0xFF25 { return nr51 }
        guard index >= 0 && index < GBAPU.readMasks.count else { return 0xFF }
        return registers[index] | GBAPU.readMasks[index]
    }

    func write(_ addr: UInt16, _ v: UInt8) {
        let a = Int(addr)
        if a >= 0xFF30 {
            waveRAM[a - 0xFF30] = v
            return
        }
        if a == 0xFF26 {
            let on = v & 0x80 != 0
            if powered && !on {
                for reg in 0xFF10...0xFF25 { write(UInt16(reg), 0) }
                ch1 = Pulse()
                ch2 = Pulse()
                ch3 = Wave()
                ch4 = Noise()
                nr50 = 0
                nr51 = 0
            } else if !powered && on {
                sequencerStep = 0
            }
            powered = on
            return
        }
        guard powered else { return }
        registers[a - 0xFF10] = v
        switch a {
        case 0xFF10:
            ch1.sweepPeriod = Int((v >> 4) & 7)
            ch1.sweepNegate = v & 0x08 != 0
            ch1.sweepShift = Int(v & 7)
        case 0xFF11:
            ch1.duty = Int(v >> 6)
            ch1.length = 64 - Int(v & 0x3F)
        case 0xFF12:
            setEnvelope(&ch1, v)
        case 0xFF13:
            ch1.frequency = (ch1.frequency & 0x700) | Int(v)
        case 0xFF14:
            ch1.frequency = (ch1.frequency & 0xFF) | Int(v & 7) << 8
            ch1.lengthEnabled = v & 0x40 != 0
            if v & 0x80 != 0 { ch1.trigger(hasSweep: true) }
        case 0xFF16:
            ch2.duty = Int(v >> 6)
            ch2.length = 64 - Int(v & 0x3F)
        case 0xFF17:
            setEnvelope(&ch2, v)
        case 0xFF18:
            ch2.frequency = (ch2.frequency & 0x700) | Int(v)
        case 0xFF19:
            ch2.frequency = (ch2.frequency & 0xFF) | Int(v & 7) << 8
            ch2.lengthEnabled = v & 0x40 != 0
            if v & 0x80 != 0 { ch2.trigger(hasSweep: false) }
        case 0xFF1A:
            ch3.dacEnabled = v & 0x80 != 0
            if !ch3.dacEnabled { ch3.enabled = false }
        case 0xFF1B:
            ch3.length = 256 - Int(v)
        case 0xFF1C:
            ch3.volumeCode = Int((v >> 5) & 3)
        case 0xFF1D:
            ch3.frequency = (ch3.frequency & 0x700) | Int(v)
        case 0xFF1E:
            ch3.frequency = (ch3.frequency & 0xFF) | Int(v & 7) << 8
            ch3.lengthEnabled = v & 0x40 != 0
            if v & 0x80 != 0 {
                ch3.enabled = ch3.dacEnabled
                if ch3.length == 0 { ch3.length = 256 }
                ch3.timer = (2048 - ch3.frequency) * 2
                ch3.position = 0
            }
        case 0xFF20:
            ch4.length = 64 - Int(v & 0x3F)
        case 0xFF21:
            ch4.envelopeInitial = Int(v >> 4)
            ch4.envelopeUp = v & 0x08 != 0
            ch4.envelopePeriod = Int(v & 7)
            ch4.dacEnabled = v & 0xF8 != 0
            if !ch4.dacEnabled { ch4.enabled = false }
        case 0xFF22:
            ch4.shift = Int(v >> 4)
            ch4.narrow = v & 0x08 != 0
            ch4.divisor = Int(v & 7)
        case 0xFF23:
            ch4.lengthEnabled = v & 0x40 != 0
            if v & 0x80 != 0 {
                ch4.enabled = ch4.dacEnabled
                if ch4.length == 0 { ch4.length = 64 }
                ch4.timer = ch4.period
                ch4.volume = ch4.envelopeInitial
                ch4.envelopeTimer = ch4.envelopePeriod
                ch4.lfsr = 0x7FFF
            }
        case 0xFF24:
            nr50 = v
        case 0xFF25:
            nr51 = v
        default:
            break
        }
    }

    private func setEnvelope(_ ch: inout Pulse, _ v: UInt8) {
        ch.envelopeInitial = Int(v >> 4)
        ch.envelopeUp = v & 0x08 != 0
        ch.envelopePeriod = Int(v & 7)
        ch.dacEnabled = v & 0xF8 != 0
        if !ch.dacEnabled { ch.enabled = false }
    }

    // MARK: State

    private func savePulse(_ p: Pulse, _ w: inout StateWriter) {
        w.bool(p.enabled); w.bool(p.dacEnabled); w.int(p.duty); w.int(p.dutyStep)
        w.int(p.length); w.bool(p.lengthEnabled); w.int(p.frequency); w.int(p.timer)
        w.int(p.volume); w.int(p.envelopeInitial); w.bool(p.envelopeUp); w.int(p.envelopePeriod)
        w.int(p.envelopeTimer); w.int(p.sweepPeriod); w.bool(p.sweepNegate); w.int(p.sweepShift)
        w.int(p.sweepTimer); w.bool(p.sweepEnabled); w.int(p.shadow)
    }

    private func loadPulse(_ r: inout StateReader) throws -> Pulse {
        var p = Pulse()
        p.enabled = try r.bool(); p.dacEnabled = try r.bool(); p.duty = try r.int() & 3; p.dutyStep = try r.int() & 7
        p.length = try r.int(); p.lengthEnabled = try r.bool(); p.frequency = try r.int() & 0x7FF; p.timer = try r.int()
        p.volume = try r.int(); p.envelopeInitial = try r.int(); p.envelopeUp = try r.bool(); p.envelopePeriod = try r.int()
        p.envelopeTimer = try r.int(); p.sweepPeriod = try r.int(); p.sweepNegate = try r.bool(); p.sweepShift = try r.int()
        p.sweepTimer = try r.int(); p.sweepEnabled = try r.bool(); p.shadow = try r.int()
        return p
    }

    func save(_ w: inout StateWriter) {
        w.bool(powered)
        savePulse(ch1, &w)
        savePulse(ch2, &w)
        w.bool(ch3.enabled); w.bool(ch3.dacEnabled); w.int(ch3.length); w.bool(ch3.lengthEnabled)
        w.int(ch3.frequency); w.int(ch3.timer); w.int(ch3.position); w.int(ch3.volumeCode); w.u8(ch3.sample)
        w.bool(ch4.enabled); w.bool(ch4.dacEnabled); w.int(ch4.length); w.bool(ch4.lengthEnabled)
        w.int(ch4.volume); w.int(ch4.envelopeInitial); w.bool(ch4.envelopeUp); w.int(ch4.envelopePeriod)
        w.int(ch4.envelopeTimer); w.int(ch4.shift); w.bool(ch4.narrow); w.int(ch4.divisor); w.int(ch4.timer); w.u16(ch4.lfsr)
        w.u8(nr50)
        w.u8(nr51)
        w.int(sequencerStep)
        w.bytes(registers)
        w.bytes(waveRAM.pointer, count: 16)
    }

    func load(_ r: inout StateReader) throws {
        powered = try r.bool()
        ch1 = try loadPulse(&r)
        ch2 = try loadPulse(&r)
        ch3.enabled = try r.bool(); ch3.dacEnabled = try r.bool(); ch3.length = try r.int(); ch3.lengthEnabled = try r.bool()
        ch3.frequency = try r.int() & 0x7FF; ch3.timer = try r.int(); ch3.position = try r.int() & 31
        ch3.volumeCode = try r.int() & 3; ch3.sample = try r.u8()
        ch4.enabled = try r.bool(); ch4.dacEnabled = try r.bool(); ch4.length = try r.int(); ch4.lengthEnabled = try r.bool()
        ch4.volume = try r.int(); ch4.envelopeInitial = try r.int(); ch4.envelopeUp = try r.bool(); ch4.envelopePeriod = try r.int()
        ch4.envelopeTimer = try r.int(); ch4.shift = try r.int(); ch4.narrow = try r.bool(); ch4.divisor = try r.int() & 7
        ch4.timer = try r.int(); ch4.lfsr = try r.u16()
        nr50 = try r.u8()
        nr51 = try r.u8()
        sequencerStep = try r.int() & 7
        let regs = try r.bytes()
        guard regs.count == registers.count else { throw EmulatorError.badSaveState }
        registers = regs
        try r.bytes(into: waveRAM.pointer, count: 16)
    }
}

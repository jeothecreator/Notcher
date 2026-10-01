import Foundation

/// The Ricoh 2A03's 6502 core (no decimal mode). Each memory access, dummy
/// accesses included, takes one CPU cycle and advances the PPU and APU, so
/// cycle counts match the hardware exactly.
final class NESCPU {
    /// Set by `NES` right after creating its parts; never retained.
    unowned(unsafe) var bus: NES!

    var a: UInt8 = 0
    var x: UInt8 = 0
    var y: UInt8 = 0
    var s: UInt8 = 0xFD
    var p: UInt8 = 0x24
    var pc: UInt16 = 0
    /// Total CPU cycles since power-on.
    var cycles = 0
    var nmiPending = false
    var jammed = false

    static let carry: UInt8 = 0x01
    static let zero: UInt8 = 0x02
    static let interrupt: UInt8 = 0x04
    static let decimal: UInt8 = 0x08
    static let brk: UInt8 = 0x10
    static let unused: UInt8 = 0x20
    static let overflow: UInt8 = 0x40
    static let negative: UInt8 = 0x80

    init() {}

    // MARK: Bus

    @inline(__always) func read(_ addr: UInt16) -> UInt8 {
        cycles += 1
        bus.tick()
        return bus.read(addr)
    }

    @inline(__always) func write(_ addr: UInt16, _ v: UInt8) {
        cycles += 1
        bus.tick()
        bus.write(addr, v)
    }

    @inline(__always) func fetch() -> UInt8 {
        let v = read(pc)
        pc &+= 1
        return v
    }

    @inline(__always) func fetch16() -> UInt16 {
        let lo = UInt16(fetch())
        return UInt16(fetch()) << 8 | lo
    }

    @inline(__always) func push(_ v: UInt8) {
        write(0x100 | UInt16(s), v)
        s &-= 1
    }

    @inline(__always) func pull() -> UInt8 {
        s &+= 1
        return read(0x100 | UInt16(s))
    }

    // MARK: Flags

    @inline(__always) func flag(_ f: UInt8) -> Bool { p & f != 0 }

    @inline(__always) func set(_ f: UInt8, _ on: Bool) {
        if on { p |= f } else { p &= ~f }
    }

    @inline(__always) func setZN(_ v: UInt8) {
        p = (p & ~(Self.zero | Self.negative)) | (v == 0 ? Self.zero : 0) | (v & 0x80)
    }

    // MARK: Interrupts

    func reset() {
        s &-= 3
        p |= Self.interrupt
        let lo = UInt16(bus.read(0xFFFC))
        let hi = UInt16(bus.read(0xFFFD))
        pc = hi << 8 | lo
        cycles += 7
        for _ in 0..<7 { bus.tick() }
        jammed = false
    }

    private func interrupt(vector: UInt16, brk: Bool) {
        if !brk {
            _ = read(pc)
            _ = read(pc)
        }
        push(UInt8(pc >> 8))
        push(UInt8(pc & 0xFF))
        push(p | Self.unused | (brk ? Self.brk : 0))
        p |= Self.interrupt
        // A pending NMI can hijack a BRK or IRQ in progress.
        var target = vector
        if nmiPending && vector != 0xFFFA {
            nmiPending = false
            target = 0xFFFA
        }
        let lo = UInt16(read(target))
        let hi = UInt16(read(target &+ 1))
        pc = hi << 8 | lo
    }

    /// Runs one instruction, or services one interrupt.
    func step() {
        if jammed {
            cycles += 1
            bus.tick()
            return
        }
        if nmiPending {
            nmiPending = false
            interrupt(vector: 0xFFFA, brk: false)
            return
        }
        if bus.irqLine && !flag(Self.interrupt) {
            interrupt(vector: 0xFFFE, brk: false)
            return
        }
        execute(fetch())
    }

    // MARK: Addressing

    enum Access { case read, write, modify }

    @inline(__always) func zp() -> UInt16 { UInt16(fetch()) }

    @inline(__always) func zpIndexed(_ index: UInt8) -> UInt16 {
        let base = fetch()
        _ = read(UInt16(base))
        return UInt16(base &+ index)
    }

    @inline(__always) func abs() -> UInt16 { fetch16() }

    @inline(__always) func absIndexed(_ index: UInt8, _ access: Access) -> UInt16 {
        let base = fetch16()
        let addr = base &+ UInt16(index)
        if access != .read || base & 0xFF00 != addr & 0xFF00 {
            _ = read((base & 0xFF00) | (addr & 0x00FF))
        }
        return addr
    }

    @inline(__always) func indexedIndirect() -> UInt16 {
        let zp = fetch()
        _ = read(UInt16(zp))
        let ptr = zp &+ x
        let lo = UInt16(read(UInt16(ptr)))
        let hi = UInt16(read(UInt16(ptr &+ 1)))
        return hi << 8 | lo
    }

    @inline(__always) func indirectIndexed(_ access: Access) -> UInt16 {
        let zp = fetch()
        let lo = UInt16(read(UInt16(zp)))
        let hi = UInt16(read(UInt16(zp &+ 1)))
        let base = hi << 8 | lo
        let addr = base &+ UInt16(y)
        if access != .read || base & 0xFF00 != addr & 0xFF00 {
            _ = read((base & 0xFF00) | (addr & 0x00FF))
        }
        return addr
    }

    /// Two-cycle implied instructions read the next byte and throw it away.
    @inline(__always) func implied() {
        _ = read(pc)
    }

    // MARK: Operations

    @inline(__always) func adc(_ v: UInt8) {
        let sum = UInt16(a) + UInt16(v) + (flag(Self.carry) ? 1 : 0)
        let result = UInt8(sum & 0xFF)
        set(Self.overflow, (~(a ^ v) & (a ^ result) & 0x80) != 0)
        set(Self.carry, sum > 0xFF)
        a = result
        setZN(a)
    }

    @inline(__always) func sbc(_ v: UInt8) { adc(~v) }

    @inline(__always) func compare(_ r: UInt8, _ v: UInt8) {
        set(Self.carry, r >= v)
        setZN(r &- v)
    }

    @inline(__always) func asl(_ v: UInt8) -> UInt8 {
        set(Self.carry, v & 0x80 != 0)
        let r = v << 1
        setZN(r)
        return r
    }

    @inline(__always) func lsr(_ v: UInt8) -> UInt8 {
        set(Self.carry, v & 1 != 0)
        let r = v >> 1
        setZN(r)
        return r
    }

    @inline(__always) func rol(_ v: UInt8) -> UInt8 {
        let r = v << 1 | (flag(Self.carry) ? 1 : 0)
        set(Self.carry, v & 0x80 != 0)
        setZN(r)
        return r
    }

    @inline(__always) func ror(_ v: UInt8) -> UInt8 {
        let r = v >> 1 | (flag(Self.carry) ? 0x80 : 0)
        set(Self.carry, v & 1 != 0)
        setZN(r)
        return r
    }

    @inline(__always) func inc(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        setZN(r)
        return r
    }

    @inline(__always) func dec(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        setZN(r)
        return r
    }

    @inline(__always) func bit(_ v: UInt8) {
        set(Self.zero, a & v == 0)
        set(Self.overflow, v & 0x40 != 0)
        set(Self.negative, v & 0x80 != 0)
    }

    @inline(__always) func load(_ addr: UInt16) -> UInt8 { read(addr) }

    /// Read-modify-write: read, write the old value back, write the result.
    @inline(__always) func modify(_ addr: UInt16, _ op: (UInt8) -> UInt8) -> UInt8 {
        let v = read(addr)
        write(addr, v)
        let r = op(v)
        write(addr, r)
        return r
    }

    @inline(__always) func branch(_ condition: Bool) {
        let offset = Int8(bitPattern: fetch())
        guard condition else { return }
        _ = read(pc)
        let target = pc &+ UInt16(bitPattern: Int16(offset))
        if target & 0xFF00 != pc & 0xFF00 {
            _ = read((pc & 0xFF00) | (target & 0x00FF))
        }
        pc = target
    }

    // Unofficial combined operations.
    @inline(__always) func slo(_ addr: UInt16) { a |= modify(addr) { self.asl($0) }; setZN(a) }
    @inline(__always) func rla(_ addr: UInt16) { a &= modify(addr) { self.rol($0) }; setZN(a) }
    @inline(__always) func sre(_ addr: UInt16) { a ^= modify(addr) { self.lsr($0) }; setZN(a) }
    @inline(__always) func rra(_ addr: UInt16) { let v = modify(addr) { self.ror($0) }; adc(v) }
    @inline(__always) func dcp(_ addr: UInt16) { let v = modify(addr) { $0 &- 1 }; compare(a, v) }
    @inline(__always) func isb(_ addr: UInt16) { let v = modify(addr) { $0 &+ 1 }; sbc(v) }
    @inline(__always) func lax(_ v: UInt8) { a = v; x = v; setZN(v) }

    // MARK: Opcodes

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func execute(_ op: UInt8) {
        switch op {
        // LDA
        case 0xA9: a = fetch(); setZN(a)
        case 0xA5: a = load(zp()); setZN(a)
        case 0xB5: a = load(zpIndexed(x)); setZN(a)
        case 0xAD: a = load(abs()); setZN(a)
        case 0xBD: a = load(absIndexed(x, .read)); setZN(a)
        case 0xB9: a = load(absIndexed(y, .read)); setZN(a)
        case 0xA1: a = load(indexedIndirect()); setZN(a)
        case 0xB1: a = load(indirectIndexed(.read)); setZN(a)
        // LDX
        case 0xA2: x = fetch(); setZN(x)
        case 0xA6: x = load(zp()); setZN(x)
        case 0xB6: x = load(zpIndexed(y)); setZN(x)
        case 0xAE: x = load(abs()); setZN(x)
        case 0xBE: x = load(absIndexed(y, .read)); setZN(x)
        // LDY
        case 0xA0: y = fetch(); setZN(y)
        case 0xA4: y = load(zp()); setZN(y)
        case 0xB4: y = load(zpIndexed(x)); setZN(y)
        case 0xAC: y = load(abs()); setZN(y)
        case 0xBC: y = load(absIndexed(x, .read)); setZN(y)
        // STA
        case 0x85: write(zp(), a)
        case 0x95: write(zpIndexed(x), a)
        case 0x8D: write(abs(), a)
        case 0x9D: write(absIndexed(x, .write), a)
        case 0x99: write(absIndexed(y, .write), a)
        case 0x81: write(indexedIndirect(), a)
        case 0x91: write(indirectIndexed(.write), a)
        // STX / STY
        case 0x86: write(zp(), x)
        case 0x96: write(zpIndexed(y), x)
        case 0x8E: write(abs(), x)
        case 0x84: write(zp(), y)
        case 0x94: write(zpIndexed(x), y)
        case 0x8C: write(abs(), y)
        // Transfers
        case 0xAA: implied(); x = a; setZN(x)
        case 0xA8: implied(); y = a; setZN(y)
        case 0x8A: implied(); a = x; setZN(a)
        case 0x98: implied(); a = y; setZN(a)
        case 0xBA: implied(); x = s; setZN(x)
        case 0x9A: implied(); s = x
        // Stack
        case 0x48: implied(); push(a)
        case 0x08: implied(); push(p | Self.brk | Self.unused)
        case 0x68:
            implied()
            _ = read(0x100 | UInt16(s))
            a = pull()
            setZN(a)
        case 0x28:
            implied()
            _ = read(0x100 | UInt16(s))
            p = (pull() & ~Self.brk) | Self.unused
        // ADC
        case 0x69: adc(fetch())
        case 0x65: adc(load(zp()))
        case 0x75: adc(load(zpIndexed(x)))
        case 0x6D: adc(load(abs()))
        case 0x7D: adc(load(absIndexed(x, .read)))
        case 0x79: adc(load(absIndexed(y, .read)))
        case 0x61: adc(load(indexedIndirect()))
        case 0x71: adc(load(indirectIndexed(.read)))
        // SBC
        case 0xE9, 0xEB: sbc(fetch())
        case 0xE5: sbc(load(zp()))
        case 0xF5: sbc(load(zpIndexed(x)))
        case 0xED: sbc(load(abs()))
        case 0xFD: sbc(load(absIndexed(x, .read)))
        case 0xF9: sbc(load(absIndexed(y, .read)))
        case 0xE1: sbc(load(indexedIndirect()))
        case 0xF1: sbc(load(indirectIndexed(.read)))
        // AND
        case 0x29: a &= fetch(); setZN(a)
        case 0x25: a &= load(zp()); setZN(a)
        case 0x35: a &= load(zpIndexed(x)); setZN(a)
        case 0x2D: a &= load(abs()); setZN(a)
        case 0x3D: a &= load(absIndexed(x, .read)); setZN(a)
        case 0x39: a &= load(absIndexed(y, .read)); setZN(a)
        case 0x21: a &= load(indexedIndirect()); setZN(a)
        case 0x31: a &= load(indirectIndexed(.read)); setZN(a)
        // ORA
        case 0x09: a |= fetch(); setZN(a)
        case 0x05: a |= load(zp()); setZN(a)
        case 0x15: a |= load(zpIndexed(x)); setZN(a)
        case 0x0D: a |= load(abs()); setZN(a)
        case 0x1D: a |= load(absIndexed(x, .read)); setZN(a)
        case 0x19: a |= load(absIndexed(y, .read)); setZN(a)
        case 0x01: a |= load(indexedIndirect()); setZN(a)
        case 0x11: a |= load(indirectIndexed(.read)); setZN(a)
        // EOR
        case 0x49: a ^= fetch(); setZN(a)
        case 0x45: a ^= load(zp()); setZN(a)
        case 0x55: a ^= load(zpIndexed(x)); setZN(a)
        case 0x4D: a ^= load(abs()); setZN(a)
        case 0x5D: a ^= load(absIndexed(x, .read)); setZN(a)
        case 0x59: a ^= load(absIndexed(y, .read)); setZN(a)
        case 0x41: a ^= load(indexedIndirect()); setZN(a)
        case 0x51: a ^= load(indirectIndexed(.read)); setZN(a)
        // CMP / CPX / CPY
        case 0xC9: compare(a, fetch())
        case 0xC5: compare(a, load(zp()))
        case 0xD5: compare(a, load(zpIndexed(x)))
        case 0xCD: compare(a, load(abs()))
        case 0xDD: compare(a, load(absIndexed(x, .read)))
        case 0xD9: compare(a, load(absIndexed(y, .read)))
        case 0xC1: compare(a, load(indexedIndirect()))
        case 0xD1: compare(a, load(indirectIndexed(.read)))
        case 0xE0: compare(x, fetch())
        case 0xE4: compare(x, load(zp()))
        case 0xEC: compare(x, load(abs()))
        case 0xC0: compare(y, fetch())
        case 0xC4: compare(y, load(zp()))
        case 0xCC: compare(y, load(abs()))
        // BIT
        case 0x24: bit(load(zp()))
        case 0x2C: bit(load(abs()))
        // Shifts and rotates
        case 0x0A: implied(); a = asl(a)
        case 0x06: _ = modify(zp()) { self.asl($0) }
        case 0x16: _ = modify(zpIndexed(x)) { self.asl($0) }
        case 0x0E: _ = modify(abs()) { self.asl($0) }
        case 0x1E: _ = modify(absIndexed(x, .modify)) { self.asl($0) }
        case 0x4A: implied(); a = lsr(a)
        case 0x46: _ = modify(zp()) { self.lsr($0) }
        case 0x56: _ = modify(zpIndexed(x)) { self.lsr($0) }
        case 0x4E: _ = modify(abs()) { self.lsr($0) }
        case 0x5E: _ = modify(absIndexed(x, .modify)) { self.lsr($0) }
        case 0x2A: implied(); a = rol(a)
        case 0x26: _ = modify(zp()) { self.rol($0) }
        case 0x36: _ = modify(zpIndexed(x)) { self.rol($0) }
        case 0x2E: _ = modify(abs()) { self.rol($0) }
        case 0x3E: _ = modify(absIndexed(x, .modify)) { self.rol($0) }
        case 0x6A: implied(); a = ror(a)
        case 0x66: _ = modify(zp()) { self.ror($0) }
        case 0x76: _ = modify(zpIndexed(x)) { self.ror($0) }
        case 0x6E: _ = modify(abs()) { self.ror($0) }
        case 0x7E: _ = modify(absIndexed(x, .modify)) { self.ror($0) }
        // INC / DEC
        case 0xE6: _ = modify(zp()) { self.inc($0) }
        case 0xF6: _ = modify(zpIndexed(x)) { self.inc($0) }
        case 0xEE: _ = modify(abs()) { self.inc($0) }
        case 0xFE: _ = modify(absIndexed(x, .modify)) { self.inc($0) }
        case 0xC6: _ = modify(zp()) { self.dec($0) }
        case 0xD6: _ = modify(zpIndexed(x)) { self.dec($0) }
        case 0xCE: _ = modify(abs()) { self.dec($0) }
        case 0xDE: _ = modify(absIndexed(x, .modify)) { self.dec($0) }
        case 0xE8: implied(); x = inc(x)
        case 0xC8: implied(); y = inc(y)
        case 0xCA: implied(); x = dec(x)
        case 0x88: implied(); y = dec(y)
        // Flags
        case 0x18: implied(); set(Self.carry, false)
        case 0x38: implied(); set(Self.carry, true)
        case 0x58: implied(); set(Self.interrupt, false)
        case 0x78: implied(); set(Self.interrupt, true)
        case 0xB8: implied(); set(Self.overflow, false)
        case 0xD8: implied(); set(Self.decimal, false)
        case 0xF8: implied(); set(Self.decimal, true)
        // Branches
        case 0x10: branch(!flag(Self.negative))
        case 0x30: branch(flag(Self.negative))
        case 0x50: branch(!flag(Self.overflow))
        case 0x70: branch(flag(Self.overflow))
        case 0x90: branch(!flag(Self.carry))
        case 0xB0: branch(flag(Self.carry))
        case 0xD0: branch(!flag(Self.zero))
        case 0xF0: branch(flag(Self.zero))
        // Jumps
        case 0x4C: pc = fetch16()
        case 0x6C:
            let ptr = fetch16()
            let lo = UInt16(read(ptr))
            // The famous page-wrap bug.
            let hi = UInt16(read((ptr & 0xFF00) | ((ptr &+ 1) & 0x00FF)))
            pc = hi << 8 | lo
        case 0x20:
            let lo = UInt16(fetch())
            _ = read(0x100 | UInt16(s))
            push(UInt8(pc >> 8))
            push(UInt8(pc & 0xFF))
            let hi = UInt16(fetch())
            pc = hi << 8 | lo
        case 0x60:
            implied()
            _ = read(0x100 | UInt16(s))
            let lo = UInt16(pull())
            let hi = UInt16(pull())
            pc = hi << 8 | lo
            _ = read(pc)
            pc &+= 1
        case 0x40:
            implied()
            _ = read(0x100 | UInt16(s))
            p = (pull() & ~Self.brk) | Self.unused
            let lo = UInt16(pull())
            let hi = UInt16(pull())
            pc = hi << 8 | lo
        case 0x00:
            _ = fetch()
            interrupt(vector: 0xFFFE, brk: true)
        case 0xEA: implied()

        // Unofficial NOPs
        case 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA: implied()
        case 0x80, 0x82, 0x89, 0xC2, 0xE2: _ = fetch()
        case 0x04, 0x44, 0x64: _ = load(zp())
        case 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4: _ = load(zpIndexed(x))
        case 0x0C: _ = load(abs())
        case 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC: _ = load(absIndexed(x, .read))
        // LAX
        case 0xA7: lax(load(zp()))
        case 0xB7: lax(load(zpIndexed(y)))
        case 0xAF: lax(load(abs()))
        case 0xBF: lax(load(absIndexed(y, .read)))
        case 0xA3: lax(load(indexedIndirect()))
        case 0xB3: lax(load(indirectIndexed(.read)))
        case 0xAB: lax(fetch())
        // SAX
        case 0x87: write(zp(), a & x)
        case 0x97: write(zpIndexed(y), a & x)
        case 0x8F: write(abs(), a & x)
        case 0x83: write(indexedIndirect(), a & x)
        // DCP
        case 0xC7: dcp(zp())
        case 0xD7: dcp(zpIndexed(x))
        case 0xCF: dcp(abs())
        case 0xDF: dcp(absIndexed(x, .modify))
        case 0xDB: dcp(absIndexed(y, .modify))
        case 0xC3: dcp(indexedIndirect())
        case 0xD3: dcp(indirectIndexed(.modify))
        // ISB
        case 0xE7: isb(zp())
        case 0xF7: isb(zpIndexed(x))
        case 0xEF: isb(abs())
        case 0xFF: isb(absIndexed(x, .modify))
        case 0xFB: isb(absIndexed(y, .modify))
        case 0xE3: isb(indexedIndirect())
        case 0xF3: isb(indirectIndexed(.modify))
        // SLO
        case 0x07: slo(zp())
        case 0x17: slo(zpIndexed(x))
        case 0x0F: slo(abs())
        case 0x1F: slo(absIndexed(x, .modify))
        case 0x1B: slo(absIndexed(y, .modify))
        case 0x03: slo(indexedIndirect())
        case 0x13: slo(indirectIndexed(.modify))
        // RLA
        case 0x27: rla(zp())
        case 0x37: rla(zpIndexed(x))
        case 0x2F: rla(abs())
        case 0x3F: rla(absIndexed(x, .modify))
        case 0x3B: rla(absIndexed(y, .modify))
        case 0x23: rla(indexedIndirect())
        case 0x33: rla(indirectIndexed(.modify))
        // SRE
        case 0x47: sre(zp())
        case 0x57: sre(zpIndexed(x))
        case 0x4F: sre(abs())
        case 0x5F: sre(absIndexed(x, .modify))
        case 0x5B: sre(absIndexed(y, .modify))
        case 0x43: sre(indexedIndirect())
        case 0x53: sre(indirectIndexed(.modify))
        // RRA
        case 0x67: rra(zp())
        case 0x77: rra(zpIndexed(x))
        case 0x6F: rra(abs())
        case 0x7F: rra(absIndexed(x, .modify))
        case 0x7B: rra(absIndexed(y, .modify))
        case 0x63: rra(indexedIndirect())
        case 0x73: rra(indirectIndexed(.modify))
        // Immediate oddities
        case 0x0B, 0x2B: // ANC
            a &= fetch()
            setZN(a)
            set(Self.carry, a & 0x80 != 0)
        case 0x4B: // ALR
            a &= fetch()
            a = lsr(a)
        case 0x6B: // ARR
            a &= fetch()
            a = a >> 1 | (flag(Self.carry) ? 0x80 : 0)
            setZN(a)
            set(Self.carry, a & 0x40 != 0)
            set(Self.overflow, ((a >> 6) ^ (a >> 5)) & 1 != 0)
        case 0xCB: // AXS
            let v = fetch()
            let ax = a & x
            set(Self.carry, ax >= v)
            x = ax &- v
            setZN(x)
        case 0x9C: // SHY
            let addr = absIndexed(x, .write)
            write(addr, y & (UInt8(addr >> 8) &+ 1))
        case 0x9E: // SHX
            let addr = absIndexed(y, .write)
            write(addr, x & (UInt8(addr >> 8) &+ 1))
        case 0x9F, 0x93, 0x9B, 0xBB, 0x8B:
            // Unstable opcodes no game relies on: treat as their addressing-only NOPs.
            _ = fetch()
        default:
            // KIL / JAM
            jammed = true
        }
    }

    // MARK: State

    func save(_ w: inout StateWriter) {
        for v in [a, x, y, s, p] { w.u8(v) }
        w.u16(pc)
        w.int(cycles)
        w.bool(nmiPending)
        w.bool(jammed)
    }

    func load(_ r: inout StateReader) throws {
        a = try r.u8(); x = try r.u8(); y = try r.u8(); s = try r.u8(); p = try r.u8()
        pc = try r.u16()
        cycles = try r.int()
        nmiPending = try r.bool()
        jammed = try r.bool()
    }
}

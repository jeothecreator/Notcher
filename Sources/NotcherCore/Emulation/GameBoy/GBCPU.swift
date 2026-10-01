import Foundation

/// The Sharp SM83 core. Every memory access advances the rest of the system
/// by one M-cycle, so instruction timing falls out of the access pattern.
final class GBCPU {
    unowned(unsafe) let bus: GameBoy

    var a: UInt8 = 0x01, f: UInt8 = 0xB0
    var b: UInt8 = 0x00, c: UInt8 = 0x13
    var d: UInt8 = 0x00, e: UInt8 = 0xD8
    var h: UInt8 = 0x01, l: UInt8 = 0x4D
    var sp: UInt16 = 0xFFFE
    var pc: UInt16 = 0x0100
    var ime = false
    /// EI enables interrupts after the following instruction.
    var imeDelay = 0
    var halted = false
    var haltBug = false
    /// Set by an illegal opcode; the real CPU locks up.
    var locked = false

    init(bus: GameBoy) {
        self.bus = bus
    }

    // MARK: Registers

    var bc: UInt16 {
        get { UInt16(b) << 8 | UInt16(c) }
        set { b = UInt8(newValue >> 8); c = UInt8(newValue & 0xFF) }
    }
    var de: UInt16 {
        get { UInt16(d) << 8 | UInt16(e) }
        set { d = UInt8(newValue >> 8); e = UInt8(newValue & 0xFF) }
    }
    var hl: UInt16 {
        get { UInt16(h) << 8 | UInt16(l) }
        set { h = UInt8(newValue >> 8); l = UInt8(newValue & 0xFF) }
    }
    var af: UInt16 {
        get { UInt16(a) << 8 | UInt16(f) }
        set { a = UInt8(newValue >> 8); f = UInt8(newValue & 0xF0) }
    }

    @inline(__always) var flagZ: Bool { f & 0x80 != 0 }
    @inline(__always) var flagC: Bool { f & 0x10 != 0 }
    @inline(__always) var flagN: Bool { f & 0x40 != 0 }
    @inline(__always) var flagH: Bool { f & 0x20 != 0 }

    // MARK: Bus

    @inline(__always) func read(_ addr: UInt16) -> UInt8 {
        bus.tick()
        return bus.read(addr)
    }

    @inline(__always) func write(_ addr: UInt16, _ value: UInt8) {
        bus.tick()
        bus.write(addr, value)
    }

    @inline(__always) func fetch() -> UInt8 {
        let v = read(pc)
        if haltBug {
            haltBug = false
        } else {
            pc &+= 1
        }
        return v
    }

    @inline(__always) func fetch16() -> UInt16 {
        let lo = UInt16(fetch())
        let hi = UInt16(fetch())
        return hi << 8 | lo
    }

    @inline(__always) func push(_ v: UInt16) {
        sp &-= 1
        write(sp, UInt8(v >> 8))
        sp &-= 1
        write(sp, UInt8(v & 0xFF))
    }

    @inline(__always) func pop() -> UInt16 {
        let lo = UInt16(read(sp))
        sp &+= 1
        let hi = UInt16(read(sp))
        sp &+= 1
        return hi << 8 | lo
    }

    // MARK: Step

    func step() {
        if locked {
            bus.tick()
            return
        }
        let pending = bus.interruptEnable & bus.interruptFlag & 0x1F
        if halted {
            if pending == 0 {
                bus.tick()
                return
            }
            halted = false
        }
        if ime && pending != 0 {
            serviceInterrupt()
            return
        }
        execute(fetch())
        if imeDelay > 0 {
            imeDelay -= 1
            if imeDelay == 0 { ime = true }
        }
    }

    private func serviceInterrupt() {
        ime = false
        bus.tick()
        bus.tick()
        sp &-= 1
        write(sp, UInt8(pc >> 8))
        // Pushing the high byte can overwrite IE, which can cancel the dispatch.
        let pending = bus.interruptEnable & bus.interruptFlag & 0x1F
        sp &-= 1
        write(sp, UInt8(pc & 0xFF))
        if pending == 0 {
            pc = 0
        } else {
            let bit = pending.trailingZeroBitCount
            bus.interruptFlag &= ~(UInt8(1) << UInt8(bit))
            pc = 0x40 + UInt16(bit) * 8
        }
        bus.tick()
    }

    // MARK: Operands

    @inline(__always) func reg(_ i: UInt8) -> UInt8 {
        switch i {
        case 0: return b
        case 1: return c
        case 2: return d
        case 3: return e
        case 4: return h
        case 5: return l
        case 6: return read(hl)
        default: return a
        }
    }

    @inline(__always) func setReg(_ i: UInt8, _ v: UInt8) {
        switch i {
        case 0: b = v
        case 1: c = v
        case 2: d = v
        case 3: e = v
        case 4: h = v
        case 5: l = v
        case 6: write(hl, v)
        default: a = v
        }
    }

    // MARK: ALU

    @inline(__always) func add(_ v: UInt8, carry: Bool) {
        let cin: UInt8 = carry ? 1 : 0
        let r = UInt16(a) + UInt16(v) + UInt16(cin)
        let half = (a & 0x0F) + (v & 0x0F) + cin > 0x0F
        a = UInt8(r & 0xFF)
        f = (a == 0 ? 0x80 : 0) | (half ? 0x20 : 0) | (r > 0xFF ? 0x10 : 0)
    }

    @inline(__always) func sub(_ v: UInt8, carry: Bool, store: Bool) {
        let cin = carry ? 1 : 0
        let r = Int(a) - Int(v) - cin
        let half = Int(a & 0x0F) - Int(v & 0x0F) - cin < 0
        let res = UInt8(truncatingIfNeeded: r)
        f = (res == 0 ? 0x80 : 0) | 0x40 | (half ? 0x20 : 0) | (r < 0 ? 0x10 : 0)
        if store { a = res }
    }

    @inline(__always) func alu(_ op: UInt8, _ v: UInt8) {
        switch op {
        case 0: add(v, carry: false)
        case 1: add(v, carry: flagC)
        case 2: sub(v, carry: false, store: true)
        case 3: sub(v, carry: flagC, store: true)
        case 4:
            a &= v
            f = (a == 0 ? 0x80 : 0) | 0x20
        case 5:
            a ^= v
            f = a == 0 ? 0x80 : 0
        case 6:
            a |= v
            f = a == 0 ? 0x80 : 0
        default:
            sub(v, carry: false, store: false)
        }
    }

    @inline(__always) func inc(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        f = (f & 0x10) | (r == 0 ? 0x80 : 0) | (v & 0x0F == 0x0F ? 0x20 : 0)
        return r
    }

    @inline(__always) func dec(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        f = (f & 0x10) | (r == 0 ? 0x80 : 0) | 0x40 | (v & 0x0F == 0 ? 0x20 : 0)
        return r
    }

    @inline(__always) func addHL(_ v: UInt16) {
        let value = hl
        let r = UInt32(value) + UInt32(v)
        let half = (value & 0x0FFF) + (v & 0x0FFF) > 0x0FFF
        f = (f & 0x80) | (half ? 0x20 : 0) | (r > 0xFFFF ? 0x10 : 0)
        hl = UInt16(r & 0xFFFF)
        bus.tick()
    }

    /// SP + signed immediate, with the flags of an 8-bit add on the low byte.
    @inline(__always) func spPlusOffset() -> UInt16 {
        let offset = fetch()
        let signed = UInt16(bitPattern: Int16(Int8(bitPattern: offset)))
        let half = (sp & 0x0F) + UInt16(offset & 0x0F) > 0x0F
        let carry = (sp & 0xFF) + UInt16(offset) > 0xFF
        f = (half ? 0x20 : 0) | (carry ? 0x10 : 0)
        return sp &+ signed
    }

    func daa() {
        var value = a
        var carry = flagC
        if !flagN {
            if flagC || value > 0x99 {
                value &+= 0x60
                carry = true
            }
            if flagH || value & 0x0F > 0x09 {
                value &+= 0x06
            }
        } else {
            if flagC { value &-= 0x60 }
            if flagH { value &-= 0x06 }
        }
        a = value
        f = (a == 0 ? 0x80 : 0) | (f & 0x40) | (carry ? 0x10 : 0)
    }

    // MARK: Control flow

    @inline(__always) func jr(_ condition: Bool) {
        let offset = Int8(bitPattern: fetch())
        if condition {
            pc = pc &+ UInt16(bitPattern: Int16(offset))
            bus.tick()
        }
    }

    @inline(__always) func jp(_ condition: Bool) {
        let target = fetch16()
        if condition {
            pc = target
            bus.tick()
        }
    }

    @inline(__always) func call(_ condition: Bool) {
        let target = fetch16()
        if condition {
            bus.tick()
            push(pc)
            pc = target
        }
    }

    @inline(__always) func ret(_ condition: Bool) {
        bus.tick()
        if condition {
            pc = pop()
            bus.tick()
        }
    }

    @inline(__always) func rst(_ vector: UInt16) {
        bus.tick()
        push(pc)
        pc = vector
    }

    // MARK: Opcodes

    func execute(_ op: UInt8) {
        switch op {
        case 0x00: break
        case 0x01: bc = fetch16()
        case 0x02: write(bc, a)
        case 0x03: bc &+= 1; bus.tick()
        case 0x04: b = inc(b)
        case 0x05: b = dec(b)
        case 0x06: b = fetch()
        case 0x07:
            let carry = a >> 7
            a = a << 1 | carry
            f = carry != 0 ? 0x10 : 0
        case 0x08:
            let addr = fetch16()
            write(addr, UInt8(sp & 0xFF))
            write(addr &+ 1, UInt8(sp >> 8))
        case 0x09: addHL(bc)
        case 0x0A: a = read(bc)
        case 0x0B: bc &-= 1; bus.tick()
        case 0x0C: c = inc(c)
        case 0x0D: c = dec(c)
        case 0x0E: c = fetch()
        case 0x0F:
            let carry = a & 1
            a = a >> 1 | carry << 7
            f = carry != 0 ? 0x10 : 0
        case 0x10:
            _ = fetch()
            bus.stop()
        case 0x11: de = fetch16()
        case 0x12: write(de, a)
        case 0x13: de &+= 1; bus.tick()
        case 0x14: d = inc(d)
        case 0x15: d = dec(d)
        case 0x16: d = fetch()
        case 0x17:
            let carry = a >> 7
            a = a << 1 | (flagC ? 1 : 0)
            f = carry != 0 ? 0x10 : 0
        case 0x18: jr(true)
        case 0x19: addHL(de)
        case 0x1A: a = read(de)
        case 0x1B: de &-= 1; bus.tick()
        case 0x1C: e = inc(e)
        case 0x1D: e = dec(e)
        case 0x1E: e = fetch()
        case 0x1F:
            let carry = a & 1
            a = a >> 1 | (flagC ? 0x80 : 0)
            f = carry != 0 ? 0x10 : 0
        case 0x20: jr(!flagZ)
        case 0x21: hl = fetch16()
        case 0x22: write(hl, a); hl &+= 1
        case 0x23: hl &+= 1; bus.tick()
        case 0x24: h = inc(h)
        case 0x25: h = dec(h)
        case 0x26: h = fetch()
        case 0x27: daa()
        case 0x28: jr(flagZ)
        case 0x29: addHL(hl)
        case 0x2A: a = read(hl); hl &+= 1
        case 0x2B: hl &-= 1; bus.tick()
        case 0x2C: l = inc(l)
        case 0x2D: l = dec(l)
        case 0x2E: l = fetch()
        case 0x2F:
            a = ~a
            f = (f & 0x90) | 0x60
        case 0x30: jr(!flagC)
        case 0x31: sp = fetch16()
        case 0x32: write(hl, a); hl &-= 1
        case 0x33: sp &+= 1; bus.tick()
        case 0x34: write(hl, inc(read(hl)))
        case 0x35: write(hl, dec(read(hl)))
        case 0x36: write(hl, fetch())
        case 0x37: f = (f & 0x80) | 0x10
        case 0x38: jr(flagC)
        case 0x39: addHL(sp)
        case 0x3A: a = read(hl); hl &-= 1
        case 0x3B: sp &-= 1; bus.tick()
        case 0x3C: a = inc(a)
        case 0x3D: a = dec(a)
        case 0x3E: a = fetch()
        case 0x3F: f = (f & 0x80) | (flagC ? 0 : 0x10)

        case 0x76:
            let pending = bus.interruptEnable & bus.interruptFlag & 0x1F
            if !ime && pending != 0 {
                haltBug = true
            } else {
                halted = true
            }
        case 0x40...0x7F:
            setReg((op >> 3) & 7, reg(op & 7))
        case 0x80...0xBF:
            alu((op >> 3) & 7, reg(op & 7))

        case 0xC0: ret(!flagZ)
        case 0xC1: bc = pop()
        case 0xC2: jp(!flagZ)
        case 0xC3: jp(true)
        case 0xC4: call(!flagZ)
        case 0xC5: bus.tick(); push(bc)
        case 0xC6: alu(0, fetch())
        case 0xC7: rst(0x00)
        case 0xC8: ret(flagZ)
        case 0xC9: pc = pop(); bus.tick()
        case 0xCA: jp(flagZ)
        case 0xCB: executeCB(fetch())
        case 0xCC: call(flagZ)
        case 0xCD: call(true)
        case 0xCE: alu(1, fetch())
        case 0xCF: rst(0x08)
        case 0xD0: ret(!flagC)
        case 0xD1: de = pop()
        case 0xD2: jp(!flagC)
        case 0xD4: call(!flagC)
        case 0xD5: bus.tick(); push(de)
        case 0xD6: alu(2, fetch())
        case 0xD7: rst(0x10)
        case 0xD8: ret(flagC)
        case 0xD9:
            pc = pop()
            bus.tick()
            ime = true
            imeDelay = 0
        case 0xDA: jp(flagC)
        case 0xDC: call(flagC)
        case 0xDE: alu(3, fetch())
        case 0xDF: rst(0x18)
        case 0xE0: write(0xFF00 | UInt16(fetch()), a)
        case 0xE1: hl = pop()
        case 0xE2: write(0xFF00 | UInt16(c), a)
        case 0xE5: bus.tick(); push(hl)
        case 0xE6: alu(4, fetch())
        case 0xE7: rst(0x20)
        case 0xE8:
            sp = spPlusOffset()
            bus.tick()
            bus.tick()
        case 0xE9: pc = hl
        case 0xEA: write(fetch16(), a)
        case 0xEE: alu(5, fetch())
        case 0xEF: rst(0x28)
        case 0xF0: a = read(0xFF00 | UInt16(fetch()))
        case 0xF1: af = pop()
        case 0xF2: a = read(0xFF00 | UInt16(c))
        case 0xF3:
            ime = false
            imeDelay = 0
        case 0xF5: bus.tick(); push(af)
        case 0xF6: alu(6, fetch())
        case 0xF7: rst(0x30)
        case 0xF8:
            hl = spPlusOffset()
            bus.tick()
        case 0xF9: sp = hl; bus.tick()
        case 0xFA: a = read(fetch16())
        case 0xFB:
            if !ime && imeDelay == 0 { imeDelay = 2 }
        case 0xFE: alu(7, fetch())
        case 0xFF: rst(0x38)
        default:
            // 0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD
            locked = true
        }
    }

    func executeCB(_ op: UInt8) {
        let index = op & 7
        let bit = (op >> 3) & 7
        switch op >> 6 {
        case 0:
            var v = reg(index)
            var carry: UInt8
            switch bit {
            case 0: // RLC
                carry = v >> 7
                v = v << 1 | carry
            case 1: // RRC
                carry = v & 1
                v = v >> 1 | carry << 7
            case 2: // RL
                carry = v >> 7
                v = v << 1 | (flagC ? 1 : 0)
            case 3: // RR
                carry = v & 1
                v = v >> 1 | (flagC ? 0x80 : 0)
            case 4: // SLA
                carry = v >> 7
                v <<= 1
            case 5: // SRA
                carry = v & 1
                v = v >> 1 | (v & 0x80)
            case 6: // SWAP
                carry = 0
                v = v << 4 | v >> 4
            default: // SRL
                carry = v & 1
                v >>= 1
            }
            f = (v == 0 ? 0x80 : 0) | (carry != 0 ? 0x10 : 0)
            setReg(index, v)
        case 1:
            let v = reg(index)
            f = (f & 0x10) | 0x20 | (v & (1 << bit) == 0 ? 0x80 : 0)
        case 2:
            setReg(index, reg(index) & ~(1 << bit))
        default:
            setReg(index, reg(index) | (1 << bit))
        }
    }

    // MARK: State

    func save(_ w: inout StateWriter) {
        for r in [a, f, b, c, d, e, h, l] { w.u8(r) }
        w.u16(sp)
        w.u16(pc)
        w.bool(ime)
        w.int(imeDelay)
        w.bool(halted)
        w.bool(haltBug)
        w.bool(locked)
    }

    func load(_ r: inout StateReader) throws {
        a = try r.u8(); f = try r.u8(); b = try r.u8(); c = try r.u8()
        d = try r.u8(); e = try r.u8(); h = try r.u8(); l = try r.u8()
        sp = try r.u16()
        pc = try r.u16()
        ime = try r.bool()
        imeDelay = try r.int()
        halted = try r.bool()
        haltBug = try r.bool()
        locked = try r.bool()
    }
}

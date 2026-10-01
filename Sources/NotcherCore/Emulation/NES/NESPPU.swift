import Foundation

/// The 2C02 picture processor, stepped one dot at a time with the usual
/// background shift registers and loopy scroll registers, so mid-frame
/// scroll splits and sprite-0 hits behave like the real thing.
final class NESPPU {
    static let width = 256
    static let height = 240

    unowned(unsafe) let bus: NES

    var ctrl: UInt8 = 0
    var mask: UInt8 = 0
    var status: UInt8 = 0
    var oamAddr: UInt8 = 0
    let oam = ByteBuffer(count: 256)
    let vram = ByteBuffer(count: 0x1000)
    let palette = ByteBuffer(count: 32)

    // Loopy registers.
    var v: UInt16 = 0
    var t: UInt16 = 0
    var fineX: UInt8 = 0
    var latch = false
    var readBuffer: UInt8 = 0
    var openBus: UInt8 = 0

    var scanline = 261
    var dot = 0
    var oddFrame = false
    var frameComplete = false

    // Background pipeline.
    var nextTile: UInt8 = 0
    var nextAttribute: UInt8 = 0
    var nextLow: UInt8 = 0
    var nextHigh: UInt8 = 0
    var shiftPatternLow: UInt16 = 0
    var shiftPatternHigh: UInt16 = 0
    var shiftAttributeLow: UInt16 = 0
    var shiftAttributeHigh: UInt16 = 0

    // Sprites for the line being drawn.
    var spriteCount = 0
    var spriteX = [Int](repeating: 0, count: 8)
    var spriteAttr = [UInt8](repeating: 0, count: 8)
    var spriteLow = [UInt8](repeating: 0, count: 8)
    var spriteHigh = [UInt8](repeating: 0, count: 8)
    var spriteZeroOnLine = false

    var frame = [UInt32](repeating: 0xFF00_0000, count: 256 * 240)

    init(bus: NES) {
        self.bus = bus
    }

    var renderingEnabled: Bool { mask & 0x18 != 0 }

    // MARK: Registers

    func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg & 7 {
        case 2:
            let value = (status & 0xE0) | (openBus & 0x1F)
            status &= 0x7F
            latch = false
            openBus = value
            return value
        case 4:
            openBus = oam[Int(oamAddr)]
            return openBus
        case 7:
            var value: UInt8
            let addr = v & 0x3FFF
            if addr >= 0x3F00 {
                value = (readPalette(addr) & 0x3F) | (openBus & 0xC0)
                readBuffer = memoryRead(addr &- 0x1000)
            } else {
                value = readBuffer
                readBuffer = memoryRead(addr)
            }
            v = (v &+ (ctrl & 0x04 != 0 ? 32 : 1)) & 0x7FFF
            openBus = value
            return value
        default:
            return openBus
        }
    }

    func writeRegister(_ reg: UInt16, _ value: UInt8) {
        openBus = value
        switch reg & 7 {
        case 0:
            let wasEnabled = ctrl & 0x80 != 0
            ctrl = value
            t = (t & 0xF3FF) | (UInt16(value & 0x03) << 10)
            // Enabling NMI during VBlank fires it straight away.
            if !wasEnabled && value & 0x80 != 0 && status & 0x80 != 0 {
                bus.cpu.nmiPending = true
            }
        case 1:
            mask = value
        case 3:
            oamAddr = value
        case 4:
            oam[Int(oamAddr)] = value
            oamAddr &+= 1
        case 5:
            if !latch {
                fineX = value & 0x07
                t = (t & 0xFFE0) | UInt16(value >> 3)
            } else {
                t = (t & 0x8C1F) | (UInt16(value & 0x07) << 12) | (UInt16(value & 0xF8) << 2)
            }
            latch.toggle()
        case 6:
            if !latch {
                t = (t & 0x00FF) | (UInt16(value & 0x3F) << 8)
            } else {
                t = (t & 0xFF00) | UInt16(value)
                v = t
            }
            latch.toggle()
        case 7:
            memoryWrite(v & 0x3FFF, value)
            v = (v &+ (ctrl & 0x04 != 0 ? 32 : 1)) & 0x7FFF
        default:
            break
        }
    }

    // MARK: Memory

    @inline(__always) func nametableIndex(_ addr: UInt16) -> Int {
        let a = Int(addr & 0x0FFF)
        let table = a / 0x400
        let offset = a & 0x3FF
        switch bus.cart.mirroring {
        case .vertical: return (table & 1) * 0x400 + offset
        case .horizontal: return (table >> 1) * 0x400 + offset
        case .singleLow: return offset
        case .singleHigh: return 0x400 + offset
        case .fourScreen: return a
        }
    }

    @inline(__always) func paletteIndex(_ addr: UInt16) -> Int {
        var i = Int(addr & 0x1F)
        if i & 0x13 == 0x10 { i &= ~0x10 }
        return i
    }

    @inline(__always) func readPalette(_ addr: UInt16) -> UInt8 {
        palette[paletteIndex(addr)]
    }

    @inline(__always) func memoryRead(_ addr: UInt16) -> UInt8 {
        let a = addr & 0x3FFF
        if a < 0x2000 { return bus.cart.ppuRead(a) }
        if a < 0x3F00 { return vram[nametableIndex(a)] }
        return readPalette(a)
    }

    func memoryWrite(_ addr: UInt16, _ value: UInt8) {
        let a = addr & 0x3FFF
        if a < 0x2000 {
            bus.cart.ppuWrite(a, value)
        } else if a < 0x3F00 {
            vram[nametableIndex(a)] = value
        } else {
            palette[paletteIndex(a)] = value & 0x3F
        }
    }

    // MARK: Scrolling

    @inline(__always) private func incrementX() {
        if v & 0x001F == 31 {
            v &= ~0x001F
            v ^= 0x0400
        } else {
            v &+= 1
        }
    }

    @inline(__always) private func incrementY() {
        if v & 0x7000 != 0x7000 {
            v &+= 0x1000
        } else {
            v &= ~0x7000
            var y = (v & 0x03E0) >> 5
            if y == 29 {
                y = 0
                v ^= 0x0800
            } else if y == 31 {
                y = 0
            } else {
                y += 1
            }
            v = (v & ~0x03E0) | (y << 5)
        }
    }

    @inline(__always) private func copyX() {
        v = (v & ~0x041F) | (t & 0x041F)
    }

    @inline(__always) private func copyY() {
        v = (v & ~0x7BE0) | (t & 0x7BE0)
    }

    @inline(__always) private func loadShifters() {
        shiftPatternLow = (shiftPatternLow & 0xFF00) | UInt16(nextLow)
        shiftPatternHigh = (shiftPatternHigh & 0xFF00) | UInt16(nextHigh)
        shiftAttributeLow = (shiftAttributeLow & 0xFF00) | (nextAttribute & 1 != 0 ? 0xFF : 0)
        shiftAttributeHigh = (shiftAttributeHigh & 0xFF00) | (nextAttribute & 2 != 0 ? 0xFF : 0)
    }

    @inline(__always) private func shiftBackground() {
        shiftPatternLow <<= 1
        shiftPatternHigh <<= 1
        shiftAttributeLow <<= 1
        shiftAttributeHigh <<= 1
    }

    // MARK: Sprites

    private func evaluateSprites() {
        spriteCount = 0
        spriteZeroOnLine = false
        let height = ctrl & 0x20 != 0 ? 16 : 8
        let line = scanline
        var found = 0
        for i in 0..<64 {
            let y = Int(oam[i * 4])
            let row = line - y
            guard row >= 0 && row < height else { continue }
            if found == 8 {
                status |= 0x20
                break
            }
            let tile = oam[i * 4 + 1]
            let attr = oam[i * 4 + 2]
            var r = attr & 0x80 != 0 ? height - 1 - row : row
            let addr: UInt16
            if height == 16 {
                let table: UInt16 = tile & 1 != 0 ? 0x1000 : 0
                var index = UInt16(tile & 0xFE)
                if r >= 8 {
                    index += 1
                    r -= 8
                }
                addr = table | (index << 4) | UInt16(r)
            } else {
                let table: UInt16 = ctrl & 0x08 != 0 ? 0x1000 : 0
                addr = table | (UInt16(tile) << 4) | UInt16(r)
            }
            var low = bus.cart.ppuRead(addr)
            var high = bus.cart.ppuRead(addr + 8)
            if attr & 0x40 != 0 {
                low = low.bitReversed
                high = high.bitReversed
            }
            spriteX[found] = Int(oam[i * 4 + 3])
            spriteAttr[found] = attr
            spriteLow[found] = low
            spriteHigh[found] = high
            if i == 0 { spriteZeroOnLine = true }
            found += 1
        }
        spriteCount = found
    }

    // MARK: Dot

    @inline(__always) func step() {
        let visibleLine = scanline < 240
        let preRender = scanline == 261
        let rendering = renderingEnabled

        if visibleLine || preRender {
            if preRender && dot == 1 {
                status &= 0x1F
            }
            if rendering {
                if (dot >= 2 && dot <= 257) || (dot >= 321 && dot <= 337) {
                    shiftBackground()
                    switch (dot - 1) & 7 {
                    case 0:
                        loadShifters()
                        nextTile = vram[nametableIndex(0x2000 | (v & 0x0FFF))]
                    case 2:
                        let coarse: UInt16 = ((v >> 4) & 0x38) | ((v >> 2) & 0x07)
                        let addr: UInt16 = 0x23C0 | (v & 0x0C00) | coarse
                        var at = vram[nametableIndex(addr)]
                        if (v >> 5) & 0x02 != 0 { at >>= 4 }
                        if v & 0x02 != 0 { at >>= 2 }
                        nextAttribute = at & 0x03
                    case 4:
                        let base: UInt16 = ctrl & 0x10 != 0 ? 0x1000 : 0
                        nextLow = bus.cart.ppuRead(base + UInt16(nextTile) * 16 + ((v >> 12) & 7))
                    case 6:
                        let base: UInt16 = ctrl & 0x10 != 0 ? 0x1000 : 0
                        nextHigh = bus.cart.ppuRead(base + UInt16(nextTile) * 16 + ((v >> 12) & 7) + 8)
                    case 7:
                        incrementX()
                    default:
                        break
                    }
                }
                if dot == 256 { incrementY() }
                if dot == 257 {
                    loadShifters()
                    copyX()
                    if visibleLine { evaluateSprites() } else { spriteCount = 0 }
                }
                if preRender && dot >= 280 && dot <= 304 { copyY() }
                if dot == 260 { bus.cart.scanline() }
            }
            if visibleLine && dot >= 1 && dot <= 256 {
                renderPixel(dot - 1)
            }
        } else if scanline == 241 && dot == 1 {
            status |= 0x80
            if ctrl & 0x80 != 0 { bus.cpu.nmiPending = true }
        }

        dot += 1
        // Odd frames skip the last dot of the pre-render line when rendering.
        if preRender && dot == 340 && oddFrame && rendering {
            dot = 341
        }
        if dot > 340 {
            dot = 0
            scanline += 1
            if scanline == 240 {
                frameComplete = true
            }
            if scanline > 261 {
                scanline = 0
                oddFrame.toggle()
            }
        }
    }

    @inline(__always) private func renderPixel(_ x: Int) {
        var bgPixel: UInt8 = 0
        var bgPalette: UInt8 = 0
        if mask & 0x08 != 0 && (x >= 8 || mask & 0x02 != 0) {
            let bit: UInt16 = 0x8000 >> UInt16(fineX)
            let p0: UInt8 = shiftPatternLow & bit != 0 ? 1 : 0
            let p1: UInt8 = shiftPatternHigh & bit != 0 ? 2 : 0
            bgPixel = p0 | p1
            let a0: UInt8 = shiftAttributeLow & bit != 0 ? 1 : 0
            let a1: UInt8 = shiftAttributeHigh & bit != 0 ? 2 : 0
            bgPalette = a0 | a1
        }

        var spritePixel: UInt8 = 0
        var spritePalette: UInt8 = 0
        var spriteBehind = false
        if mask & 0x10 != 0 && (x >= 8 || mask & 0x04 != 0) {
            for i in 0..<spriteCount {
                let offset = x - spriteX[i]
                guard offset >= 0 && offset < 8 else { continue }
                let shift = UInt8(7 - offset)
                let color = ((spriteHigh[i] >> shift) & 1) << 1 | ((spriteLow[i] >> shift) & 1)
                guard color != 0 else { continue }
                if i == 0 && spriteZeroOnLine && bgPixel != 0 && x != 255 {
                    status |= 0x40
                }
                spritePixel = color
                spritePalette = (spriteAttr[i] & 0x03) + 4
                spriteBehind = spriteAttr[i] & 0x20 != 0
                break
            }
            // Sprite 0 can hit behind a higher-priority sprite too.
            if spriteZeroOnLine && status & 0x40 == 0 && bgPixel != 0 && x != 255 && spriteCount > 0 {
                let offset = x - spriteX[0]
                if offset >= 0 && offset < 8 {
                    let shift = UInt8(7 - offset)
                    if ((spriteHigh[0] >> shift) & 1) | ((spriteLow[0] >> shift) & 1) != 0 {
                        status |= 0x40
                    }
                }
            }
        }

        var index: Int
        if bgPixel == 0 && spritePixel == 0 {
            index = 0
        } else if bgPixel == 0 {
            index = Int(spritePalette) * 4 + Int(spritePixel)
        } else if spritePixel == 0 || spriteBehind {
            index = Int(bgPalette) * 4 + Int(bgPixel)
        } else {
            index = Int(spritePalette) * 4 + Int(spritePixel)
        }
        var color = palette[paletteIndex(UInt16(index))]
        if mask & 0x01 != 0 { color &= 0x30 }
        frame[scanline * 256 + x] = NESPPU.colors[Int(color & 0x3F)]
    }

    static let colors: [UInt32] = ([
        0x666666, 0x002A88, 0x1412A7, 0x3B00A4, 0x5C007E, 0x6E0040, 0x6C0600, 0x561D00,
        0x333500, 0x0B4800, 0x005200, 0x004F08, 0x00404D, 0x000000, 0x000000, 0x000000,
        0xADADAD, 0x155FD9, 0x4240FF, 0x7527FE, 0xA01ACC, 0xB71E7B, 0xB53120, 0x994E00,
        0x6B6D00, 0x388700, 0x0C9300, 0x008F32, 0x007C8D, 0x000000, 0x000000, 0x000000,
        0xFFFEFF, 0x64B0FF, 0x9290FF, 0xC676FF, 0xF36AFF, 0xFE6ECC, 0xFE8170, 0xEA9E22,
        0xBCBE00, 0x88D800, 0x5CE430, 0x45E082, 0x48CDDE, 0x4F4F4F, 0x000000, 0x000000,
        0xFFFEFF, 0xC0DFFF, 0xD3D2FF, 0xE8C8FF, 0xFBC2FF, 0xFEC4EA, 0xFECCC5, 0xF7D8A5,
        0xE4E594, 0xCFEF96, 0xBDF4AB, 0xB3F3CC, 0xB5EBF2, 0xB8B8B8, 0x000000, 0x000000,
    ] as [UInt32]).map { 0xFF00_0000 | $0 }

    // MARK: State

    func save(_ w: inout StateWriter) {
        for b in [ctrl, mask, status, oamAddr, fineX, readBuffer, openBus, nextTile, nextAttribute, nextLow, nextHigh] { w.u8(b) }
        w.bytes(oam.pointer, count: oam.count)
        w.bytes(vram.pointer, count: vram.count)
        w.bytes(palette.pointer, count: palette.count)
        w.u16(v); w.u16(t)
        w.bool(latch)
        w.int(scanline); w.int(dot)
        w.bool(oddFrame)
        for s in [shiftPatternLow, shiftPatternHigh, shiftAttributeLow, shiftAttributeHigh] { w.u16(s) }
        w.int(spriteCount)
        for i in 0..<8 {
            w.int(spriteX[i]); w.u8(spriteAttr[i]); w.u8(spriteLow[i]); w.u8(spriteHigh[i])
        }
        w.bool(spriteZeroOnLine)
    }

    func load(_ r: inout StateReader) throws {
        ctrl = try r.u8(); mask = try r.u8(); status = try r.u8(); oamAddr = try r.u8(); fineX = try r.u8()
        readBuffer = try r.u8(); openBus = try r.u8(); nextTile = try r.u8(); nextAttribute = try r.u8()
        nextLow = try r.u8(); nextHigh = try r.u8()
        try r.bytes(into: oam.pointer, count: oam.count)
        try r.bytes(into: vram.pointer, count: vram.count)
        try r.bytes(into: palette.pointer, count: palette.count)
        v = try r.u16(); t = try r.u16()
        latch = try r.bool()
        scanline = try r.int(); dot = try r.int()
        guard (0...261).contains(scanline), (0...340).contains(dot) else { throw EmulatorError.badSaveState }
        oddFrame = try r.bool()
        shiftPatternLow = try r.u16(); shiftPatternHigh = try r.u16()
        shiftAttributeLow = try r.u16(); shiftAttributeHigh = try r.u16()
        spriteCount = min(8, max(0, try r.int()))
        for i in 0..<8 {
            spriteX[i] = try r.int(); spriteAttr[i] = try r.u8(); spriteLow[i] = try r.u8(); spriteHigh[i] = try r.u8()
        }
        spriteZeroOnLine = try r.bool()
    }
}

extension UInt8 {
    var bitReversed: UInt8 {
        var b = self
        b = (b & 0xF0) >> 4 | (b & 0x0F) << 4
        b = (b & 0xCC) >> 2 | (b & 0x33) << 2
        b = (b & 0xAA) >> 1 | (b & 0x55) << 1
        return b
    }
}

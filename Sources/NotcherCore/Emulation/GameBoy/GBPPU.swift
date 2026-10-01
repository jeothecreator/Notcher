import Foundation

/// Game Boy picture processor. Timing is tracked per dot; each line is drawn
/// in one go when the line enters HBlank, which covers the raster effects
/// games use (scroll splits, window tricks, palette changes between lines).
final class GBPPU {
    static let width = 160
    static let height = 144

    unowned(unsafe) let bus: GameBoy
    let cgb: Bool

    let vram = ByteBuffer(count: 0x4000)
    let oam = ByteBuffer(count: 0xA0)
    var vramBank = 0

    var lcdc: UInt8 = 0x91
    var statEnable: UInt8 = 0
    var scy: UInt8 = 0, scx: UInt8 = 0
    var ly: UInt8 = 0, lyc: UInt8 = 0
    var bgp: UInt8 = 0xFC, obp0: UInt8 = 0xFF, obp1: UInt8 = 0xFF
    var wy: UInt8 = 0, wx: UInt8 = 0
    var dmaRegister: UInt8 = 0xFF

    var mode: UInt8 = 1
    var dot = 0
    var windowLine = 0
    var windowTriggered = false
    var statLine = false
    var frameReady = false

    // CGB palette memory, 8 palettes × 4 colors × 2 bytes each.
    let bgPalette = ByteBuffer(count: 64, fill: 0xFF)
    let objPalette = ByteBuffer(count: 64, fill: 0xFF)
    var bcps: UInt8 = 0
    var ocps: UInt8 = 0

    /// The finished picture, 0xAARRGGBB.
    var frame: [UInt32]
    /// Four shades for original Game Boy games, lightest first.
    var dmgColors: [UInt32] = GBPPU.greenShades

    static let greenShades: [UInt32] = [0xFFE0_F8D0, 0xFF88_C070, 0xFF34_6856, 0xFF08_1820]
    static let grayShades: [UInt32] = [0xFFF4_F4EE, 0xFFA9_A9A3, 0xFF5C_5C58, 0xFF1A_1A18]

    // Line scratch: background color index and CGB attribute priority.
    private var lineColor = [UInt8](repeating: 0, count: 160)
    private var linePriority = [Bool](repeating: false, count: 160)
    private var lineObj = [Int32](repeating: -1, count: 160)
    private static let colorTable: [UInt32] = GBPPU.makeColorTable()

    init(bus: GameBoy, cgb: Bool) {
        self.bus = bus
        self.cgb = cgb
        frame = [UInt32](repeating: 0xFF00_0000, count: 160 * 144)
        if !cgb { frame = [UInt32](repeating: GBPPU.greenShades[0], count: 160 * 144) }
        ly = 0
        mode = 2
    }

    var lcdOn: Bool { lcdc & 0x80 != 0 }

    // MARK: Timing

    @inline(__always) func step(_ dots: Int) {
        guard lcdOn else { return }
        var remaining = dots
        while remaining > 0 {
            remaining -= 1
            dot += 1
            if ly < 144 {
                if dot == 80 {
                    setMode(3)
                } else if dot == 252 {
                    renderLine()
                    setMode(0)
                    bus.hblank()
                }
            }
            if dot == 456 {
                dot = 0
                ly += 1
                if ly == 144 {
                    setMode(1)
                    bus.interruptFlag |= 0x01
                    frameReady = true
                } else if ly == 154 {
                    ly = 0
                    windowLine = 0
                    windowTriggered = false
                }
                if ly < 144 {
                    if ly == wy { windowTriggered = true }
                    setMode(2)
                } else {
                    updateStat()
                }
            }
        }
    }

    private func setMode(_ m: UInt8) {
        mode = m
        updateStat()
    }

    func updateStat() {
        guard lcdOn else {
            statLine = false
            return
        }
        let line = (statEnable & 0x40 != 0 && ly == lyc)
            || (statEnable & 0x08 != 0 && mode == 0)
            || (statEnable & 0x10 != 0 && mode == 2)
            || (statEnable & 0x20 != 0 && mode == 1)
        if line && !statLine {
            bus.interruptFlag |= 0x02
        }
        statLine = line
    }

    // MARK: Registers

    func readRegister(_ addr: UInt16) -> UInt8 {
        switch addr & 0xFF {
        case 0x40: return lcdc
        case 0x41:
            let coincidence: UInt8 = ly == lyc ? 0x04 : 0
            return 0x80 | statEnable | coincidence | (lcdOn ? mode : 0)
        case 0x42: return scy
        case 0x43: return scx
        case 0x44: return ly
        case 0x45: return lyc
        case 0x46: return dmaRegister
        case 0x47: return bgp
        case 0x48: return obp0
        case 0x49: return obp1
        case 0x4A: return wy
        case 0x4B: return wx
        default: return 0xFF
        }
    }

    func writeRegister(_ addr: UInt16, _ v: UInt8) {
        switch addr & 0xFF {
        case 0x40:
            let wasOn = lcdOn
            lcdc = v
            if wasOn && !lcdOn {
                ly = 0
                dot = 0
                mode = 0
                statLine = false
                // A blank screen while the LCD is off.
                let blank = cgb ? 0xFFFF_FFFF : dmgColors[0]
                for i in frame.indices { frame[i] = blank }
            } else if !wasOn && lcdOn {
                ly = 0
                dot = 0
                windowLine = 0
                windowTriggered = wy == 0
                setMode(2)
            }
        case 0x41:
            statEnable = v & 0x78
            updateStat()
        case 0x42: scy = v
        case 0x43: scx = v
        case 0x45:
            lyc = v
            updateStat()
        case 0x46: dmaRegister = v
        case 0x47: bgp = v
        case 0x48: obp0 = v
        case 0x49: obp1 = v
        case 0x4A: wy = v
        case 0x4B: wx = v
        default: break
        }
    }

    @inline(__always) func readVRAM(_ addr: UInt16) -> UInt8 {
        vram[vramBank * 0x2000 + Int(addr & 0x1FFF)]
    }

    @inline(__always) func writeVRAM(_ addr: UInt16, _ v: UInt8) {
        vram[vramBank * 0x2000 + Int(addr & 0x1FFF)] = v
    }

    // MARK: CGB palettes

    func readPalette(_ addr: UInt16) -> UInt8 {
        switch addr & 0xFF {
        case 0x68: return bcps | 0x40
        case 0x69: return bgPalette[Int(bcps & 0x3F)]
        case 0x6A: return ocps | 0x40
        case 0x6B: return objPalette[Int(ocps & 0x3F)]
        default: return 0xFF
        }
    }

    func writePalette(_ addr: UInt16, _ v: UInt8) {
        switch addr & 0xFF {
        case 0x68: bcps = v & 0xBF
        case 0x69:
            bgPalette[Int(bcps & 0x3F)] = v
            if bcps & 0x80 != 0 { bcps = 0x80 | ((bcps &+ 1) & 0x3F) }
        case 0x6A: ocps = v & 0xBF
        case 0x6B:
            objPalette[Int(ocps & 0x3F)] = v
            if ocps & 0x80 != 0 { ocps = 0x80 | ((ocps &+ 1) & 0x3F) }
        default: break
        }
    }

    // MARK: Rendering

    /// 15-bit CGB color → 0xAARRGGBB with a mild LCD-like correction.
    private static func makeColorTable() -> [UInt32] {
        var table = [UInt32](repeating: 0, count: 0x8000)
        for v in 0..<0x8000 {
            let r = v & 0x1F, g = (v >> 5) & 0x1F, b = (v >> 10) & 0x1F
            let rr = (r * 26 + g * 4 + b * 2) / 32
            let gg = (g * 24 + b * 8) / 32
            let bb = (r * 6 + g * 4 + b * 22) / 32
            func scale(_ x: Int) -> UInt32 { UInt32(min(255, x * 255 / 31)) }
            table[v] = 0xFF00_0000 | scale(rr) << 16 | scale(gg) << 8 | scale(bb)
        }
        return table
    }

    @inline(__always) private func cgbColor(_ palette: ByteBuffer, _ index: Int) -> UInt32 {
        let v = Int(palette[index]) | Int(palette[index + 1]) << 8
        return GBPPU.colorTable[v & 0x7FFF]
    }

    private func renderLine() {
        let y = Int(ly)
        let row = y * 160
        let vram = self.vram

        // Background and window.
        let bgOn = cgb || lcdc & 0x01 != 0
        if bgOn {
            let windowOn = lcdc & 0x20 != 0 && windowTriggered && wx <= 166
            let windowStart = Int(wx) - 7
            var drewWindow = false
            let bgMap = lcdc & 0x08 != 0 ? 0x1C00 : 0x1800
            let winMap = lcdc & 0x40 != 0 ? 0x1C00 : 0x1800
            let unsignedTiles = lcdc & 0x10 != 0
            var x = 0
            while x < 160 {
                let inWindow = windowOn && x >= windowStart
                let px: Int, py: Int, map: Int
                if inWindow {
                    px = x - windowStart
                    py = windowLine
                    map = winMap
                    drewWindow = true
                } else {
                    px = (x + Int(scx)) & 0xFF
                    py = (y + Int(scy)) & 0xFF
                    map = bgMap
                }
                let mapIndex = map + (py >> 3) * 32 + (px >> 3)
                let tile = Int(vram[mapIndex])
                let attr = cgb ? vram[0x2000 + mapIndex] : 0
                var tileRow = py & 7
                if attr & 0x40 != 0 { tileRow = 7 - tileRow }
                let base = unsignedTiles ? tile * 16 : 0x1000 + Int(Int8(bitPattern: UInt8(tile))) * 16
                let bank = attr & 0x08 != 0 ? 0x2000 : 0
                let lo = vram[bank + base + tileRow * 2]
                let hi = vram[bank + base + tileRow * 2 + 1]
                // Draw the rest of this tile's row in one pass.
                var col = px & 7
                while col < 8 && x < 160 {
                    if !inWindow && windowOn && x >= windowStart { break }
                    let bit = attr & 0x20 != 0 ? col : 7 - col
                    let color = ((hi >> UInt8(bit)) & 1) << 1 | ((lo >> UInt8(bit)) & 1)
                    lineColor[x] = color
                    if cgb {
                        linePriority[x] = attr & 0x80 != 0
                        frame[row + x] = cgbColor(bgPalette, Int(attr & 0x07) * 8 + Int(color) * 2)
                    } else {
                        frame[row + x] = dmgColors[Int((bgp >> (color * 2)) & 3)]
                    }
                    col += 1
                    x += 1
                }
            }
            if drewWindow { windowLine += 1 }
        } else {
            let blank = dmgColors[0]
            for x in 0..<160 {
                lineColor[x] = 0
                frame[row + x] = blank
            }
        }

        // Sprites.
        guard lcdc & 0x02 != 0 else { return }
        let height = lcdc & 0x04 != 0 ? 16 : 8
        var found: [Int] = []
        found.reserveCapacity(10)
        for i in 0..<40 {
            let sy = Int(oam[i * 4]) - 16
            if y >= sy && y < sy + height {
                found.append(i)
                if found.count == 10 { break }
            }
        }
        guard !found.isEmpty else { return }
        if !cgb {
            // Lower X wins; ties go to the earlier OAM entry.
            found.sort { a, b in
                let xa = oam[a * 4 + 1], xb = oam[b * 4 + 1]
                return xa != xb ? xa < xb : a < b
            }
        }
        for x in 0..<160 { lineObj[x] = -1 }
        for i in found {
            let o = i * 4
            let sy = Int(oam[o]) - 16
            let sx = Int(oam[o + 1]) - 8
            var tile = Int(oam[o + 2])
            let attr = oam[o + 3]
            var line = y - sy
            if attr & 0x40 != 0 { line = height - 1 - line }
            if height == 16 {
                tile &= 0xFE
                if line >= 8 {
                    tile |= 1
                    line -= 8
                }
            }
            let bank = cgb && attr & 0x08 != 0 ? 0x2000 : 0
            let lo = vram[bank + tile * 16 + line * 2]
            let hi = vram[bank + tile * 16 + line * 2 + 1]
            for col in 0..<8 {
                let x = sx + col
                guard x >= 0 && x < 160, lineObj[x] < 0 else { continue }
                let bit = attr & 0x20 != 0 ? col : 7 - col
                let color = ((hi >> UInt8(bit)) & 1) << 1 | ((lo >> UInt8(bit)) & 1)
                guard color != 0 else { continue }
                lineObj[x] = Int32(i)
                // Background over sprite?
                let bgColor = lineColor[x]
                var hidden = false
                if bgOn && bgColor != 0 {
                    if cgb {
                        hidden = lcdc & 0x01 != 0 && (linePriority[x] || attr & 0x80 != 0)
                    } else {
                        hidden = attr & 0x80 != 0
                    }
                }
                if hidden { continue }
                if cgb {
                    frame[row + x] = cgbColor(objPalette, Int(attr & 0x07) * 8 + Int(color) * 2)
                } else {
                    let palette = attr & 0x10 != 0 ? obp1 : obp0
                    frame[row + x] = dmgColors[Int((palette >> (color * 2)) & 3)]
                }
            }
        }
    }

    // MARK: State

    func save(_ w: inout StateWriter) {
        w.bytes(vram.pointer, count: vram.count)
        w.bytes(oam.pointer, count: oam.count)
        w.bytes(bgPalette.pointer, count: 64)
        w.bytes(objPalette.pointer, count: 64)
        w.int(vramBank)
        for r in [lcdc, statEnable, scy, scx, ly, lyc, bgp, obp0, obp1, wy, wx, dmaRegister, mode, bcps, ocps] { w.u8(r) }
        w.int(dot)
        w.int(windowLine)
        w.bool(windowTriggered)
        w.bool(statLine)
    }

    func load(_ r: inout StateReader) throws {
        try r.bytes(into: vram.pointer, count: vram.count)
        try r.bytes(into: oam.pointer, count: oam.count)
        try r.bytes(into: bgPalette.pointer, count: 64)
        try r.bytes(into: objPalette.pointer, count: 64)
        vramBank = try r.int()
        lcdc = try r.u8(); statEnable = try r.u8(); scy = try r.u8(); scx = try r.u8()
        ly = try r.u8(); lyc = try r.u8(); bgp = try r.u8(); obp0 = try r.u8(); obp1 = try r.u8()
        wy = try r.u8(); wx = try r.u8(); dmaRegister = try r.u8(); mode = try r.u8()
        bcps = try r.u8(); ocps = try r.u8()
        dot = try r.int()
        windowLine = try r.int()
        windowTriggered = try r.bool()
        statLine = try r.bool()
    }
}

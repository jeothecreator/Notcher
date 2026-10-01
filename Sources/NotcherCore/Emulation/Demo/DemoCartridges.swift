import Foundation

/// Three tiny homebrew games built right here: fly a ship through a
/// parallax starfield under a big NOTCHER title. They exist so there is
/// always something to play (and to test and screenshot) before you add
/// ROMs of your own.
///
/// Controls: the D-pad flies, hold A to warp.
public enum DemoCartridges {
    public struct Cartridge: Sendable {
        public let fileName: String
        public let data: [UInt8]
    }

    public static var all: [Cartridge] {
        [
            Cartridge(fileName: "Night Flight (Notcher Demo).nes", data: nes()),
            Cartridge(fileName: "Color Flight (Notcher Demo).gbc", data: gameBoy(color: true)),
            Cartridge(fileName: "Pocket Flight (Notcher Demo).gb", data: gameBoy(color: false)),
        ]
    }

    // MARK: - Tiles

    // Tile numbers shared by both consoles.
    static let brickBase = 0x10
    static let starDim = 0x60, starMid = 0x61, starBright = 0x62
    static let spriteStar = 0x63
    static let shipTiles = 0x70
    static let flameShort = 0x74, flameLong = 0x75

    static let shipArt = [
        "................",
        "................",
        "..3.............",
        "..33............",
        "..313...........",
        ".31113333.......",
        ".311111111333...",
        "3111222111111133",
        "3111222111111133",
        ".311111111333...",
        ".31113333.......",
        "..313...........",
        "..33............",
        "..3.............",
        "................",
        "................",
    ]

    /// Every tile the demos use, by number.
    static func eachTile(_ body: (Int, [[UInt8]]) -> Void) {
        for mask in 1..<16 {
            body(brickBase + mask, TileArt.bricks(mask))
        }
        for (ch, rows) in DemoFont.glyphs {
            guard let ascii = ch.asciiValue else { continue }
            body(Int(ascii), TileArt.glyph(rows, color: 1))
            body(Int(ascii) | 0x80, TileArt.glyph(rows, color: 3))
        }
        body(starDim, TileArt.parse(["", "", "", "....2..."]))
        body(starMid, TileArt.parse(["", "", "", "", "..3....."]))
        body(starBright, TileArt.parse(["", "", "...3....", "..313...", "...3...."]))
        body(spriteStar, TileArt.parse(["", "", "", "...1...."]))
        body(spriteStar + 1, TileArt.parse(["", "", "", "...2...."]))
        body(spriteStar + 2, TileArt.parse(["", "", "", "...31..."]))
        for quarter in 0..<4 {
            let ox = (quarter & 1) * 8
            let oy = (quarter >> 1) * 8
            let rows = (0..<8).map { y -> String in
                let line = Array(shipArt[oy + y])
                return String(line[ox..<(ox + 8)])
            }
            body(shipTiles + quarter, TileArt.parse(rows))
        }
        body(flameShort, TileArt.parse(["", "", "", "...33221", "...33221"]))
        body(flameLong, TileArt.parse(["", "", "......32", "33322211", "33322211", "......32"]))
    }

    // MARK: - Screen layout

    /// A background map: tile numbers and a palette per tile.
    struct Screen {
        let columns: Int
        let rows: Int
        var tiles: [UInt8]
        var palettes: [UInt8]
        /// Half-tile "bricks" for the big title.
        private var cells: [[Bool]]

        init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
            tiles = [UInt8](repeating: 0, count: columns * rows)
            palettes = [UInt8](repeating: 0, count: columns * rows)
            cells = [[Bool]](repeating: [Bool](repeating: false, count: columns * 2), count: rows * 2)
        }

        /// Big brick letters, `width` bricks wide with one brick between letters.
        mutating func title(_ text: String, font: [Character: [UInt8]], width: Int, row: Int) {
            let pitch = width + 1
            let total = text.count * pitch - 1
            let left = (columns * 2 - total) / 2
            for (i, ch) in text.enumerated() {
                guard let glyph = font[ch] else { continue }
                for (y, bits) in glyph.enumerated() {
                    for x in 0..<width where Int(bits) & (1 << (width - 1 - x)) != 0 {
                        cells[row * 2 + y][left + i * pitch + x] = true
                    }
                }
            }
            for ty in 0..<rows {
                for tx in 0..<columns {
                    var mask = 0
                    if cells[ty * 2][tx * 2] { mask |= 1 }
                    if cells[ty * 2][tx * 2 + 1] { mask |= 2 }
                    if cells[ty * 2 + 1][tx * 2] { mask |= 4 }
                    if cells[ty * 2 + 1][tx * 2 + 1] { mask |= 8 }
                    if mask != 0 { tiles[ty * columns + tx] = UInt8(DemoCartridges.brickBase + mask) }
                }
            }
        }

        mutating func text(_ string: String, row: Int, dim: Bool = false) {
            let start = (columns - string.count) / 2
            for (i, ch) in string.enumerated() {
                tiles[row * columns + start + i] = DemoFont.tile(for: ch, dim: dim)
            }
        }

        mutating func palette(_ palette: UInt8, rows range: ClosedRange<Int>) {
            for row in range {
                for col in 0..<columns { palettes[row * columns + col] = palette }
            }
        }

        /// Background stars on empty tiles, away from `avoid`.
        mutating func stars(_ count: Int, seed: UInt32, avoid: Set<Int>) {
            var random = DemoRandom(seed: seed)
            var placed = 0
            var attempts = 0
            while placed < count && attempts < count * 20 {
                attempts += 1
                let x = random.next(columns)
                let y = random.next(rows)
                let i = y * columns + x
                guard !avoid.contains(y), tiles[i] == 0 else { continue }
                let kind = random.next(10)
                tiles[i] = UInt8(kind < 5 ? DemoCartridges.starDim : (kind < 8 ? DemoCartridges.starMid : DemoCartridges.starBright))
                placed += 1
            }
        }
    }

    struct DemoRandom {
        var state: UInt32

        init(seed: UInt32) {
            state = seed
        }

        mutating func next(_ bound: Int) -> Int {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int(state >> 16) % bound
        }
    }

    /// Ship bobbing, as signed bytes.
    static let bob: [UInt8] = [0, 1, 2, 2, 3, 2, 2, 1, 0, 0xFF, 0xFE, 0xFE, 0xFD, 0xFE, 0xFE, 0xFF]

    /// Moving stars: (y, x, layer) for `count` stars spread down the screen.
    static func spriteStars(count: Int, top: Int, spacing: Int, width: Int, seed: UInt32) -> [(y: Int, x: Int, layer: Int)] {
        var random = DemoRandom(seed: seed)
        return (0..<count).map { i in
            (y: top + i * spacing + random.next(3), x: random.next(width), layer: i % 3)
        }
    }

    // MARK: - NES

    /// NROM-128: 16 KB of program at $C000 and 8 KB of tiles.
    public static func nes() -> [UInt8] {
        // Zero page
        let frame: UInt8 = 0x10, pad: UInt8 = 0x11, shipX: UInt8 = 0x12, shipY: UInt8 = 0x13, tmp: UInt8 = 0x14
        let starCount = 24
        var a = DemoAssembler(origin: 0xC000)

        a.label("reset")
        a.op(0x78)                      // SEI
        a.op(0xD8)                      // CLD
        a.op(0xA2, 0x40)                // LDX #$40
        a.at(0x8E, 0x4017)              // STX $4017  (no frame IRQ)
        a.op(0xA2, 0xFF)                // LDX #$FF
        a.op(0x9A)                      // TXS
        a.op(0xE8)                      // INX        (X = 0)
        a.at(0x8E, 0x2000)              // STX $2000
        a.at(0x8E, 0x2001)              // STX $2001
        a.at(0x8E, 0x4010)              // STX $4010
        a.at(0x2C, 0x2002)              // BIT $2002
        a.label("vblank1")
        a.at(0x2C, 0x2002)              // BIT $2002
        a.rel(0x10, "vblank1")          // BPL
        a.op(0xA9, 0x00)                // LDA #0
        a.label("clear")
        a.op(0x95, 0x00)                // STA $00,X
        for page in [0x0100, 0x0300, 0x0400, 0x0500, 0x0600, 0x0700] {
            a.at(0x9D, page)            // STA page,X
        }
        a.op(0xE8)                      // INX
        a.rel(0xD0, "clear")            // BNE
        a.op(0xA9, 0xFF)                // LDA #$FF   (sprites off screen)
        a.label("hide")
        a.at(0x9D, 0x0200)              // STA $0200,X
        a.op(0xE8)
        a.rel(0xD0, "hide")
        a.label("vblank2")
        a.at(0x2C, 0x2002)
        a.rel(0x10, "vblank2")

        // Palettes
        a.at(0xAD, 0x2002)              // LDA $2002
        a.op(0xA9, 0x3F)
        a.at(0x8D, 0x2006)
        a.op(0xA9, 0x00)
        a.at(0x8D, 0x2006)
        a.op(0xA2, 0x00)                // LDX #0
        a.label("palette")
        a.abs(0xBD, "paletteData")      // LDA paletteData,X
        a.at(0x8D, 0x2007)
        a.op(0xE8)
        a.op(0xE0, 0x20)                // CPX #32
        a.rel(0xD0, "palette")

        // Nametable 0, 1 KB through a pointer in $00/$01
        a.at(0xAD, 0x2002)
        a.op(0xA9, 0x20)
        a.at(0x8D, 0x2006)
        a.op(0xA9, 0x00)
        a.at(0x8D, 0x2006)
        a.low(0xA9, "nametable")        // LDA #<nametable
        a.op(0x85, 0x00)
        a.high(0xA9, "nametable")       // LDA #>nametable
        a.op(0x85, 0x01)
        a.op(0xA2, 0x04)                // LDX #4 pages
        a.op(0xA0, 0x00)                // LDY #0
        a.label("nametableLoop")
        a.op(0xB1, 0x00)                // LDA ($00),Y
        a.at(0x8D, 0x2007)
        a.op(0xC8)                      // INY
        a.rel(0xD0, "nametableLoop")
        a.op(0xE6, 0x01)                // INC $01
        a.op(0xCA)                      // DEX
        a.rel(0xD0, "nametableLoop")

        // Star sprites start at sprite 5 ($0214)
        a.op(0xA2, 0x00)
        a.label("starCopy")
        a.abs(0xBD, "starInit")         // LDA starInit,X
        a.at(0x9D, 0x0214)              // STA $0214,X
        a.op(0xE8)
        a.op(0xE0, UInt8(starCount * 4))
        a.rel(0xD0, "starCopy")

        a.op(0xA9, 0x38)
        a.op(0x85, shipX)
        a.op(0xA9, 0x8C)                // between the subtitle and the controls line
        a.op(0x85, shipY)
        a.op(0xA9, 0x00)
        a.at(0x8D, 0x2005)
        a.at(0x8D, 0x2005)
        a.op(0xA9, 0x80)                // NMI on, all tiles from $0000
        a.at(0x8D, 0x2000)
        a.op(0xA9, 0x1E)                // show background and sprites
        a.at(0x8D, 0x2001)

        a.label("main")
        a.op(0xA5, frame)               // LDA frame
        a.label("waitFrame")
        a.op(0xC5, frame)               // CMP frame
        a.rel(0xF0, "waitFrame")        // BEQ
        a.abs(0x20, "readPad")          // JSR
        a.abs(0x20, "moveShip")
        a.abs(0x20, "moveStars")
        a.abs(0x20, "drawShip")
        a.abs(0x4C, "main")             // JMP

        // Controller 1 into `pad`: A B Select Start Up Down Left Right, bit 7 first.
        a.label("readPad")
        a.op(0xA9, 0x01)
        a.at(0x8D, 0x4016)
        a.op(0xA9, 0x00)
        a.at(0x8D, 0x4016)
        a.op(0xA2, 0x08)
        a.label("readBit")
        a.at(0xAD, 0x4016)              // LDA $4016
        a.op(0x4A)                      // LSR A
        a.op(0x26, pad)                 // ROL pad
        a.op(0xCA)
        a.rel(0xD0, "readBit")
        a.op(0x60)                      // RTS

        a.label("moveShip")
        // Up
        a.op(0xA5, pad)
        a.op(0x29, 0x08)
        a.rel(0xF0, "notUp")
        a.op(0xA5, shipY)
        a.op(0xC9, 24)
        a.rel(0x90, "notUp")            // BCC
        a.op(0x38)                      // SEC
        a.op(0xE9, 0x02)                // SBC #2
        a.op(0x85, shipY)
        a.label("notUp")
        // Down
        a.op(0xA5, pad)
        a.op(0x29, 0x04)
        a.rel(0xF0, "notDown")
        a.op(0xA5, shipY)
        a.op(0xC9, 200)
        a.rel(0xB0, "notDown")          // BCS
        a.op(0x18)                      // CLC
        a.op(0x69, 0x02)                // ADC #2
        a.op(0x85, shipY)
        a.label("notDown")
        // Left
        a.op(0xA5, pad)
        a.op(0x29, 0x02)
        a.rel(0xF0, "notLeft")
        a.op(0xA5, shipX)
        a.op(0xC9, 16)
        a.rel(0x90, "notLeft")
        a.op(0x38)
        a.op(0xE9, 0x02)
        a.op(0x85, shipX)
        a.label("notLeft")
        // Right
        a.op(0xA5, pad)
        a.op(0x29, 0x01)
        a.rel(0xF0, "notRight")
        a.op(0xA5, shipX)
        a.op(0xC9, 216)
        a.rel(0xB0, "notRight")
        a.op(0x18)
        a.op(0x69, 0x02)
        a.op(0x85, shipX)
        a.label("notRight")
        a.op(0x60)

        // Stars drift left at their layer's speed, four times as fast while A is held.
        a.label("moveStars")
        a.op(0xA2, 0x00)                // LDX #0 (OAM offset)
        a.op(0xA0, 0x00)                // LDY #0 (star)
        a.label("starLoop")
        a.abs(0xB9, "starSpeed")        // LDA starSpeed,Y
        a.op(0x24, pad)                 // BIT pad (N = A button)
        a.rel(0x10, "noWarp")           // BPL
        a.op(0x0A)                      // ASL A
        a.op(0x0A)                      // ASL A
        a.label("noWarp")
        a.op(0x85, tmp)
        a.at(0xBD, 0x0217)              // LDA $0217,X (sprite x)
        a.op(0x38)
        a.op(0xE5, tmp)                 // SBC tmp
        a.at(0x9D, 0x0217)              // STA $0217,X
        a.op(0xE8, 0xE8, 0xE8, 0xE8)    // X += 4
        a.op(0xC8)                      // INY
        a.op(0xC0, UInt8(starCount))    // CPY
        a.rel(0xD0, "starLoop")
        a.op(0x60)

        // Ship: four sprites plus a flame, bobbing gently.
        a.label("drawShip")
        a.op(0xA5, frame)
        a.op(0x4A, 0x4A, 0x4A)          // LSR ×3
        a.op(0x29, 0x0F)
        a.op(0xAA)                      // TAX
        a.op(0xA5, shipY)
        a.op(0x18)
        a.abs(0x7D, "bobTable")         // ADC bobTable,X
        a.op(0x85, tmp)
        a.at(0x8D, 0x0200)
        a.at(0x8D, 0x0204)
        a.op(0x18)
        a.op(0x69, 0x08)
        a.at(0x8D, 0x0208)
        a.at(0x8D, 0x020C)
        a.op(0xA5, tmp)
        a.op(0x18)
        a.op(0x69, 0x04)
        a.at(0x8D, 0x0210)
        for (i, offset) in [0x0201, 0x0205, 0x0209, 0x020D].enumerated() {
            a.op(0xA9, UInt8(shipTiles + i))
            a.at(0x8D, offset)
        }
        a.op(0xA5, frame)
        a.op(0x29, 0x04)
        a.rel(0xF0, "shortFlame")
        a.op(0xA9, UInt8(flameLong))
        a.rel(0xD0, "flameChosen")      // always taken
        a.label("shortFlame")
        a.op(0xA9, UInt8(flameShort))
        a.label("flameChosen")
        a.op(0x24, pad)                 // BIT pad
        a.rel(0x10, "flameNoWarp")
        a.op(0xA9, UInt8(flameLong))
        a.label("flameNoWarp")
        a.at(0x8D, 0x0211)
        a.op(0xA9, 0x00)
        for offset in [0x0202, 0x0206, 0x020A, 0x020E] { a.at(0x8D, offset) }
        a.op(0xA9, 0x01)
        a.at(0x8D, 0x0212)
        a.op(0xA5, shipX)
        a.at(0x8D, 0x0203)
        a.at(0x8D, 0x020B)
        a.op(0x18)
        a.op(0x69, 0x08)
        a.at(0x8D, 0x0207)
        a.at(0x8D, 0x020F)
        a.op(0xA5, shipX)
        a.op(0x38)
        a.op(0xE9, 0x08)
        a.at(0x8D, 0x0213)
        a.op(0x60)

        // Vertical blank: sprites, the blinking line, scroll.
        a.label("nmi")
        a.op(0x48, 0x8A, 0x48, 0x98, 0x48)   // PHA TXA PHA TYA PHA
        a.op(0xA9, 0x00)
        a.at(0x8D, 0x2003)
        a.op(0xA9, 0x02)
        a.at(0x8D, 0x4014)              // OAM DMA from $0200
        a.at(0xAD, 0x2002)
        a.op(0xA9, 0x3F)
        a.at(0x8D, 0x2006)
        a.op(0xA9, 0x0D)                // background palette 3, colour 1
        a.at(0x8D, 0x2006)
        a.op(0xA5, frame)
        a.op(0x29, 0x20)
        a.rel(0xF0, "blinkOn")
        a.op(0xA9, 0x00)
        a.abs(0x4C, "blinkSet")
        a.label("blinkOn")
        a.op(0xA9, 0x30)
        a.label("blinkSet")
        a.at(0x8D, 0x2007)
        a.op(0xA9, 0x00)
        a.at(0x8D, 0x2005)
        a.at(0x8D, 0x2005)
        a.op(0xA9, 0x80)
        a.at(0x8D, 0x2000)
        a.op(0xE6, frame)               // INC frame
        a.op(0x68, 0xA8, 0x68, 0xAA, 0x68)   // PLA TAY PLA TAX PLA
        a.op(0x40)                      // RTI
        a.label("irq")
        a.op(0x40)

        // Data
        a.label("paletteData")
        a.data([
            0x0F, 0x30, 0x00, 0x10, 0x0F, 0x3C, 0x11, 0x2C, 0x0F, 0x35, 0x14, 0x25, 0x0F, 0x30, 0x00, 0x10,
            0x0F, 0x30, 0x2C, 0x16, 0x0F, 0x28, 0x27, 0x16, 0x0F, 0x00, 0x21, 0x30, 0x0F, 0x30, 0x30, 0x30,
        ])
        a.label("nametable")
        a.data(nesNametable())
        a.label("starInit")
        let stars = spriteStars(count: starCount, top: 18, spacing: 8, width: 256, seed: 0x5EED_0001)
        for star in stars {
            a.data([UInt8(star.y), UInt8(spriteStar + star.layer), 0x22, UInt8(star.x)])
        }
        a.label("starSpeed")
        a.data(stars.map { UInt8($0.layer + 1) })
        a.label("bobTable")
        a.data(bob)

        var prg = a.assembled()
        precondition(prg.count <= 0x3FFA, "NES demo program too large")
        prg += [UInt8](repeating: 0xFF, count: 0x4000 - prg.count)
        func vector(_ label: String, at offset: Int) {
            let address = a.address(of: label) ?? 0xC000
            prg[offset] = UInt8(address & 0xFF)
            prg[offset + 1] = UInt8(address >> 8)
        }
        vector("nmi", at: 0x3FFA)
        vector("reset", at: 0x3FFC)
        vector("irq", at: 0x3FFE)

        var chr = [UInt8](repeating: 0, count: 0x2000)
        eachTile { index, pixels in
            chr.replaceSubrange((index * 16)..<(index * 16 + 16), with: TileArt.nes(pixels))
        }

        let header: [UInt8] = [0x4E, 0x45, 0x53, 0x1A, 1, 1, 0x01, 0x00] + [UInt8](repeating: 0, count: 8)
        return header + prg + chr
    }

    static func nesNametable() -> [UInt8] {
        var screen = Screen(columns: 32, rows: 30)
        screen.title("NOTCHER", font: DemoFont.glyphs, width: 5, row: 6)
        screen.palette(1, rows: 6...7)
        screen.palette(2, rows: 8...9)
        screen.text("NIGHT FLIGHT", row: 12)
        screen.text("A NOTCHER DEMO CARTRIDGE", row: 14, dim: true)
        screen.text("ARROWS FLY - HOLD A TO WARP", row: 21)
        screen.palette(3, rows: 20...21)
        screen.text("PLAY YOUR OWN ROMS IN THE NOTCH", row: 25, dim: true)
        screen.stars(46, seed: 0xC0FF_EE01, avoid: [0, 6, 7, 8, 9, 12, 14, 20, 21, 25, 29])

        var attributes = [UInt8](repeating: 0, count: 64)
        for ay in 0..<8 {
            for ax in 0..<8 {
                var byte: UInt8 = 0
                for quadrant in 0..<4 {
                    let tx = ax * 4 + (quadrant & 1) * 2
                    let ty = ay * 4 + (quadrant >> 1) * 2
                    guard ty < 30 else { continue }
                    byte |= (screen.palettes[ty * 32 + tx] & 3) << UInt8(quadrant * 2)
                }
                attributes[ay * 8 + ax] = byte
            }
        }
        return screen.tiles + attributes
    }

    // MARK: - Game Boy

    /// A 32 KB cartridge without a mapper. The Color version uses the Game Boy
    /// Color's palettes; the other runs in original Game Boy shades.
    public static func gameBoy(color: Bool) -> [UInt8] {
        // Work RAM: shadow OAM at $C000, variables after it.
        let cgbFlag = 0xC0A0, frame = 0xC0A1, pad = 0xC0A2, shipX = 0xC0A3, shipY = 0xC0A4
        let starCount = 20
        var a = DemoAssembler(origin: 0x150)

        a.label("start")
        a.op(0xF3)                      // DI
        a.at(0x31, 0xFFFE)              // LD SP,$FFFE
        a.at(0xEA, cgbFlag)             // LD (cgbFlag),A  ($11 on a Game Boy Color)
        a.label("waitVBlank")
        a.op(0xF0, 0x44)                // LDH A,(LY)
        a.op(0xFE, 144)                 // CP 144
        a.rel(0x38, "waitVBlank")       // JR C
        a.op(0xAF)                      // XOR A
        a.op(0xE0, 0x40)                // LDH (LCDC),A  — screen off

        a.at(0x21, 0x8000)              // LD HL,$8000
        a.abs(0x11, "tiles")            // LD DE,tiles
        a.at(0x01, 0x1000)              // LD BC,4096
        a.abs(0xCD, "copy")             // CALL copy
        a.at(0x21, 0x9800)
        a.abs(0x11, "map")
        a.abs(0xCD, "copyMap")

        a.at(0xFA, cgbFlag)             // LD A,(cgbFlag)
        a.op(0xFE, 0x11)
        a.rel(0x20, "notColor")         // JR NZ
        a.op(0x3E, 0x01)
        a.op(0xE0, 0x4F)                // VRAM bank 1: tile attributes
        a.at(0x21, 0x9800)
        a.abs(0x11, "attributes")
        a.abs(0xCD, "copyMap")
        a.op(0xAF)
        a.op(0xE0, 0x4F)
        a.op(0x3E, 0x80)
        a.op(0xE0, 0x68)                // BCPS: index 0, auto-increment
        a.abs(0x21, "backgroundColors")
        a.op(0x06, 64)
        a.label("bgColors")
        a.op(0x2A)                      // LD A,(HL+)
        a.op(0xE0, 0x69)
        a.op(0x05)                      // DEC B
        a.rel(0x20, "bgColors")
        a.op(0x3E, 0x80)
        a.op(0xE0, 0x6A)                // OCPS
        a.abs(0x21, "spriteColors")
        a.op(0x06, 64)
        a.label("objColors")
        a.op(0x2A)
        a.op(0xE0, 0x6B)
        a.op(0x05)
        a.rel(0x20, "objColors")
        a.label("notColor")
        a.op(0x3E, 0x63)                // BGP: dark sky, white text
        a.op(0xE0, 0x47)
        a.op(0x3E, 0x90)                // OBP0: ship and flame
        a.op(0xE0, 0x48)
        a.op(0x3E, 0x18)                // OBP1: stars
        a.op(0xE0, 0x49)

        a.at(0x21, 0xC000)              // clear shadow OAM
        a.op(0x06, 160)
        a.op(0xAF)
        a.label("clearOAM")
        a.op(0x22)                      // LD (HL+),A
        a.op(0x05)
        a.rel(0x20, "clearOAM")
        a.at(0x21, 0xC014)              // stars from sprite 5
        a.abs(0x11, "starInit")
        a.at(0x01, starCount * 4)
        a.abs(0xCD, "copy")
        a.at(0x21, 0xFF80)              // OAM DMA routine into HRAM
        a.abs(0x11, "dmaRoutine")
        a.at(0x01, 8)
        a.abs(0xCD, "copy")

        a.op(0x3E, 32)
        a.at(0xEA, shipX)
        a.op(0x3E, 78)
        a.at(0xEA, shipY)
        a.op(0xAF)
        a.at(0xEA, frame)
        a.at(0xEA, pad)
        a.op(0xE0, 0x42)                // SCY
        a.op(0xE0, 0x43)                // SCX
        a.op(0x3E, 0x93)                // LCD on, tiles at $8000, sprites, background
        a.op(0xE0, 0x40)
        a.op(0x3E, 0x01)
        a.op(0xE0, 0xFF)                // IE: vertical blank
        a.op(0xAF)
        a.op(0xE0, 0x0F)                // IF
        a.op(0xFB)                      // EI

        a.label("main")
        a.op(0x76)                      // HALT until the next vertical blank
        a.abs(0xCD, "readPad")
        a.abs(0xCD, "moveShip")
        a.abs(0xCD, "moveStars")
        a.abs(0xCD, "drawShip")
        a.rel(0x18, "main")

        // HL = destination, DE = source, BC = count
        a.label("copy")
        a.op(0x1A)                      // LD A,(DE)
        a.op(0x22)                      // LD (HL+),A
        a.op(0x13)                      // INC DE
        a.op(0x0B)                      // DEC BC
        a.op(0x78)                      // LD A,B
        a.op(0xB1)                      // OR C
        a.rel(0x20, "copy")
        a.op(0xC9)                      // RET

        // 20×18 bytes from DE into the 32-wide map at HL
        a.label("copyMap")
        a.op(0x0E, 18)                  // LD C,18
        a.label("mapRow")
        a.op(0x06, 20)                  // LD B,20
        a.label("mapColumn")
        a.op(0x1A)
        a.op(0x22)
        a.op(0x13)
        a.op(0x05)
        a.rel(0x20, "mapColumn")
        a.op(0x7D)                      // LD A,L
        a.op(0xC6, 12)                  // ADD A,12
        a.op(0x6F)                      // LD L,A
        a.rel(0x30, "noCarry")          // JR NC
        a.op(0x24)                      // INC H
        a.label("noCarry")
        a.op(0x0D)                      // DEC C
        a.rel(0x20, "mapRow")
        a.op(0xC9)

        // pad: Down Up Left Right Start Select B A, bit 7 first.
        a.label("readPad")
        a.op(0x3E, 0x20)
        a.op(0xE0, 0x00)
        a.op(0xF0, 0x00, 0xF0, 0x00)
        a.op(0x2F)                      // CPL
        a.op(0xE6, 0x0F)
        a.op(0xCB, 0x37)                // SWAP A
        a.op(0x47)                      // LD B,A
        a.op(0x3E, 0x10)
        a.op(0xE0, 0x00)
        a.op(0xF0, 0x00, 0xF0, 0x00, 0xF0, 0x00, 0xF0, 0x00)
        a.op(0x2F)
        a.op(0xE6, 0x0F)
        a.op(0xB0)                      // OR B
        a.at(0xEA, pad)
        a.op(0x3E, 0x30)
        a.op(0xE0, 0x00)
        a.op(0xC9)

        a.label("moveShip")
        a.at(0xFA, pad)
        a.op(0x47)                      // LD B,A
        a.op(0xCB, 0x70)                // BIT 6,B (up)
        a.rel(0x28, "gbNotUp")          // JR Z
        a.at(0xFA, shipY)
        a.op(0xFE, 12)
        a.rel(0x38, "gbNotUp")          // JR C
        a.op(0xD6, 2)                   // SUB 2
        a.at(0xEA, shipY)
        a.label("gbNotUp")
        a.op(0xCB, 0x78)                // BIT 7,B (down)
        a.rel(0x28, "gbNotDown")
        a.at(0xFA, shipY)
        a.op(0xFE, 120)
        a.rel(0x30, "gbNotDown")        // JR NC
        a.op(0xC6, 2)
        a.at(0xEA, shipY)
        a.label("gbNotDown")
        a.op(0xCB, 0x68)                // BIT 5,B (left)
        a.rel(0x28, "gbNotLeft")
        a.at(0xFA, shipX)
        a.op(0xFE, 12)
        a.rel(0x38, "gbNotLeft")
        a.op(0xD6, 2)
        a.at(0xEA, shipX)
        a.label("gbNotLeft")
        a.op(0xCB, 0x60)                // BIT 4,B (right)
        a.rel(0x28, "gbNotRight")
        a.at(0xFA, shipX)
        a.op(0xFE, 140)
        a.rel(0x30, "gbNotRight")
        a.op(0xC6, 2)
        a.at(0xEA, shipX)
        a.label("gbNotRight")
        a.op(0xC9)

        a.label("moveStars")
        a.at(0x21, 0xC015)              // x of the first star
        a.abs(0x11, "starSpeed")
        a.op(0x0E, UInt8(starCount))
        a.label("gbStarLoop")
        a.op(0x1A)                      // LD A,(DE)
        a.op(0x13)                      // INC DE
        a.op(0x47)                      // LD B,A
        a.at(0xFA, pad)
        a.op(0xCB, 0x47)                // BIT 0,A (A button)
        a.rel(0x28, "gbNoWarp")
        a.op(0xCB, 0x20, 0xCB, 0x20)    // SLA B ×2
        a.label("gbNoWarp")
        a.op(0x7E)                      // LD A,(HL)
        a.op(0x90)                      // SUB B
        a.op(0x77)                      // LD (HL),A
        a.op(0x23, 0x23, 0x23, 0x23)    // INC HL ×4
        a.op(0x0D)
        a.rel(0x20, "gbStarLoop")
        a.op(0xC9)

        a.label("drawShip")
        a.at(0xFA, frame)
        a.op(0xCB, 0x3F, 0xCB, 0x3F, 0xCB, 0x3F)   // SRL A ×3
        a.op(0xE6, 0x0F)
        a.op(0x5F)                      // LD E,A
        a.op(0x16, 0x00)                // LD D,0
        a.abs(0x21, "bobTable")
        a.op(0x19)                      // ADD HL,DE
        a.at(0xFA, shipY)
        a.op(0x86)                      // ADD A,(HL)
        a.op(0xC6, 16)
        a.op(0x47)                      // LD B,A  (sprite y)
        a.at(0xFA, shipX)
        a.op(0xC6, 8)
        a.op(0x4F)                      // LD C,A  (sprite x)
        a.at(0x21, 0xC000)
        for (i, offset) in [(0, 0), (8, 0), (0, 8), (8, 8)].enumerated() {
            a.op(0x78)                  // LD A,B
            if offset.1 > 0 { a.op(0xC6, UInt8(offset.1)) }
            a.op(0x22)
            a.op(0x79)                  // LD A,C
            if offset.0 > 0 { a.op(0xC6, UInt8(offset.0)) }
            a.op(0x22)
            a.op(0x3E, UInt8(shipTiles + i))
            a.op(0x22)
            a.op(0xAF)
            a.op(0x22)
        }
        a.op(0x78)
        a.op(0xC6, 4)
        a.op(0x22)
        a.op(0x79)
        a.op(0xD6, 8)
        a.op(0x22)
        a.at(0xFA, frame)
        a.op(0xE6, 0x04)
        a.op(0x3E, UInt8(flameShort))   // LD A,n keeps the flags
        a.rel(0x28, "gbFlameChosen")
        a.op(0x3E, UInt8(flameLong))
        a.label("gbFlameChosen")
        a.op(0x57)                      // LD D,A
        a.at(0xFA, pad)
        a.op(0xCB, 0x47)
        a.rel(0x28, "gbFlameNoWarp")
        a.op(0x16, UInt8(flameLong))
        a.label("gbFlameNoWarp")
        a.op(0x7A)                      // LD A,D
        a.op(0x22)
        a.op(0x3E, 0x01)                // OBP0, colour palette 1
        a.op(0x22)
        a.op(0xC9)

        a.label("vblank")
        a.op(0xF5, 0xE5)                // PUSH AF, PUSH HL
        a.op(0x3E, 0xC0)
        a.at(0xCD, 0xFF80)              // OAM DMA from $C000
        a.at(0xFA, frame)
        a.op(0x3C)                      // INC A
        a.at(0xEA, frame)
        a.op(0xE6, 0x20)
        a.op(0x3E, 0xAA)                // BCPS: palette 5 colour 1, auto-increment
        a.op(0xE0, 0x68)
        a.abs(0x21, "blinkOn")
        a.rel(0x28, "blinkChosen")
        a.abs(0x21, "blinkOff")
        a.label("blinkChosen")
        a.op(0x2A)
        a.op(0xE0, 0x69)
        a.op(0x7E)
        a.op(0xE0, 0x69)
        a.op(0xE1, 0xF1)                // POP HL, POP AF
        a.op(0xD9)                      // RETI

        // Data
        a.label("dmaRoutine")
        a.data([0xE0, 0x46, 0x3E, 0x28, 0x3D, 0x20, 0xFD, 0xC9])
        a.label("bobTable")
        a.data(bob)
        let stars = spriteStars(count: starCount, top: 4, spacing: 7, width: 168, seed: 0x5EED_0002)
        a.label("starInit")
        for star in stars {
            a.data([UInt8(star.y + 16), UInt8(star.x), UInt8(spriteStar + star.layer), 0x92])
        }
        a.label("starSpeed")
        a.data(stars.map { UInt8($0.layer + 1) })
        a.label("blinkOn")
        a.data(rgb555(0xFFFFFF))
        a.label("blinkOff")
        a.data(rgb555(0x4A5480))
        a.label("backgroundColors")
        a.data(gbBackgroundColors())
        a.label("spriteColors")
        a.data(gbSpriteColors())
        let screen = gbScreen(color: color)
        a.label("map")
        a.data(screen.tiles)
        a.label("attributes")
        a.data(screen.palettes)
        a.label("tiles")
        var tiles = [UInt8](repeating: 0, count: 0x1000)
        eachTile { index, pixels in
            tiles.replaceSubrange((index * 16)..<(index * 16 + 16), with: TileArt.gameBoy(pixels))
        }
        a.data(tiles)

        let program = a.assembled()
        var rom = [UInt8](repeating: 0, count: 0x8000)
        precondition(0x150 + program.count <= rom.count, "Game Boy demo too large")
        rom.replaceSubrange(0x150..<(0x150 + program.count), with: program)
        let vblank = a.address(of: "vblank") ?? 0x150
        rom.replaceSubrange(0x40..<0x43, with: [0xC3, UInt8(vblank & 0xFF), UInt8(vblank >> 8)])
        rom.replaceSubrange(0x100..<0x104, with: [0x00, 0xC3, 0x50, 0x01])
        rom.replaceSubrange(0x104..<0x134, with: logo)
        let title = Array((color ? "COLOR FLIGHT" : "POCKET FLIGHT").utf8)
        rom.replaceSubrange(0x134..<(0x134 + title.count), with: title)
        rom[0x143] = color ? 0x80 : 0x00
        rom[0x147] = 0x00               // ROM only
        rom[0x148] = 0x00               // 32 KB
        rom[0x149] = 0x00               // no RAM
        rom[0x14A] = 0x01
        var check: UInt8 = 0
        for i in 0x134...0x14C { check = check &- rom[i] &- 1 }
        rom[0x14D] = check
        var global: UInt16 = 0
        for (i, byte) in rom.enumerated() where i != 0x14E && i != 0x14F { global = global &+ UInt16(byte) }
        rom[0x14E] = UInt8(global >> 8)
        rom[0x14F] = UInt8(global & 0xFF)
        return rom
    }

    static func gbScreen(color: Bool) -> Screen {
        var screen = Screen(columns: 20, rows: 18)
        screen.title("NOTCHER", font: DemoFont.narrow, width: 4, row: 1)
        for row in 1...4 { screen.palette(UInt8(row), rows: row...row) }
        screen.text(color ? "COLOR FLIGHT" : "POCKET FLIGHT", row: 6)
        screen.text("A NOTCHER DEMO", row: 8, dim: true)
        screen.text("ARROWS FLY", row: 12)
        screen.text("HOLD A TO WARP", row: 13)
        screen.palette(5, rows: 12...13)
        screen.text("ROMS IN YOUR NOTCH", row: 16, dim: true)
        screen.stars(26, seed: color ? 0xC0FF_EE02 : 0xC0FF_EE03, avoid: [1, 2, 3, 4, 6, 8, 12, 13, 16])
        return screen
    }

    /// Eight background palettes of four colours: sky, highlight, shadow, body.
    static func gbBackgroundColors() -> [UInt8] {
        let sky: UInt32 = 0x0B1026
        let palettes: [[UInt32]] = [
            [sky, 0xFFFFFF, 0x3A4470, 0x8E9AC8],
            [sky, 0xE8FFFF, 0x1E7FA0, 0x5EF0FF],
            [sky, 0xE6F0FF, 0x2C4FB8, 0x78A8FF],
            [sky, 0xF2E8FF, 0x5B2DB0, 0xB48CFF],
            [sky, 0xFFE8F6, 0xA8247F, 0xFF7AD9],
            [sky, 0xFFFFFF, 0x3A4470, 0x8E9AC8],
            [sky, 0xFFFFFF, 0x3A4470, 0x8E9AC8],
            [sky, 0xFFFFFF, 0x3A4470, 0x8E9AC8],
        ]
        return palettes.flatMap { $0.flatMap(rgb555) }
    }

    static func gbSpriteColors() -> [UInt8] {
        let ship: [UInt32] = [0x000000, 0xFFFFFF, 0x5EF0FF, 0xFF4D6D]
        let flame: [UInt32] = [0x000000, 0xFFF07A, 0xFFA53D, 0xFF4D3D]
        let stars: [UInt32] = [0x000000, 0x5A6490, 0xB8C4FF, 0xFFFFFF]
        let palettes: [[UInt32]] = [ship, flame, stars, ship, ship, ship, ship, ship]
        return palettes.flatMap { $0.flatMap(rgb555) }
    }

    /// 0xRRGGBB as a little-endian Game Boy Color colour.
    static func rgb555(_ rgb: UInt32) -> [UInt8] {
        let r = (rgb >> 19) & 0x1F
        let g = (rgb >> 11) & 0x1F
        let b = (rgb >> 3) & 0x1F
        let value = r | (g << 5) | (b << 10)
        return [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    /// The logo every Game Boy cartridge carries in its header.
    static let logo: [UInt8] = [
        0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
        0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
        0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
    ]
}

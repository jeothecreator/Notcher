import Foundation

/// Just enough of an assembler to write the demo cartridges: raw opcode
/// bytes plus labels. 6502 and SM83 are both little-endian and both use a
/// signed byte after the opcode for short branches, so one helper serves both.
struct DemoAssembler {
    enum Fixup {
        /// Signed 8-bit offset from the end of the instruction.
        case relative
        /// Little-endian 16-bit address.
        case absolute
        case lowByte
        case highByte
    }

    let origin: Int
    private(set) var bytes: [UInt8] = []
    private var labels: [String: Int] = [:]
    private var fixups: [(at: Int, label: String, kind: Fixup)] = []

    init(origin: Int) {
        self.origin = origin
    }

    var here: Int { origin + bytes.count }

    mutating func label(_ name: String) {
        precondition(labels[name] == nil, "label \(name) defined twice")
        labels[name] = here
    }

    func address(of name: String) -> Int? {
        labels[name]
    }

    /// Opcode and operand bytes as they are.
    mutating func op(_ values: UInt8...) {
        bytes.append(contentsOf: values)
    }

    mutating func data(_ values: [UInt8]) {
        bytes.append(contentsOf: values)
    }

    /// An opcode followed by a 16-bit address.
    mutating func at(_ opcode: UInt8, _ address: Int) {
        bytes.append(contentsOf: [opcode, UInt8(address & 0xFF), UInt8((address >> 8) & 0xFF)])
    }

    /// An opcode followed by a signed offset to `label`.
    mutating func rel(_ opcode: UInt8, _ label: String) {
        bytes.append(contentsOf: [opcode, 0])
        fixups.append((bytes.count - 1, label, .relative))
    }

    /// An opcode followed by the address of `label`.
    mutating func abs(_ opcode: UInt8, _ label: String) {
        bytes.append(contentsOf: [opcode, 0, 0])
        fixups.append((bytes.count - 2, label, .absolute))
    }

    /// An opcode followed by the low byte of `label`'s address.
    mutating func low(_ opcode: UInt8, _ label: String) {
        bytes.append(contentsOf: [opcode, 0])
        fixups.append((bytes.count - 1, label, .lowByte))
    }

    /// An opcode followed by the high byte of `label`'s address.
    mutating func high(_ opcode: UInt8, _ label: String) {
        bytes.append(contentsOf: [opcode, 0])
        fixups.append((bytes.count - 1, label, .highByte))
    }

    /// The program with every label filled in.
    func assembled() -> [UInt8] {
        var out = bytes
        for fix in fixups {
            guard let target = labels[fix.label] else {
                preconditionFailure("unknown label \(fix.label)")
            }
            switch fix.kind {
            case .relative:
                let offset = target - (origin + fix.at + 1)
                precondition((-128...127).contains(offset), "branch to \(fix.label) out of range")
                out[fix.at] = UInt8(bitPattern: Int8(offset))
            case .absolute:
                out[fix.at] = UInt8(target & 0xFF)
                out[fix.at + 1] = UInt8((target >> 8) & 0xFF)
            case .lowByte:
                out[fix.at] = UInt8(target & 0xFF)
            case .highByte:
                out[fix.at] = UInt8((target >> 8) & 0xFF)
            }
        }
        return out
    }
}

/// 8×8 pictures with four colours, and the two consoles' ways of storing them.
enum TileArt {
    /// Rows of "0123" (or "." for 0), padded to 8×8.
    static func parse(_ rows: [String]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        for y in 0..<8 {
            var row = [UInt8](repeating: 0, count: 8)
            if y < rows.count {
                for (x, ch) in rows[y].prefix(8).enumerated() {
                    row[x] = UInt8(ch.wholeNumberValue ?? 0)
                }
            }
            out.append(row)
        }
        return out
    }

    /// NES: eight bytes of the low bit plane, then eight of the high.
    static func nes(_ pixels: [[UInt8]]) -> [UInt8] {
        var low = [UInt8](repeating: 0, count: 8)
        var high = [UInt8](repeating: 0, count: 8)
        for y in 0..<8 {
            for x in 0..<8 {
                let c = pixels[y][x]
                let bit = UInt8(0x80 >> x)
                if c & 1 != 0 { low[y] |= bit }
                if c & 2 != 0 { high[y] |= bit }
            }
        }
        return low + high
    }

    /// Game Boy: each row as its low byte then its high byte.
    static func gameBoy(_ pixels: [[UInt8]]) -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<8 {
            var low: UInt8 = 0
            var high: UInt8 = 0
            for x in 0..<8 {
                let c = pixels[y][x]
                let bit = UInt8(0x80 >> x)
                if c & 1 != 0 { low |= bit }
                if c & 2 != 0 { high |= bit }
            }
            out.append(low)
            out.append(high)
        }
        return out
    }

    /// A 5×7 glyph in colour `color`, one pixel in from the left.
    static func glyph(_ rows: [UInt8], color: UInt8) -> [[UInt8]] {
        var pixels = [[UInt8]](repeating: [UInt8](repeating: 0, count: 8), count: 8)
        for (y, bits) in rows.prefix(7).enumerated() {
            for x in 0..<5 where bits & UInt8(0x10 >> x) != 0 {
                pixels[y][x + 1] = color
            }
        }
        return pixels
    }

    /// One of sixteen tiles made of 4×4 bricks: bit 0 top-left, 1 top-right,
    /// 2 bottom-left, 3 bottom-right. Bricks have a light top edge (colour 1),
    /// a body (3) and a shadow on the right and bottom (2).
    static func bricks(_ mask: Int) -> [[UInt8]] {
        var pixels = [[UInt8]](repeating: [UInt8](repeating: 0, count: 8), count: 8)
        for cell in 0..<4 where mask & (1 << cell) != 0 {
            let ox = (cell & 1) * 4
            let oy = (cell >> 1) * 4
            for y in 0..<4 {
                for x in 0..<4 {
                    let c: UInt8
                    if x == 3 || y == 3 {
                        c = 2
                    } else if y == 0 {
                        c = 1
                    } else {
                        c = 3
                    }
                    pixels[oy + y][ox + x] = c
                }
            }
        }
        return pixels
    }
}

/// A 5×7 font for the demo screens.
enum DemoFont {
    static let glyphs: [Character: [UInt8]] = [
        "A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        "B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        "C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
        "D": [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
        "E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
        "F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        "G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
        "H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        "I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "J": [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
        "K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        "L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        "M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
        "N": [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
        "O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        "P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        "Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
        "R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        "S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
        "T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        "U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        "V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        "W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
        "X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        "Y": [0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04],
        "Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        "0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
        "1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
        "3": [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
        "4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        "5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        "6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
        "7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        "8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        "9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        "-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
        ".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
        "!": [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
        ":": [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
        "/": [0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10],
        "(": [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02],
        ")": [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08],
        "'": [0x0C, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
    ]

    /// Narrow 4×7 capitals for the Game Boy title, which has 20 tiles of width.
    static let narrow: [Character: [UInt8]] = [
        "N": [0x9, 0xD, 0xD, 0xB, 0xB, 0x9, 0x9],
        "O": [0x6, 0x9, 0x9, 0x9, 0x9, 0x9, 0x6],
        "T": [0xF, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6],
        "C": [0x7, 0x8, 0x8, 0x8, 0x8, 0x8, 0x7],
        "H": [0x9, 0x9, 0x9, 0xF, 0x9, 0x9, 0x9],
        "E": [0xF, 0x8, 0x8, 0xE, 0x8, 0x8, 0xF],
        "R": [0xE, 0x9, 0x9, 0xE, 0xA, 0x9, 0x9],
    ]

    /// Tile number for a character: its ASCII code, plus 0x80 for the dim variant.
    static func tile(for ch: Character, dim: Bool) -> UInt8 {
        guard let ascii = ch.asciiValue, glyphs[ch] != nil else { return 0 }
        return dim ? ascii | 0x80 : ascii
    }
}

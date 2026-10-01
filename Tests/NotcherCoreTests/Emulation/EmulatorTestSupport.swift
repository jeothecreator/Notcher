import Foundation
import XCTest
@testable import NotcherCore

/// A tiny assembler for test programs: raw bytes plus label fix-ups.
struct Asm {
    enum Fixup { case relative, absolute16 }

    let origin: Int
    private(set) var bytes: [UInt8] = []
    private var labels: [String: Int] = [:]
    private var fixups: [(at: Int, label: String, kind: Fixup)] = []

    init(origin: Int) {
        self.origin = origin
    }

    var here: Int { origin + bytes.count }

    mutating func label(_ name: String) {
        labels[name] = here
    }

    mutating func emit(_ values: UInt8...) {
        bytes.append(contentsOf: values)
    }

    mutating func emit(_ values: [UInt8]) {
        bytes.append(contentsOf: values)
    }

    /// An opcode followed by a signed 8-bit offset to `label`.
    mutating func rel(_ opcode: UInt8, _ label: String) {
        emit(opcode, 0)
        fixups.append((bytes.count - 1, label, .relative))
    }

    /// An opcode followed by a little-endian address of `label`.
    mutating func abs(_ opcode: UInt8, _ label: String) {
        emit(opcode, 0, 0)
        fixups.append((bytes.count - 2, label, .absolute16))
    }

    func assembled() -> [UInt8] {
        var out = bytes
        for fix in fixups {
            guard let target = labels[fix.label] else {
                XCTFail("Unknown label \(fix.label)")
                continue
            }
            switch fix.kind {
            case .relative:
                let offset = target - (origin + fix.at + 1)
                precondition((-128...127).contains(offset), "branch to \(fix.label) out of range")
                out[fix.at] = UInt8(bitPattern: Int8(offset))
            case .absolute16:
                out[fix.at] = UInt8(target & 0xFF)
                out[fix.at + 1] = UInt8(target >> 8)
            }
        }
        return out
    }
}

enum TestROM {
    static let nintendoLogo: [UInt8] = [
        0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
        0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
        0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
    ]

    /// A 32 KB Game Boy ROM whose entry point jumps to `code` at 0x150.
    static func gameBoy(
        code: [UInt8], title: String = "TEST", type: UInt8 = 0x00, ramSize: UInt8 = 0,
        cgb: Bool = false, vectors: [Int: [UInt8]] = [:]
    ) -> [UInt8] {
        var rom = [UInt8](repeating: 0, count: 0x8000)
        rom.replaceSubrange(0x100..<0x104, with: [0x00, 0xC3, 0x50, 0x01])
        rom.replaceSubrange(0x104..<0x134, with: nintendoLogo)
        for (i, ch) in title.utf8.prefix(15).enumerated() { rom[0x134 + i] = ch }
        rom[0x143] = cgb ? 0x80 : 0x00
        rom[0x147] = type
        rom[0x148] = 0
        rom[0x149] = ramSize
        rom.replaceSubrange(0x150..<(0x150 + code.count), with: code)
        for (addr, bytes) in vectors {
            rom.replaceSubrange(addr..<(addr + bytes.count), with: bytes)
        }
        return rom
    }

    /// iNES image with PRG at $8000 (or mirrored $C000 for 16 KB) and the
    /// reset/NMI/IRQ vectors pointing into it.
    static func nes(
        prg code: [UInt8], at origin: Int = 0x8000, chr: [UInt8] = [], mapper: Int = 0,
        battery: Bool = false, vertical: Bool = true, nmi: Int? = nil, irq: Int? = nil
    ) -> [UInt8] {
        var prg = [UInt8](repeating: 0xEA, count: 0x8000)
        let offset = origin - 0x8000
        prg.replaceSubrange(offset..<(offset + code.count), with: code)
        let reset = origin
        let nmiAddr = nmi ?? origin
        let irqAddr = irq ?? origin
        prg[0x7FFA] = UInt8(nmiAddr & 0xFF); prg[0x7FFB] = UInt8(nmiAddr >> 8)
        prg[0x7FFC] = UInt8(reset & 0xFF); prg[0x7FFD] = UInt8(reset >> 8)
        prg[0x7FFE] = UInt8(irqAddr & 0xFF); prg[0x7FFF] = UInt8(irqAddr >> 8)
        var chrData = chr
        if !chrData.isEmpty && chrData.count < 0x2000 {
            chrData += [UInt8](repeating: 0, count: 0x2000 - chrData.count)
        }
        var header: [UInt8] = [0x4E, 0x45, 0x53, 0x1A, 2, UInt8(chrData.count / 0x2000)]
        header.append(UInt8((mapper & 0x0F) << 4) | (battery ? 0x02 : 0) | (vertical ? 0x01 : 0))
        header.append(UInt8(mapper & 0xF0))
        header += [UInt8](repeating: 0, count: 8)
        return header + prg + chrData
    }
}

/// Where CI drops downloaded conformance ROMs (see Scripts/fetch-test-roms.sh).
enum ExternalROMs {
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Emulation
            .deletingLastPathComponent() // NotcherCoreTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("External")
    }

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["NOTCHER_CONFORMANCE"] == "1"
    }

    static func load(_ relative: String) throws -> [UInt8] {
        let url = directory.appendingPathComponent(relative)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("\(relative) not downloaded; run Scripts/fetch-test-roms.sh")
        }
        return [UInt8](data)
    }
}

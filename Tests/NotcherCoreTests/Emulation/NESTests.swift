import XCTest
@testable import NotcherCore

final class NESTests: XCTestCase {
    func run(_ nes: NES, frames: Int) {
        for _ in 0..<frames { nes.runFrame() }
    }

    /// BIT $2002 ; BPL back — waits for VBlank.
    static func waitVBlank(_ asm: inout Asm, _ name: String) {
        asm.label(name)
        asm.emit(0x2C, 0x02, 0x20)
        asm.rel(0x10, name)
    }

    func testDetectionAndInfo() throws {
        let rom = TestROM.nes(prg: [0x4C, 0x00, 0x80], battery: true)
        XCTAssertEqual(ROMInfo.detect(rom), .nes)
        let info = try XCTUnwrap(ROMInfo.inspect(rom))
        XCTAssertEqual(info.board, "NROM")
        XCTAssertTrue(info.hasBattery)
        XCTAssertTrue(info.supported)
        XCTAssertTrue(try EmulatorFactory.make(rom: rom) is NES)

        let mmc5 = TestROM.nes(prg: [0x4C, 0x00, 0x80], mapper: 5)
        XCTAssertFalse(ROMInfo.inspect(mmc5)?.supported ?? true)
        XCTAssertThrowsError(try NES(rom: mmc5)) { error in
            XCTAssertEqual(error as? EmulatorError, .unsupportedMapper("MMC5"))
        }
        XCTAssertThrowsError(try NES(rom: Array(rom.prefix(100))))
    }

    func testArithmeticAndSubroutines() throws {
        var asm = Asm(origin: 0x8000)
        asm.emit(0xA9, 0x12, 0x18, 0x69, 0x34, 0x85, 0x00) // LDA #12 ; CLC ; ADC #34 ; STA 00
        asm.emit(0xA9, 0x50, 0x38, 0xE9, 0x70, 0x85, 0x01) // LDA #50 ; SEC ; SBC #70 ; STA 01
        asm.emit(0xA2, 0x05, 0xA9, 0x00)                   // LDX #5 ; LDA #0
        asm.label("loop")
        asm.emit(0x18, 0x69, 0x03, 0xCA)                   // CLC ; ADC #3 ; DEX
        asm.rel(0xD0, "loop")                              // BNE loop
        asm.emit(0x85, 0x03)                               // STA 03
        asm.abs(0x20, "sub")                               // JSR sub
        asm.emit(0x85, 0x04)                               // STA 04
        asm.emit(0xA9, 0x81, 0x0A, 0x85, 0x05)             // LDA #81 ; ASL A ; STA 05
        asm.emit(0xA9, 0x00, 0x2A, 0x85, 0x06)             // LDA #0 ; ROL A (carry in) ; STA 06
        asm.label("spin")
        asm.abs(0x4C, "spin")
        asm.label("sub")
        asm.emit(0xA9, 0x99, 0x60)                         // LDA #99 ; RTS
        let nes = try NES(rom: TestROM.nes(prg: asm.assembled()))
        run(nes, frames: 1)
        XCTAssertEqual(nes.ram[0], 0x46)
        XCTAssertEqual(nes.ram[1], 0xE0)
        XCTAssertEqual(nes.ram[3], 15)
        XCTAssertEqual(nes.ram[4], 0x99)
        XCTAssertEqual(nes.ram[5], 0x02)
        XCTAssertEqual(nes.ram[6], 0x01)
    }

    /// Tile 1 is solid color 1.
    static let chr: [UInt8] = {
        var chr = [UInt8](repeating: 0, count: 0x2000)
        for i in 0..<8 { chr[16 + i] = 0xFF }
        return chr
    }()

    static func backgroundProgram(nmiScroll: Bool = false) -> Asm {
        var asm = Asm(origin: 0x8000)
        asm.emit(0x78, 0xA2, 0xFF, 0x9A) // SEI ; LDX #FF ; TXS
        waitVBlank(&asm, "vb1")
        waitVBlank(&asm, "vb2")
        asm.emit(0xA9, 0x3F, 0x8D, 0x06, 0x20, 0xA9, 0x00, 0x8D, 0x06, 0x20) // PPUADDR 3F00
        asm.emit(0xA9, 0x0F, 0x8D, 0x07, 0x20, 0xA9, 0x30, 0x8D, 0x07, 0x20) // black, white
        asm.emit(0xA9, 0x20, 0x8D, 0x06, 0x20, 0xA9, 0x00, 0x8D, 0x06, 0x20) // PPUADDR 2000
        asm.emit(0xA2, 0x00)
        asm.label("fill")
        asm.emit(0x8A, 0x29, 0x01, 0x49, 0x01, 0x8D, 0x07, 0x20) // TXA ; AND #1 ; EOR #1 ; STA 2007
        asm.emit(0xE8, 0xE0, 0x20)                               // INX ; CPX #32
        asm.rel(0xD0, "fill")
        asm.emit(0xA9, 0x00, 0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20) // scroll 0,0
        asm.emit(0xA9, nmiScroll ? 0x80 : 0x00, 0x8D, 0x00, 0x20) // PPUCTRL
        asm.emit(0xA9, 0x0A, 0x8D, 0x01, 0x20)                    // show background
        asm.label("spin")
        asm.abs(0x4C, "spin")
        asm.label("nmi")
        asm.emit(0xE6, 0x20, 0xA5, 0x20, 0x8D, 0x05, 0x20)       // INC 20 ; LDA 20 ; STA 2005
        asm.emit(0xA9, 0x00, 0x8D, 0x05, 0x20, 0x40)             // LDA #0 ; STA 2005 ; RTI
        return asm
    }

    func testBackgroundRendering() throws {
        let asm = Self.backgroundProgram()
        let nes = try NES(rom: TestROM.nes(prg: asm.assembled(), chr: Self.chr))
        run(nes, frames: 4)
        let white = NESPPU.colors[0x30], black = NESPPU.colors[0x0F]
        let frame = nes.frameBuffer
        XCTAssertEqual(frame.count, 256 * 240)
        // Even map entries hold tile 1, odd ones tile 0.
        XCTAssertEqual(frame[0], white)
        XCTAssertEqual(frame[7 * 256 + 7], white)
        XCTAssertEqual(frame[8], black)
        XCTAssertEqual(frame[16], white)
        XCTAssertEqual(frame[8 * 256], black)
    }

    func testNMIScrollAndSaveStates() throws {
        let asm = Self.backgroundProgram(nmiScroll: true)
        let nmi = asm.here - 13
        let rom = TestROM.nes(prg: asm.assembled(), chr: Self.chr, nmi: nmi)
        let nes = try NES(rom: rom)
        run(nes, frames: 10)
        XCTAssertGreaterThan(nes.ram[0x20], 3)
        let state = nes.saveState()
        run(nes, frames: 20)
        let expected = nes.frameBuffer
        let counter = nes.ram[0x20]

        try nes.loadState(state)
        run(nes, frames: 20)
        XCTAssertEqual(nes.ram[0x20], counter)
        XCTAssertEqual(nes.frameBuffer, expected)

        let fresh = try NES(rom: rom)
        try fresh.loadState(state)
        run(fresh, frames: 20)
        XCTAssertEqual(fresh.frameBuffer, expected)
        XCTAssertThrowsError(try nes.loadState(Array(state.prefix(40))))
    }

    func testController() throws {
        var asm = Asm(origin: 0x8000)
        asm.label("loop")
        asm.emit(0xA9, 0x01, 0x8D, 0x16, 0x40, 0xA9, 0x00, 0x8D, 0x16, 0x40) // strobe
        asm.emit(0xA2, 0x08, 0xA9, 0x00, 0x85, 0x10)
        asm.label("bit")
        asm.emit(0xAD, 0x16, 0x40, 0x29, 0x01, 0x4A, 0x26, 0x10, 0xCA) // LDA 4016 ; AND #1 ; LSR ; ROL 10 ; DEX
        asm.rel(0xD0, "bit")
        asm.abs(0x4C, "loop")
        let nes = try NES(rom: TestROM.nes(prg: asm.assembled()))
        nes.buttons = [.a, .start, .right]
        run(nes, frames: 1)
        XCTAssertEqual(nes.ram[0x10], 0b1001_0001)
    }

    func testBatteryRAM() throws {
        let code: [UInt8] = [0xA9, 0x42, 0x8D, 0x00, 0x60, 0x4C, 0x05, 0x80]
        let nes = try NES(rom: TestROM.nes(prg: code, battery: true))
        run(nes, frames: 1)
        XCTAssertTrue(nes.batteryDirty)
        XCTAssertEqual(nes.batteryRAM?.count, 0x2000)
        XCTAssertEqual(nes.batteryRAM?[0], 0x42)
        nes.markBatterySaved()
        XCTAssertFalse(nes.batteryDirty)
        XCTAssertNil(try NES(rom: TestROM.nes(prg: code)).batteryRAM)
    }

    func testMMC1Banking() throws {
        // 128 KB PRG, bank n starts with byte n; code lives in the fixed last bank.
        var prg = [UInt8](repeating: 0xEA, count: 0x20000)
        for bank in 0..<8 { prg[bank * 0x4000] = UInt8(bank) }
        // Entry at C001: the first byte of every bank is its number.
        var asm = Asm(origin: 0xC001)
        asm.emit(0xA9, 0x03)
        for _ in 0..<4 { asm.emit(0x8D, 0x00, 0xE0, 0x4A) } // STA E000 ; LSR A
        asm.emit(0x8D, 0x00, 0xE0)
        asm.emit(0xAD, 0x00, 0x80, 0x85, 0x00)              // LDA 8000 ; STA 00
        asm.label("spin")
        asm.abs(0x4C, "spin")
        let code = asm.assembled()
        let last = 7 * 0x4000
        prg.replaceSubrange((last + 1)..<(last + 1 + code.count), with: code)
        prg[0x1FFFC] = 0x01
        prg[0x1FFFD] = 0xC0
        let header: [UInt8] = [0x4E, 0x45, 0x53, 0x1A, 8, 0, 0x10, 0x00, 0, 0, 0, 0, 0, 0, 0, 0]
        let nes = try NES(rom: header + prg)
        XCTAssertEqual(nes.cart.mapper, 1)
        run(nes, frames: 1)
        XCTAssertEqual(nes.ram[0], 3)
    }

    func testMMC3ScanlineIRQ() throws {
        var asm = Asm(origin: 0x8000)
        asm.emit(0x78, 0xA2, 0xFF, 0x9A)       // SEI ; set stack
        asm.emit(0xA9, 0x40, 0x8D, 0x17, 0x40) // no APU frame IRQ
        asm.emit(0xA9, 0x08, 0x8D, 0x01, 0x20) // render background
        asm.emit(0xA9, 0x10, 0x8D, 0x00, 0xC0) // IRQ latch 16
        asm.emit(0x8D, 0x01, 0xC0)             // reload
        asm.emit(0x8D, 0x01, 0xE0)             // enable
        asm.emit(0x58)                          // CLI
        asm.label("spin")
        asm.abs(0x4C, "spin")
        asm.label("irq")
        asm.emit(0xE6, 0x30, 0x8D, 0x00, 0xE0, 0x8D, 0x01, 0xE0, 0x40) // INC 30 ; ack ; re-enable ; RTI
        let irq = asm.here - 9
        let nes = try NES(rom: TestROM.nes(prg: asm.assembled(), mapper: 4, irq: irq))
        run(nes, frames: 2)
        XCTAssertGreaterThan(nes.ram[0x30], 10)
    }

    func testSoundProducesSamples() throws {
        let code: [UInt8] = [
            0xA9, 0x01, 0x8D, 0x15, 0x40, // enable pulse 1
            0xA9, 0xBF, 0x8D, 0x00, 0x40, // duty 50%, constant volume 15
            0xA9, 0xFD, 0x8D, 0x02, 0x40, // timer low
            0xA9, 0x00, 0x8D, 0x03, 0x40, // timer high + length
            0x4C, 0x14, 0x80,
        ]
        let nes = try NES(rom: TestROM.nes(prg: code))
        run(nes, frames: 3)
        let samples = nes.audio.drain()
        XCTAssertGreaterThan(samples.count, 1500)
        let energy = samples.suffix(700).map { Double($0 * $0) }.reduce(0, +)
        XCTAssertGreaterThan(energy, 1)
    }

    func testCycleCounts() throws {
        // LDA abs,X across a page costs 5; STA abs,X always 5; taken branch 3.
        let code: [UInt8] = [
            0xA2, 0x01,       // LDX #1         2
            0xBD, 0xFF, 0x00, // LDA $00FF,X    5 (page cross)
            0x9D, 0x00, 0x02, // STA $0200,X    5
            0x18,             // CLC            2
            0x90, 0x00,       // BCC +0         3
            0xEA,             // NOP            2
        ]
        let nes = try NES(rom: TestROM.nes(prg: code + [0x4C, 0x0C, 0x80]))
        let start = nes.cpu.cycles
        for _ in 0..<6 { nes.cpu.step() }
        XCTAssertEqual(nes.cpu.cycles - start, 2 + 5 + 5 + 2 + 3 + 2)
    }
}

/// nestest.nes in automation mode, compared line by line with its golden log,
/// plus Blargg's instruction tests (which also exercise MMC1).
final class NESConformanceTests: XCTestCase {
    func testBlarggOfficialInstructions() throws {
        guard ExternalROMs.enabled else { throw XCTSkip("Set NOTCHER_CONFORMANCE=1 to run conformance ROMs") }
        let nes = try NES(rom: try ExternalROMs.load("nes/official_only.nes"))
        let ram = nes.cart.prgRAM
        var status: UInt8 = 0xFF
        for frame in 0..<(60 * 180) {
            nes.runFrame()
            guard frame % 30 == 0, ram[1] == 0xDE, ram[2] == 0xB0, ram[3] == 0x61 else { continue }
            status = ram[0]
            if status < 0x80 { break }
        }
        var text = ""
        var i = 4
        while i < 0x2000 && ram[i] != 0 {
            text.append(Character(UnicodeScalar(ram[i])))
            i += 1
        }
        XCTAssertEqual(status, 0, text)
    }

    func testNestestMatchesGoldenLog() throws {
        guard ExternalROMs.enabled else { throw XCTSkip("Set NOTCHER_CONFORMANCE=1 to run conformance ROMs") }
        let rom = try ExternalROMs.load("nes/nestest.nes")
        let log = String(decoding: try ExternalROMs.load("nes/nestest.log"), as: UTF8.self)
        let nes = try NES(rom: rom)
        nes.cpu.pc = 0xC000
        nes.cpu.p = 0x24
        nes.cpu.s = 0xFD
        nes.cpu.cycles = 7

        var checked = 0
        for (number, raw) in log.split(separator: "\n").enumerated() {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            guard line.count > 20, let pc = UInt16(line.prefix(4), radix: 16),
                  let registers = line.range(of: "A:", options: .backwards) else { continue }
            var fields: [String: Int] = [:]
            for token in line[registers.lowerBound...].split(separator: " ") {
                let parts = token.split(separator: ":")
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                let radix = key == "CYC" ? 10 : 16
                if let value = Int(parts[1], radix: radix) { fields[key] = value }
            }
            let cpu = nes.cpu
            let actual = String(
                format: "%04X A:%02X X:%02X Y:%02X P:%02X SP:%02X CYC:%d",
                cpu.pc, cpu.a, cpu.x, cpu.y, cpu.p, cpu.s, cpu.cycles
            )
            let expected = String(
                format: "%04X A:%02X X:%02X Y:%02X P:%02X SP:%02X CYC:%d",
                pc, fields["A"] ?? -1, fields["X"] ?? -1, fields["Y"] ?? -1, fields["P"] ?? -1,
                fields["SP"] ?? -1, fields["CYC"] ?? -1
            )
            if actual != expected {
                XCTFail("nestest line \(number + 1):\nexpected \(expected)\nactual   \(actual)\n\(line)")
                return
            }
            checked += 1
            nes.cpu.step()
        }
        XCTAssertGreaterThan(checked, 8_000)
        // nestest reports failures in $02 and $03.
        XCTAssertEqual(nes.ram[2], 0)
        XCTAssertEqual(nes.ram[3], 0)
    }
}

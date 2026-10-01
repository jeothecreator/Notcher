import XCTest
@testable import NotcherCore

final class GameBoyTests: XCTestCase {
    /// LDH (01),A ; LD A,81 ; LDH (02),A — sends A over the link port.
    static let serialOut: [UInt8] = [0xE0, 0x01, 0x3E, 0x81, 0xE0, 0x02]
    static let spin: [UInt8] = [0x18, 0xFE]

    func run(_ gb: GameBoy, frames: Int) {
        for _ in 0..<frames { gb.runFrame() }
    }

    func testDetectionAndInfo() throws {
        let rom = TestROM.gameBoy(code: Self.spin, title: "NOTCHER", type: 0x03, ramSize: 2)
        XCTAssertEqual(ROMInfo.detect(rom), .gameBoy)
        let info = try XCTUnwrap(ROMInfo.inspect(rom))
        XCTAssertEqual(info.headerTitle, "NOTCHER")
        XCTAssertEqual(info.board, "MBC1")
        XCTAssertTrue(info.hasBattery)
        XCTAssertTrue(info.supported)
        XCTAssertEqual(info.checksum.count, 8)
        XCTAssertEqual(ROMInfo.detect(TestROM.gameBoy(code: Self.spin, cgb: true)), .gameBoyColor)
        XCTAssertNil(ROMInfo.detect([UInt8](repeating: 0, count: 0x8000)))
        XCTAssertTrue(try EmulatorFactory.make(rom: rom) is GameBoy)
    }

    func testUnsupportedCartridgeIsReported() {
        var rom = TestROM.gameBoy(code: Self.spin)
        rom[0x147] = 0x22 // MBC7
        XCTAssertThrowsError(try GameBoy(rom: rom)) { error in
            XCTAssertEqual(error as? EmulatorError, .unsupportedMapper("MBC7"))
        }
    }

    func testArithmeticAndSerial() throws {
        var code: [UInt8] = [0x3E, 0x12, 0xC6, 0x34] // LD A,12 ; ADD A,34
        code += Self.serialOut
        code += [0x3E, 0x45, 0xC6, 0x38, 0x27] // LD A,45 ; ADD A,38 ; DAA → 83
        code += Self.serialOut
        code += [0x3E, 0x83, 0xD6, 0x38, 0x27] // LD A,83 ; SUB 38 ; DAA → 45
        code += Self.serialOut
        code += [0x3E, 0x0F, 0xCB, 0x37] // LD A,0F ; SWAP A → F0
        code += Self.serialOut
        code += Self.spin
        let gb = try GameBoy(rom: TestROM.gameBoy(code: code))
        run(gb, frames: 1)
        XCTAssertEqual(gb.serialOutput, [0x46, 0x83, 0x45, 0xF0])
    }

    func testStackCallsAndBranches() throws {
        var asm = Asm(origin: 0x150)
        asm.emit(0x31, 0xFE, 0xDF)       // LD SP,DFFE
        asm.emit(0x01, 0x34, 0x12)       // LD BC,1234
        asm.emit(0xC5, 0xD1)             // PUSH BC ; POP DE
        asm.emit(0x7B)                   // LD A,E
        asm.emit(Self.serialOut)
        asm.emit(0x7A)                   // LD A,D
        asm.emit(Self.serialOut)
        asm.abs(0xCD, "sub")             // CALL sub
        asm.emit(Self.serialOut)
        asm.emit(0x06, 0x05, 0x3E, 0x00) // LD B,5 ; LD A,0
        asm.label("loop")
        asm.emit(0xC6, 0x03, 0x05)       // ADD A,3 ; DEC B
        asm.rel(0x20, "loop")            // JR NZ,loop
        asm.emit(Self.serialOut)
        asm.label("end")
        asm.rel(0x18, "end")
        asm.label("sub")
        asm.emit(0x3E, 0x99, 0xC9)       // LD A,99 ; RET
        let gb = try GameBoy(rom: TestROM.gameBoy(code: asm.assembled()))
        run(gb, frames: 1)
        XCTAssertEqual(gb.serialOutput, [0x34, 0x12, 0x99, 15])
    }

    func testTimerInterrupt() throws {
        var code: [UInt8] = [
            0x3E, 0x04, 0xE0, 0xFF, // IE = timer
            0x3E, 0xF0, 0xE0, 0x06, // TMA = F0
            0x3E, 0x05, 0xE0, 0x07, // TAC = enabled, 262 kHz
            0xFB,                   // EI
        ]
        code += [0x76, 0x00, 0x18, 0xFC] // HALT ; NOP ; JR -4
        let handler: [UInt8] = [0x3E, 0x55] + Self.serialOut + [0xD9] // ... RETI
        let gb = try GameBoy(rom: TestROM.gameBoy(code: code, vectors: [0x50: handler]))
        run(gb, frames: 1)
        XCTAssertGreaterThan(gb.serialOutput.count, 10)
        XCTAssertTrue(gb.serialOutput.allSatisfy { $0 == 0x55 })
    }

    /// Fills tile 1 with color 3 and puts it in the top-left map entry.
    static func drawTileProgram(cgbRed: Bool = false, sprite: Bool = false) -> [UInt8] {
        var asm = Asm(origin: 0x150)
        asm.emit(0x3E, 0x00, 0xE0, 0x40)       // LCD off
        asm.emit(0x21, 0x10, 0x80)             // LD HL,8010
        asm.emit(0x3E, 0xFF, 0x06, 0x10)       // LD A,FF ; LD B,16
        asm.label("fill")
        asm.emit(0x22, 0x05)                   // LD (HL+),A ; DEC B
        asm.rel(0x20, "fill")
        asm.emit(0x3E, 0x01, 0xEA, 0x00, 0x98) // map[0] = tile 1
        asm.emit(0x3E, 0xE4, 0xE0, 0x47)       // BGP = E4
        asm.emit(0x3E, 0xE4, 0xE0, 0x48)       // OBP0 = E4
        if cgbRed {
            asm.emit(0x3E, 0x86, 0xE0, 0x68)   // BCPS = auto-increment, palette 0 color 3
            asm.emit(0x3E, 0x1F, 0xE0, 0x69)   // red, low byte
            asm.emit(0x3E, 0x00, 0xE0, 0x69)   // high byte
        }
        if sprite {
            // OAM entry 0: screen (30, 20), tile 1.
            asm.emit(0x3E, 36, 0xEA, 0x00, 0xFE)
            asm.emit(0x3E, 38, 0xEA, 0x01, 0xFE)
            asm.emit(0x3E, 0x01, 0xEA, 0x02, 0xFE)
            asm.emit(0x3E, 0x00, 0xEA, 0x03, 0xFE)
        }
        asm.emit(0x3E, sprite ? 0x93 : 0x91, 0xE0, 0x40) // LCD on
        asm.label("spin")
        asm.rel(0x18, "spin")
        return asm.assembled()
    }

    func testBackgroundRendering() throws {
        let gb = try GameBoy(rom: TestROM.gameBoy(code: Self.drawTileProgram()))
        run(gb, frames: 3)
        let frame = gb.frameBuffer
        XCTAssertEqual(frame.count, 160 * 144)
        XCTAssertEqual(frame[0], GameBoy.greenPalette[3])
        XCTAssertEqual(frame[7 * 160 + 7], GameBoy.greenPalette[3])
        XCTAssertEqual(frame[8], GameBoy.greenPalette[0])
        XCTAssertEqual(frame[8 * 160], GameBoy.greenPalette[0])
    }

    func testSpriteRendering() throws {
        let gb = try GameBoy(rom: TestROM.gameBoy(code: Self.drawTileProgram(sprite: true)))
        run(gb, frames: 3)
        let frame = gb.frameBuffer
        XCTAssertEqual(frame[20 * 160 + 30], GameBoy.greenPalette[3])
        XCTAssertEqual(frame[27 * 160 + 37], GameBoy.greenPalette[3])
        XCTAssertEqual(frame[20 * 160 + 38], GameBoy.greenPalette[0])
        XCTAssertEqual(frame[19 * 160 + 30], GameBoy.greenPalette[0])
    }

    func testColorPalettes() throws {
        let gb = try GameBoy(rom: TestROM.gameBoy(code: Self.drawTileProgram(cgbRed: true), cgb: true))
        XCTAssertEqual(gb.system, .gameBoyColor)
        run(gb, frames: 3)
        let pixel = gb.frameBuffer[0]
        XCTAssertGreaterThan((pixel >> 16) & 0xFF, 180)
        XCTAssertLessThan((pixel >> 8) & 0xFF, 40)
        // Untouched palettes stay white.
        XCTAssertEqual(gb.frameBuffer[8] & 0xFF_FFFF, 0xFF_FFFF)
    }

    func testSoundProducesSamples() throws {
        var code: [UInt8] = [
            0x3E, 0x80, 0xE0, 0x26, // NR52 on
            0x3E, 0x77, 0xE0, 0x24, // NR50
            0x3E, 0xFF, 0xE0, 0x25, // NR51
            0x3E, 0x80, 0xE0, 0x11, // NR11 duty 50%
            0x3E, 0xF0, 0xE0, 0x12, // NR12 volume 15
            0x3E, 0x00, 0xE0, 0x13, // NR13
            0x3E, 0x87, 0xE0, 0x14, // NR14 trigger
        ]
        code += Self.spin
        let gb = try GameBoy(rom: TestROM.gameBoy(code: code))
        run(gb, frames: 2)
        let samples = gb.audio.drain()
        // The first frame is short: it starts at line 0 and stops at VBlank.
        XCTAssertGreaterThan(samples.count, 1300)
        XCTAssertLessThan(samples.count, 1550)
        let energy = samples.suffix(600).map { Double($0 * $0) }.reduce(0, +)
        XCTAssertGreaterThan(energy, 1)
    }

    func testBatteryRAM() throws {
        let code: [UInt8] = [
            0x3E, 0x0A, 0xEA, 0x00, 0x00, // enable RAM
            0x3E, 0x42, 0xEA, 0x00, 0xA0, // (A000) = 42
            0x18, 0xFE,
        ]
        let gb = try GameBoy(rom: TestROM.gameBoy(code: code, type: 0x03, ramSize: 2))
        XCTAssertFalse(gb.batteryDirty)
        run(gb, frames: 1)
        XCTAssertTrue(gb.batteryDirty)
        let saved = try XCTUnwrap(gb.batteryRAM)
        XCTAssertEqual(saved.count, 0x2000)
        XCTAssertEqual(saved[0], 0x42)
        gb.markBatterySaved()
        XCTAssertFalse(gb.batteryDirty)

        // A fresh console starts with the saved RAM.
        let other = try GameBoy(rom: TestROM.gameBoy(code: GameBoyTests.spin, type: 0x03, ramSize: 2))
        other.loadBatteryRAM(saved)
        XCTAssertEqual(other.batteryRAM?[0], 0x42)
    }

    func testMBC1Banking() throws {
        // 128 KB ROM; bank n starts with byte n.
        var rom = TestROM.gameBoy(code: [
            0x3E, 0x05, 0xEA, 0x00, 0x20, // select bank 5
            0xFA, 0x00, 0x40,             // LD A,(4000)
        ] + GameBoyTests.serialOut + GameBoyTests.spin, type: 0x01)
        rom += [UInt8](repeating: 0, count: 0x20000 - rom.count)
        rom[0x148] = 2
        for bank in 1..<8 { rom[bank * 0x4000] = UInt8(bank) }
        let gb = try GameBoy(rom: rom)
        run(gb, frames: 1)
        XCTAssertEqual(gb.serialOutput, [5])
    }

    /// Scrolls the background one pixel per frame.
    static let scrollProgram: [UInt8] = {
        var asm = Asm(origin: 0x150)
        asm.emit(Array(drawTileProgram().dropLast(2)))
        asm.label("frame")
        asm.emit(0xF0, 0x44, 0xFE, 0x90)  // LDH A,(44) ; CP 90
        asm.rel(0x20, "frame")
        asm.emit(0xF0, 0x43, 0x3C, 0xE0, 0x43) // SCX += 1
        asm.label("wait")
        asm.emit(0xF0, 0x44, 0xFE, 0x90)
        asm.rel(0x28, "wait")
        asm.rel(0x18, "frame")
        return asm.assembled()
    }()

    func testSaveStatesAreDeterministic() throws {
        let rom = TestROM.gameBoy(code: Self.scrollProgram, type: 0x03, ramSize: 2)
        let gb = try GameBoy(rom: rom)
        run(gb, frames: 10)
        let state = gb.saveState()
        run(gb, frames: 20)
        let expected = gb.frameBuffer
        let scroll = gb.ppu.scx
        XCTAssertGreaterThan(scroll, 20)

        try gb.loadState(state)
        run(gb, frames: 20)
        XCTAssertEqual(gb.frameBuffer, expected)
        XCTAssertEqual(gb.ppu.scx, scroll)

        // A state also restores into a brand new console.
        let fresh = try GameBoy(rom: rom)
        try fresh.loadState(state)
        run(fresh, frames: 20)
        XCTAssertEqual(fresh.frameBuffer, expected)

        XCTAssertThrowsError(try gb.loadState([1, 2, 3]))
        XCTAssertThrowsError(try gb.loadState(Array(state.prefix(state.count / 2))))
        // A failed load leaves the console running where it was.
        run(gb, frames: 1)
    }
}

/// Blargg's CPU test ROMs, downloaded in CI. Each prints "Passed" over serial.
final class GameBoyConformanceTests: XCTestCase {
    func runBlargg(_ path: String, maxFrames: Int = 60 * 60) throws {
        guard ExternalROMs.enabled else { throw XCTSkip("Set NOTCHER_CONFORMANCE=1 to run conformance ROMs") }
        let gb = try GameBoy(rom: try ExternalROMs.load(path))
        var text = ""
        for frame in 0..<maxFrames {
            gb.runFrame()
            if frame % 30 == 0 {
                text = String(decoding: gb.serialOutput, as: UTF8.self)
                if text.contains("Passed") || text.contains("Failed") { break }
            }
        }
        text = String(decoding: gb.serialOutput, as: UTF8.self)
        XCTAssertTrue(text.contains("Passed"), "\(path):\n\(text)")
    }

    func testCPUInstructions() throws {
        try runBlargg("gb/cpu_instrs.gb", maxFrames: 60 * 70)
    }

    func testInstructionTiming() throws {
        try runBlargg("gb/instr_timing.gb")
    }

    func testMemoryTiming() throws {
        try runBlargg("gb/mem_timing.gb")
    }
}

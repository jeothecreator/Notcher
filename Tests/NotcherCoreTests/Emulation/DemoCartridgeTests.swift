import XCTest
@testable import NotcherCore

final class DemoCartridgeTests: XCTestCase {
    func testDemosAreRecognisedAndImport() throws {
        XCTAssertEqual(ROMInfo.detect(DemoCartridges.nes()), .nes)
        XCTAssertEqual(ROMInfo.detect(DemoCartridges.gameBoy(color: true)), .gameBoyColor)
        XCTAssertEqual(ROMInfo.detect(DemoCartridges.gameBoy(color: false)), .gameBoy)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notcher-demos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = RomLibrary(folder: folder)
        let titles = try DemoCartridges.all.map { try library.importROM($0.data, fileName: $0.fileName).entry.title }
        XCTAssertEqual(titles, ["Night Flight", "Color Flight", "Pocket Flight"])
        XCTAssertEqual(Set(library.entries.map(\.system)), [.nes, .gameBoy, .gameBoyColor])
    }

    func testGameBoyHeaderChecksum() {
        for rom in [DemoCartridges.gameBoy(color: true), DemoCartridges.gameBoy(color: false)] {
            var check: UInt8 = 0
            for i in 0x134...0x14C { check = check &- rom[i] &- 1 }
            XCTAssertEqual(rom[0x14D], check)
            XCTAssertEqual(rom.count, 0x8000)
        }
    }

    func testNESDemoDrawsTitleAndFlies() throws {
        let nes = try NES(rom: DemoCartridges.nes())
        for _ in 0..<60 { nes.runFrame() }
        let colors = Set(nes.frameBuffer)
        XCTAssertTrue(colors.contains(NESPPU.colors[0x2C]), "cyan title")
        XCTAssertTrue(colors.contains(NESPPU.colors[0x25]), "pink title")
        XCTAssertTrue(colors.contains(NESPPU.colors[0x16]), "red ship trim")

        let start = try XCTUnwrap(Self.leftmost(NESPPU.colors[0x16], in: nes.frameBuffer, width: 256))
        nes.buttons = [.right]
        for _ in 0..<30 { nes.runFrame() }
        let moved = try XCTUnwrap(Self.leftmost(NESPPU.colors[0x16], in: nes.frameBuffer, width: 256))
        // Two pixels a frame; the flame alternates between a short and a long
        // sprite, which moves the leftmost red pixel by up to three.
        XCTAssertTrue((50...64).contains(moved - start), "ship moved \(moved - start) px")
    }

    func testGameBoyDemosDrawAndFly() throws {
        for color in [false, true] {
            let still = try GameBoy(rom: DemoCartridges.gameBoy(color: color))
            let flying = try GameBoy(rom: DemoCartridges.gameBoy(color: color))
            for _ in 0..<60 {
                still.runFrame()
                flying.runFrame()
            }
            XCTAssertEqual(still.frameBuffer, flying.frameBuffer, "deterministic")
            XCTAssertGreaterThanOrEqual(Set(still.frameBuffer).count, color ? 8 : 4)
            flying.buttons = [.right, .a]
            for _ in 0..<20 {
                still.runFrame()
                flying.runFrame()
            }
            XCTAssertNotEqual(still.frameBuffer, flying.frameBuffer)
        }
    }

    static func leftmost(_ color: UInt32, in frame: [UInt32], width: Int) -> Int? {
        var best: Int?
        for (i, pixel) in frame.enumerated() where pixel == color {
            let x = i % width
            if best == nil || x < best! { best = x }
        }
        return best
    }
}

/// Release-build speed, printed for the CI log (runs with the conformance step).
final class EmulationSpeedConformanceTests: XCTestCase {
    func testFramesPerSecond() throws {
        guard ExternalROMs.enabled else { throw XCTSkip("Set NOTCHER_CONFORMANCE=1 to measure speed") }
        let consoles: [(String, Emulator)] = [
            ("NES", try NES(rom: DemoCartridges.nes())),
            ("Game Boy Color", try GameBoy(rom: DemoCartridges.gameBoy(color: true))),
            ("Game Boy", try GameBoy(rom: DemoCartridges.gameBoy(color: false))),
        ]
        for (name, emulator) in consoles {
            let start = Date()
            for _ in 0..<600 { emulator.runFrame() }
            let elapsed = Date().timeIntervalSince(start)
            print(String(format: "speed: %@ %.2f ms/frame (%.0f fps)", name, elapsed * 1000 / 600, 600 / elapsed))
            XCTAssertLessThan(elapsed, 60)
        }
    }
}

import XCTest
@testable import NotcherCore

final class LibraryTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("notcher-library-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    /// A zip made with Python's zipfile (deflate, level 9): readme.txt and "Some Game (USA).gb".
    static let zipBase64 = "UEsDBBQAAAAIAA9rQV2GphA2BwAAAAUAAAAKAAAAcmVhZG1lLnR4dMtIzcnJBwBQSwMEFAAAAAgAD2tBXTWoU5vGAAAAAIAAABIAAABTb21lIEdhbWUgKFVTQSkuZ2Lt1jFKA2EUhdEnNoImYJfOfwU29jYa0CLJEKzshmgSQWZEp7G2MUtI5TpkStvBXsi0VroF0QW4gEDO6R583PpFbLi3bOv9ezptOrG7/RBPsRed2Nk/eF5Ed9UUn237sazr2aTofjXtavlSvx4dX55nWf/0/7neTwAAAMDaGY4uTs7643R1n89SnsajQSqLqkzV/DoVZTWZp7/j7jZ/TDfVYVKr1Wq1ejNrHwMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8AtQSwECFAMUAAAACAAPa0FdhqYQNgcAAAAFAAAACgAAAAAAAAAAAAAAgAEAAAAAcmVhZG1lLnR4dFBLAQIUAxQAAAAIAA9rQV01qFObxgAAAACAAAASAAAAAAAAAAAAAACAAS8AAABTb21lIEdhbWUgKFVTQSkuZ2JQSwUGAAAAAAIAAgB4AAAAJQEAAAAA"

    static var zippedROM: [UInt8] {
        var rom = TestROM.gameBoy(code: [0x18, 0xFE], title: "ZIPPED")
        let pattern = Array(String(repeating: "NOTCHER drag a ROM onto the notch to play it. ", count: 40).utf8)
        rom.replaceSubrange(0x1000..<(0x1000 + pattern.count), with: pattern)
        return rom
    }

    func testCleanTitles() {
        XCTAssertEqual(ROMInfo.cleanTitle(fileName: "Super_Mario_Land (World) [!].gb"), "Super Mario Land")
        XCTAssertEqual(ROMInfo.cleanTitle(fileName: "Tetris.gb"), "Tetris")
        XCTAssertEqual(ROMInfo.cleanTitle(fileName: "(Beta).nes", headerTitle: "POKEMON RED"), "Pokemon Red")
        XCTAssertEqual(ROMInfo.cleanTitle(fileName: "Dr. Mario (JU).nes"), "Dr. Mario")
    }

    func testCRC32() {
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum([]), 0)
    }

    func testZipExtraction() throws {
        let zip = [UInt8](try XCTUnwrap(Data(base64Encoded: Self.zipBase64)))
        XCTAssertTrue(ZipArchive.isZip(zip))
        let names = ZipArchive.entries(zip).map(\.name)
        XCTAssertEqual(names, ["readme.txt", "Some Game (USA).gb"])
        let rom = try XCTUnwrap(ZipArchive.firstROM(in: zip))
        XCTAssertEqual(rom.name, "Some Game (USA).gb")
        XCTAssertEqual(rom.data, Self.zippedROM)
        let readme = try XCTUnwrap(ZipArchive.entries(zip).first)
        XCTAssertEqual(ZipArchive.extract(readme, from: zip), Array("hello".utf8))
        XCTAssertNil(ZipArchive.firstROM(in: Array(zip.prefix(100))))
    }

    func testImportPersistAndRemove() throws {
        let library = RomLibrary(folder: folder)
        let rom = TestROM.gameBoy(code: [0x18, 0xFE], title: "LIB", type: 0x03, ramSize: 2)
        let added = try library.importROM(rom, fileName: "My_Game (Europe).gb")
        guard case .added(let entry) = added else { return XCTFail("expected a new entry") }
        XCTAssertEqual(entry.title, "My Game")
        XCTAssertEqual(entry.system, .gameBoy)
        XCTAssertTrue(entry.hasBattery)
        XCTAssertEqual(try library.romData(entry), rom)

        // The same ROM under another name is recognised.
        XCTAssertEqual(try library.importROM(rom, fileName: "copy.gb"), .existing(entry))
        XCTAssertEqual(library.entries.count, 1)

        library.writeBattery([1, 2, 3], for: entry)
        library.writeResumeState([9, 9], for: entry)
        library.writeQuickState([7], for: entry)
        library.writeThumbnail(Data([0x89, 0x50]), for: entry)
        library.notePlayed(entry.id, seconds: 42)
        library.rename(entry.id, to: "  Renamed  ")

        let reopened = RomLibrary(folder: folder)
        let restored = try XCTUnwrap(reopened.entry(entry.id))
        XCTAssertEqual(restored.title, "Renamed")
        XCTAssertEqual(restored.playSeconds, 42)
        XCTAssertNotNil(restored.lastPlayedAt)
        XCTAssertEqual(reopened.battery(restored), [1, 2, 3])
        XCTAssertEqual(reopened.resumeState(restored), [9, 9])
        XCTAssertTrue(reopened.hasResumeState(restored))
        XCTAssertEqual(reopened.quickState(restored), [7])
        XCTAssertNotNil(reopened.quickStateDate(restored))
        XCTAssertEqual(reopened.thumbnail(restored), Data([0x89, 0x50]))
        XCTAssertEqual(reopened.recentlyPlayed.map(\.id), [entry.id])

        reopened.remove(entry.id)
        XCTAssertTrue(reopened.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.romURL(entry).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.quickStateURL(entry).path))
        XCTAssertNil(reopened.thumbnail(entry))
        XCTAssertTrue(RomLibrary(folder: folder).entries.isEmpty)
    }

    func testImportFromZipAndErrors() throws {
        let library = RomLibrary(folder: folder)
        let zip = [UInt8](try XCTUnwrap(Data(base64Encoded: Self.zipBase64)))
        let entry = try library.importROM(zip, fileName: "download.zip").entry
        XCTAssertEqual(entry.title, "Some Game")
        XCTAssertEqual(entry.originalName, "Some Game (USA).gb")

        XCTAssertThrowsError(try library.importROM(Array("hello".utf8), fileName: "notes.txt")) { error in
            XCTAssertEqual(error as? LibraryError, .notAROM("notes"))
        }
        var mbc7 = TestROM.gameBoy(code: [0x18, 0xFE])
        mbc7[0x147] = 0x22
        XCTAssertThrowsError(try library.importROM(mbc7, fileName: "Tilt.gb")) { error in
            XCTAssertEqual(error as? LibraryError, .unsupported("Tilt", board: "MBC7"))
        }
        let nesROM = TestROM.nes(prg: [0x4C, 0x00, 0x80])
        let nes = try library.importROM(nesROM, fileName: "Homebrew.nes").entry
        XCTAssertEqual(nes.system, .nes)
        XCTAssertTrue(library.romURL(nes).lastPathComponent.hasSuffix(".nes"))
        XCTAssertEqual(library.entries.count, 2)
    }
}

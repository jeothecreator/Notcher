import Foundation

/// What Notcher can tell about a ROM file before running it.
public struct ROMInfo: Equatable, Sendable {
    public let system: ConsoleSystem
    /// Title stored in the cartridge header (Game Boy only).
    public let headerTitle: String?
    /// CRC-32 of the whole file, as eight hex digits. Identifies a ROM in the library.
    public let checksum: String
    public let size: Int
    public let hasBattery: Bool
    /// Cartridge hardware, e.g. "MMC3" or "MBC5".
    public let board: String
    public let supported: Bool

    static let nesMagic: [UInt8] = [0x4E, 0x45, 0x53, 0x1A]
    static let gbLogoStart: [UInt8] = [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B]

    /// The console a ROM image belongs to, judged by its header.
    public static func detect(_ rom: [UInt8], fileExtension: String? = nil) -> ConsoleSystem? {
        if rom.count >= 16, Array(rom[0..<4]) == nesMagic {
            return .nes
        }
        let ext = fileExtension?.lowercased()
        if rom.count >= 0x150 {
            let hasLogo = Array(rom[0x104..<0x10C]) == gbLogoStart
            if hasLogo || ext == "gb" || ext == "gbc" || ext == "cgb" || ext == "sgb" {
                let flag = rom[0x143]
                return flag == 0x80 || flag == 0xC0 ? .gameBoyColor : .gameBoy
            }
        }
        return nil
    }

    public static func inspect(_ rom: [UInt8], fileExtension: String? = nil) -> ROMInfo? {
        guard let system = detect(rom, fileExtension: fileExtension) else { return nil }
        let checksum = String(format: "%08X", CRC32.checksum(rom))
        switch system {
        case .nes:
            let flags6 = rom[6], flags7 = rom[7]
            let mapper = Int(flags6 >> 4) | Int(flags7 & 0xF0)
            return ROMInfo(
                system: .nes, headerTitle: nil, checksum: checksum, size: rom.count,
                hasBattery: flags6 & 0x02 != 0, board: NESCartridge.boardName(mapper),
                supported: NESCartridge.supportedMappers.contains(mapper)
            )
        case .gameBoy, .gameBoyColor:
            let titleBytes = rom[0x134..<0x144].prefix { $0 != 0 && $0 < 0x80 }
            let title = String(decoding: titleBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let type = rom[0x147]
            return ROMInfo(
                system: system, headerTitle: title.isEmpty ? nil : title, checksum: checksum, size: rom.count,
                hasBattery: GBCartridge.batteryTypes.contains(type), board: GBCartridge.boardName(type),
                supported: GBCartridge.supportedTypes.contains(type)
            )
        }
    }

    /// "Super_Mario_Land (World) [!].gb" → "Super Mario Land".
    public static func cleanTitle(fileName: String, headerTitle: String? = nil) -> String {
        var name = fileName
        if let dot = name.lastIndex(of: "."), name.distance(from: dot, to: name.endIndex) <= 5 {
            name = String(name[..<dot])
        }
        var result = ""
        var depth = 0
        for ch in name {
            switch ch {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth = max(0, depth - 1)
            default:
                if depth == 0 { result.append(ch == "_" ? " " : ch) }
            }
        }
        let collapsed = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !collapsed.isEmpty { return collapsed }
        if let header = headerTitle, !header.isEmpty { return header.capitalized }
        return "Untitled"
    }
}

/// CRC-32 (IEEE 802.3), as used by zip and every ROM database.
public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        table.withUnsafeBufferPointer { t in
            for b in bytes { crc = t[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

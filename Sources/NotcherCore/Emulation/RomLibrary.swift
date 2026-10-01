import Foundation

/// A game in the user's library.
public struct RomEntry: Codable, Identifiable, Equatable, Sendable {
    /// CRC-32 of the ROM image.
    public let id: String
    public var title: String
    public let system: ConsoleSystem
    /// File name inside the library's ROM folder.
    public let fileName: String
    /// What the file was called when it was added.
    public let originalName: String
    public let size: Int
    public let hasBattery: Bool
    public let board: String
    public var addedAt: Date
    public var lastPlayedAt: Date?
    public var playSeconds: Double

    public init(
        id: String, title: String, system: ConsoleSystem, fileName: String, originalName: String,
        size: Int, hasBattery: Bool, board: String, addedAt: Date = Date(),
        lastPlayedAt: Date? = nil, playSeconds: Double = 0
    ) {
        self.id = id
        self.title = title
        self.system = system
        self.fileName = fileName
        self.originalName = originalName
        self.size = size
        self.hasBattery = hasBattery
        self.board = board
        self.addedAt = addedAt
        self.lastPlayedAt = lastPlayedAt
        self.playSeconds = playSeconds
    }
}

public enum LibraryError: Error, Equatable, CustomStringConvertible {
    case unreadable
    case notAROM(String)
    case unsupported(String, board: String)
    case emptyArchive

    public var description: String {
        switch self {
        case .unreadable: return "Couldn't read that file."
        case .notAROM(let name): return "\(name) isn't a NES or Game Boy ROM."
        case .unsupported(let name, let board): return "\(name) uses \(board), which Notcher doesn't support yet."
        case .emptyArchive: return "There's no NES or Game Boy ROM in that archive."
        }
    }
}

/// The user's ROMs and everything that goes with them, kept in one folder:
///
///     Library/
///       library.json
///       ROMs/<id>.nes|.gb|.gbc
///       Saves/<id>.sav        battery-backed cartridge RAM
///       States/<id>.state     where you left off
///       Shots/<id>.png        last frame, for the launcher
public final class RomLibrary {
    public enum ImportResult: Equatable {
        case added(RomEntry)
        case existing(RomEntry)

        public var entry: RomEntry {
            switch self {
            case .added(let e), .existing(let e): return e
            }
        }
    }

    public let folder: URL
    public private(set) var entries: [RomEntry] = []
    private let fileManager = FileManager.default

    public init(folder: URL) {
        self.folder = folder
        for sub in ["ROMs", "Saves", "States", "Shots"] {
            try? fileManager.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        if let data = fileManager.contents(atPath: indexURL.path),
           let decoded = try? Self.decoder.decode([RomEntry].self, from: data) {
            // Drop entries whose ROM file went missing.
            entries = decoded.filter { fileManager.fileExists(atPath: romURL($0).path) }
        }
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    var indexURL: URL { folder.appendingPathComponent("library.json") }

    public func romURL(_ entry: RomEntry) -> URL {
        folder.appendingPathComponent("ROMs").appendingPathComponent(entry.fileName)
    }

    public func saveURL(_ entry: RomEntry) -> URL {
        folder.appendingPathComponent("Saves").appendingPathComponent("\(entry.id).sav")
    }

    public func stateURL(_ entry: RomEntry) -> URL {
        folder.appendingPathComponent("States").appendingPathComponent("\(entry.id).state")
    }

    public func thumbnailURL(_ entry: RomEntry) -> URL {
        folder.appendingPathComponent("Shots").appendingPathComponent("\(entry.id).png")
    }

    public func entry(_ id: String) -> RomEntry? {
        entries.first { $0.id == id }
    }

    /// Most recently played first, then newest additions.
    public var sorted: [RomEntry] {
        entries.sorted { a, b in
            switch (a.lastPlayedAt, b.lastPlayedAt) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.addedAt > b.addedAt
            }
        }
    }

    public var recentlyPlayed: [RomEntry] {
        sorted.filter { $0.lastPlayedAt != nil }
    }

    // MARK: Import

    /// Accepts a ROM file, or a zip containing one.
    @discardableResult
    public func importFile(at url: URL) throws -> ImportResult {
        guard let data = fileManager.contents(atPath: url.path) else { throw LibraryError.unreadable }
        return try importROM([UInt8](data), fileName: url.lastPathComponent)
    }

    @discardableResult
    public func importROM(_ bytes: [UInt8], fileName: String, now: Date = Date()) throws -> ImportResult {
        var image = bytes
        var name = fileName
        if ZipArchive.isZip(bytes) {
            guard let inner = ZipArchive.firstROM(in: bytes) else { throw LibraryError.emptyArchive }
            image = inner.data
            name = inner.name
        }
        let ext = (name as NSString).pathExtension.lowercased()
        guard let info = ROMInfo.inspect(image, fileExtension: ext) else {
            throw LibraryError.notAROM(ROMInfo.cleanTitle(fileName: name))
        }
        let title = ROMInfo.cleanTitle(fileName: name, headerTitle: info.headerTitle)
        guard info.supported else { throw LibraryError.unsupported(title, board: info.board) }
        if let existing = entry(info.checksum) {
            return .existing(existing)
        }
        let fileExt = info.system == .nes ? "nes" : (info.system == .gameBoyColor ? "gbc" : "gb")
        let entry = RomEntry(
            id: info.checksum, title: title, system: info.system,
            fileName: "\(info.checksum).\(fileExt)", originalName: name, size: image.count,
            hasBattery: info.hasBattery, board: info.board, addedAt: now
        )
        try Data(image).write(to: romURL(entry), options: .atomic)
        entries.append(entry)
        persist()
        return .added(entry)
    }

    public func remove(_ id: String) {
        guard let entry = entry(id) else { return }
        for url in [romURL(entry), saveURL(entry), stateURL(entry), thumbnailURL(entry)] {
            try? fileManager.removeItem(at: url)
        }
        entries.removeAll { $0.id == id }
        persist()
    }

    public func rename(_ id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].title = String(trimmed.prefix(60))
        persist()
    }

    public func notePlayed(_ id: String, seconds: Double, at date: Date = Date()) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].lastPlayedAt = date
        entries[i].playSeconds += max(0, seconds)
        persist()
    }

    // MARK: Files

    public func romData(_ entry: RomEntry) throws -> [UInt8] {
        guard let data = fileManager.contents(atPath: romURL(entry).path) else { throw LibraryError.unreadable }
        return [UInt8](data)
    }

    public func battery(_ entry: RomEntry) -> [UInt8]? {
        fileManager.contents(atPath: saveURL(entry).path).map { [UInt8]($0) }
    }

    public func writeBattery(_ data: [UInt8], for entry: RomEntry) {
        try? Data(data).write(to: saveURL(entry), options: .atomic)
    }

    public func resumeState(_ entry: RomEntry) -> [UInt8]? {
        fileManager.contents(atPath: stateURL(entry).path).map { [UInt8]($0) }
    }

    public func hasResumeState(_ entry: RomEntry) -> Bool {
        fileManager.fileExists(atPath: stateURL(entry).path)
    }

    public func writeResumeState(_ data: [UInt8], for entry: RomEntry) {
        try? Data(data).write(to: stateURL(entry), options: .atomic)
    }

    public func deleteResumeState(_ entry: RomEntry) {
        try? fileManager.removeItem(at: stateURL(entry))
    }

    public func persist() {
        guard let data = try? Self.encoder.encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

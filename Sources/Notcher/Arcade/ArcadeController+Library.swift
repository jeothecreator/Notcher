import AppKit
import NotcherCore
import SwiftUI

/// The ROM side of the arcade: the library, playing ROMs, and dragging
/// files onto the notch.
extension ArcadeController {
    static let errorColors = [Color(hex: 0xFF8A80), Color(hex: 0xE5484D)]

    // MARK: - Library

    func reloadLibrary() {
        roms = library.sorted
        if roms.count > save.stats.maximum("rom.library") {
            save.stats.apply(.maximum("rom.library", roms.count))
        }
        resumable = Set(roms.filter { library.hasResumeState($0) }.map(\.id))
        var fresh: [String: CGImage] = [:]
        for entry in roms {
            if let cached = thumbnails[entry.id] {
                fresh[entry.id] = cached
            } else if let data = library.thumbnail(entry), let image = FrameImage.load(data) {
                fresh[entry.id] = image
            }
        }
        thumbnails = fresh
    }

    private func refreshThumbnail(_ entry: RomEntry) {
        if let data = library.thumbnail(entry), let image = FrameImage.load(data) {
            thumbnails[entry.id] = image
        }
    }

    /// The ROM to offer on the For You page: the one played most recently.
    var continueROM: RomEntry? {
        roms.first { $0.lastPlayedAt != nil }
    }

    func romStatus(_ entry: RomEntry) -> String {
        if entry.playSeconds >= 60 { return Format.playTime(seconds: entry.playSeconds) + " played" }
        if entry.lastPlayedAt != nil { return "Just started" }
        return "Not played yet"
    }

    // MARK: - Playing

    func playROM(_ id: String) {
        guard let entry = library.entry(id) else { return }
        cancelOpen()
        cancelClose()
        cancelCharge()
        disarmQuit()
        let session: ConsoleSession
        if let existing = consoleSession, existing.entry.id == id {
            session = existing
        } else {
            if consoleSession != nil {
                suspendConsole()
                consoleSession = nil
            }
            do {
                session = try ConsoleSession(entry: entry, library: library, resume: Prefs.resumeROMs)
            } catch {
                let reason = (error as? CustomStringConvertible)?.description ?? "The ROM couldn't be read."
                showToast(Toast(symbol: "exclamationmark.triangle.fill", title: reason, subtitle: "Couldn't start \(entry.title)", colors: Self.errorColors))
                return
            }
            // Picking up an old game waits for a button, like a paused one.
            if session.resumed { session.pause() }
            consoleSession = session
            save.stats.apply(.count("rom.launches", 1))
            save.stats.apply(.count("rom.system.\(entry.system.rawValue)", 1))
            checkAchievements()
            persist()
        }
        ConsoleAudio.shared.setVolume(Prefs.volume, muted: !Prefs.soundEnabled)
        ConsoleAudio.shared.start()
        setMode(.console(id))
        requestFocus()
        SoundEngine.shared.play(.launch)
        if Prefs.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    /// Saves everything about the running ROM and silences it.
    func suspendConsole() {
        guard let session = consoleSession else { return }
        session.pause()
        let seconds = session.suspend()
        ConsoleAudio.shared.stop()
        library.notePlayed(session.entry.id, seconds: seconds)
        save.stats.playSeconds += seconds
        save.stats.apply(.count("rom.seconds", Int(seconds.rounded())))
        refreshThumbnail(session.entry)
        reloadLibrary()
        checkAchievements()
        persist()
    }

    // MARK: - Managing

    /// Adds ROM files (or zips). One file plays right away; several land in the library.
    func importFiles(_ urls: [URL], play: Bool = true) {
        var added: [RomEntry] = []
        var newCount = 0
        var failure: (title: String, subtitle: String)?
        for url in urls {
            // Files from drops, Finder and the open panel arrive with
            // sandbox access attached; hold it while the file is copied in.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try library.importFile(at: url)
                added.append(result.entry)
                if case .added = result { newCount += 1 }
            } catch let error as LibraryError {
                failure = Self.describe(error)
            } catch {
                failure = ("Couldn't read \(url.lastPathComponent)", "Import failed")
            }
        }
        reloadLibrary()
        dropTargeted = false
        dragNames = []
        guard let first = added.first else {
            let message = failure ?? ("That isn't a ROM", "Nothing added")
            showToast(Toast(symbol: "exclamationmark.triangle.fill", title: message.title, subtitle: message.subtitle, colors: Self.errorColors))
            if mode == .drop { setMode(.closed) }
            return
        }
        if added.count == 1 && play {
            playROM(first.id)
            return
        }
        if mode != .launcher { open(focus: false) }
        show(.library)
        let colors = first.system.colors
        showToast(Toast(
            symbol: "square.stack.3d.up.fill",
            title: newCount == 1 ? "Added 1 game" : "Added \(newCount) games",
            subtitle: "Library", colors: colors
        ))
    }

    /// Adds the three homebrew demo cartridges that ship with Notcher.
    func installDemos() {
        var added = 0
        for cartridge in DemoCartridges.all {
            if case .added? = try? library.importROM(cartridge.data, fileName: cartridge.fileName) {
                added += 1
            }
        }
        reloadLibrary()
        showToast(Toast(
            symbol: "sparkles", title: added > 0 ? "Demo games added" : "Demo games are already here",
            subtitle: "Night Flight · Color Flight · Pocket Flight", colors: LauncherPage.library.colors
        ))
    }

    static func describe(_ error: LibraryError) -> (title: String, subtitle: String) {
        switch error {
        case .unreadable: return ("Couldn't read that file", "Import failed")
        case .notAROM(let name): return ("\(name) isn't a ROM", "Notcher plays NES and Game Boy games")
        case .unsupported(let name, let board): return ("\(board) cartridges aren't supported yet", name)
        case .emptyArchive: return ("No ROM inside that zip", "Import failed")
        }
    }

    func removeROM(_ id: String) {
        if consoleSession?.entry.id == id {
            if case .console = mode { close() }
            consoleSession = nil
        }
        library.remove(id)
        reloadLibrary()
    }

    /// Forgets the saved spot so the next launch starts from power-on.
    func restartROM(_ id: String) {
        guard let entry = library.entry(id) else { return }
        if consoleSession?.entry.id == id { consoleSession = nil }
        library.deleteResumeState(entry)
        reloadLibrary()
        playROM(id)
    }

    func revealROM(_ id: String) {
        guard let entry = library.entry(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([library.romURL(entry)])
    }

    func revealLibrary() {
        NSWorkspace.shared.open(library.folder)
    }

    // MARK: - Drag and drop

    static func looksLikeROM(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ConsoleSystem.allExtensions.contains(ext) || ext == "zip"
    }

    /// A file drag is in progress; `point` is in panel coordinates. `names`
    /// is empty when the dragged files can't be read yet.
    func fileDragMoved(to point: CGPoint, names: [String]) {
        switch mode {
        case .game, .console:
            return
        case .drop:
            dropEndTask?.cancel()
            dropEndTask = nil
            // Fold away again when the pointer wanders off.
            if !shapeRect.insetBy(dx: -160, dy: -150).contains(point) { endDrop() }
        case .closed, .launcher, .trophies:
            guard names.isEmpty || names.contains(where: Self.looksLikeROM) else { return }
            let reach: CGFloat = mode == .closed ? 150 : shapeRect.height + 40
            let attract = CGRect(x: shapeRect.midX - 330, y: -40, width: 660, height: reach + 40)
            guard attract.contains(point) else { return }
            modeBeforeDrop = mode
            cancelOpen()
            cancelClose()
            cancelCharge()
            dragNames = names
            setMode(.drop)
        }
    }

    /// The mouse button came up. A drop on the notch may still be on its way.
    func fileDragEnded() {
        guard mode == .drop else { return }
        dropEndTask?.cancel()
        dropEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled, self.mode == .drop else { return }
            self.endDrop()
        }
    }

    func endDrop() {
        dropEndTask?.cancel()
        dropEndTask = nil
        dropTargeted = false
        dragNames = []
        let back = modeBeforeDrop
        modeBeforeDrop = .closed
        setMode(back == .launcher || back == .trophies ? back : .closed)
    }

    func dropTargetChanged(_ targeted: Bool) {
        if targeted {
            dropEndTask?.cancel()
            dropEndTask = nil
        }
        guard targeted != dropTargeted else { return }
        withAnimation(Theme.snappy) { dropTargeted = targeted }
        if targeted { SoundEngine.shared.play(.tick) }
    }

    func handleDrop(_ urls: [URL]) {
        dropEndTask?.cancel()
        dropEndTask = nil
        modeBeforeDrop = .closed
        importFiles(urls)
    }

    // MARK: - Preview rendering

    /// Shows a ROM after running scripted input, without audio, focus or timers.
    func previewConsole(_ id: String, script: [(frames: Int, buttons: ConsoleButtons)], held: ConsoleButtons = [], paused: Bool = false) {
        guard let entry = library.entry(id),
              let session = try? ConsoleSession(entry: entry, library: library, resume: false) else { return }
        session.gamepad = { [] }
        session.previewRun(script)
        session.previewHold(held)
        if paused { session.pause() }
        consoleSession = session
        previewState(mode: .console(id))
    }

    /// Stops the previewed ROM as Esc would, crediting `seconds` of play.
    func previewFinishConsole(seconds: Double) {
        guard let session = consoleSession else { return }
        let id = session.entry.id
        suspendConsole()
        consoleSession = nil
        library.notePlayed(id, seconds: seconds)
        reloadLibrary()
    }

    /// True when a drop on the notch right now would be accepted.
    var acceptsDrops: Bool {
        switch mode {
        case .drop, .launcher, .trophies: return true
        default: return false
        }
    }
}

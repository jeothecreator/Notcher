import Foundation
import NotcherCore

/// Persists `ArcadeSave` as JSON in Application Support, debounced.
@MainActor
final class SaveStore {
    let url: URL
    private var pending: Task<Void, Never>?

    init(folder: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = folder ?? base.appendingPathComponent("Notcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("save.json")
    }

    func load() -> ArcadeSave {
        guard let data = try? Data(contentsOf: url), let save = try? ArcadeSave.decode(data) else {
            return ArcadeSave()
        }
        return save
    }

    /// Writes after a short pause so bursts of changes cost one write.
    func scheduleSave(_ provider: @escaping () -> ArcadeSave) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.write(provider())
        }
    }

    func saveNow(_ save: ArcadeSave) {
        pending?.cancel()
        pending = nil
        write(save)
    }

    private func write(_ save: ArcadeSave) {
        guard let data = try? save.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }

    func reset() -> ArcadeSave {
        pending?.cancel()
        try? FileManager.default.removeItem(at: url)
        let fresh = ArcadeSave()
        write(fresh)
        return fresh
    }
}

import AppKit
import NotcherCore
import SwiftUI
import UniformTypeIdentifiers

@main
enum NotcherMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--render-previews") {
            Prefs.register()
            _ = NSApplication.shared
            let path = flag + 1 < args.count ? args[flag + 1] : "previews"
            PreviewRenderer.run(into: URL(fileURLWithPath: path))
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SaveStore?
    private var arcade: ArcadeController?
    private var notch: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var appliedHotkey: HotkeyPreset?
    private var appliedDisplay: DisplayChoice?
    private var settingsWindow: NSWindow?
    private var defaultsObserver: NSObjectProtocol?
    /// Files opened before launch finished (Open With, or a drop on the app icon).
    private var pendingOpen: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        let store = SaveStore()
        let arcade = ArcadeController(store: store)
        self.store = store
        self.arcade = arcade
        notch = NotchWindowController(arcade: arcade)
        arcade.openSettings = { [weak self] in self?.showSettings() }
        arcade.quitApp = { NSApp.terminate(nil) }
        arcade.requestOpenPanel = { [weak self] in self?.showOpenPanel() }

        applyPrefs()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPrefs() }
        }

        if !Prefs.defaults.bool(forKey: Prefs.Key.onboarded) {
            Prefs.defaults.set(true, forKey: Prefs.Key.onboarded)
            arcade.showToast(Toast(
                symbol: "gamecontroller.fill", title: "Hover the notch to play",
                subtitle: "Esc takes you straight back to work", colors: GameID.arcade.style.colors
            ))
            arcade.showToast(Toast(
                symbol: "square.stack.3d.up.fill", title: "Drag a ROM onto the notch",
                subtitle: "NES and Game Boy games play right here", colors: LauncherPage.library.colors
            ))
        }

        if !pendingOpen.isEmpty {
            arcade.importFiles(pendingOpen)
            pendingOpen = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let arcade {
            arcade.importFiles(urls)
        } else {
            pendingOpen += urls
        }
    }

    // MARK: - Opening ROMs

    func showOpenPanel() {
        guard let arcade else { return }
        if arcade.mode != .closed { arcade.close() }
        let panel = NSOpenPanel()
        panel.title = "Add Games to Notcher"
        panel.message = "Choose NES or Game Boy ROMs, or zip files containing them."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = (ConsoleSystem.allExtensions + ["zip"]).compactMap { UTType(filenameExtension: $0) }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { arcade.importFiles(urls) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        arcade?.prepareForQuit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Preferences

    private func applyPrefs() {
        arcade?.reloadPrefs()

        let preset = Prefs.hotkey
        if preset != appliedHotkey {
            appliedHotkey = preset
            hotKey = nil
            if let code = preset.keyCode {
                hotKey = HotKey(keyCode: code, modifiers: preset.carbonModifiers) { [weak self] in
                    MainActor.assumeIsolated { self?.arcade?.toggleFromHotkey() }
                }
            }
            rebuildMenu()
        }

        let display = Prefs.display
        if display != appliedDisplay {
            appliedDisplay = display
            notch?.layout()
        }

        if Prefs.showMenuBarIcon {
            if statusItem == nil { installStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Notcher")
            image?.isTemplate = true
            button.image = image
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Notcher", action: #selector(openArcade), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if Prefs.hotkey != .off {
            let hint = NSMenuItem(title: "Shortcut: \(Prefs.hotkey.title)", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        let trophies = NSMenuItem(title: "Trophies", action: #selector(openTrophies), keyEquivalent: "")
        trophies.target = self
        menu.addItem(trophies)
        menu.addItem(.separator())
        let openROM = NSMenuItem(title: "Open ROM…", action: #selector(openROMFromMenu), keyEquivalent: "o")
        openROM.target = self
        menu.addItem(openROM)
        let library = NSMenuItem(title: "Show ROM Library in Finder", action: #selector(revealLibrary), keyEquivalent: "")
        library.target = self
        menu.addItem(library)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Notcher", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func openArcade() {
        arcade?.open(focus: true)
    }

    @objc private func openTrophies() {
        arcade?.open(focus: true)
        arcade?.showTrophies()
    }

    @objc private func openROMFromMenu() {
        showOpenPanel()
    }

    @objc private func revealLibrary() {
        arcade?.revealLibrary()
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings window

    func showSettings() {
        guard let arcade else { return }
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(arcade: arcade))
            let window = NSWindow(contentViewController: controller)
            window.title = "Notcher Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 640))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

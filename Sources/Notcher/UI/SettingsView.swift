import AppKit
import NotcherCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let arcade: ArcadeController

    @AppStorage(Prefs.Key.hoverLaunch) private var hoverLaunch = HoverLaunch.fast.rawValue
    @AppStorage(Prefs.Key.openDelay) private var openDelay = OpenDelay.instant.rawValue
    @AppStorage(Prefs.Key.showTicker) private var showTicker = true
    @AppStorage(Prefs.Key.sound) private var sound = true
    @AppStorage(Prefs.Key.volume) private var volume = 0.5
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.hotkey) private var hotkey = HotkeyPreset.controlOptionCommandG.rawValue
    @AppStorage(Prefs.Key.menuBarIcon) private var menuBarIcon = true
    @AppStorage(Prefs.Key.drawThree) private var drawThree = false
    @AppStorage(Prefs.Key.display) private var display = DisplayChoice.automatic.rawValue
    @AppStorage(Prefs.Key.sudokuDifficulty) private var sudokuDifficulty = SudokuEngine.Difficulty.medium.rawValue
    @AppStorage(Prefs.Key.gbPalette) private var gbPalette = GameBoyPalette.classic.rawValue
    @AppStorage(Prefs.Key.screenFilter) private var screenFilter = ScreenFilter.authentic.rawValue
    @AppStorage(Prefs.Key.resumeROMs) private var resumeROMs = true

    @State private var nickname = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black)
                        NotcherMark(size: 22)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notcher")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                        Text("Your notch. Your arcade. Hover, play, Esc, back to work.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Version \(AppVersion.display)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Your ROMs") {
                LabeledContent("Library") {
                    HStack(spacing: 8) {
                        Text(arcade.roms.count == 1 ? "1 game" : "\(arcade.roms.count) games")
                            .foregroundStyle(.secondary)
                        Button("Add…") { arcade.requestOpenPanel() }
                        Button("Show in Finder") { arcade.revealLibrary() }
                    }
                }
                Toggle("Continue where you left off", isOn: $resumeROMs)
                Picker("Game Boy colours", selection: $gbPalette) {
                    ForEach(GameBoyPalette.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Screen", selection: $screenFilter) {
                    ForEach(ScreenFilter.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("Controller") {
                    Text(GamepadInput.shared.connectedName ?? "None connected")
                        .foregroundStyle(.secondary)
                }
                Text("Drag a NES, Game Boy or Game Boy Color ROM (or a zip) onto the notch to add and play it. Controls: arrows or WASD move, X is A, Z is B, Return is Start, Backspace is Select, hold Tab to fast-forward. Xbox, PlayStation and MFi controllers work too. Only play games you own.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Notch") {
                Picker("Open when hovering", selection: $openDelay) {
                    ForEach(OpenDelay.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Hover to launch", selection: $hoverLaunch) {
                    ForEach(HoverLaunch.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Show live ticker beside the notch", isOn: $showTicker)
                Picker("Display", selection: $display) {
                    ForEach(DisplayChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }

            Section("Keyboard") {
                Picker("Open with shortcut", selection: $hotkey) {
                    ForEach(HotkeyPreset.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("In game") {
                    Text("Esc back to work · P pause · M mute · S share")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sound & feel") {
                Toggle("Sound effects", isOn: $sound)
                Slider(value: $volume, in: 0...1) {
                    Text("Volume")
                }
                .disabled(!sound)
                Toggle("Haptic tap on launch (Force Touch trackpads)", isOn: $haptics)
            }

            Section("Games") {
                Picker("Solitaire", selection: $drawThree) {
                    Text("Draw 1").tag(false)
                    Text("Draw 3").tag(true)
                }
                .onChange(of: drawThree) { _, _ in
                    arcade.discardSession(.solitaire)
                }
                Picker("Sudoku", selection: $sudokuDifficulty) {
                    ForEach(SudokuEngine.Difficulty.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .onChange(of: sudokuDifficulty) { _, _ in
                    arcade.discardSession(.sudoku)
                }
            }

            Section("Player") {
                LabeledContent("Player ID") {
                    Text(arcade.save.profile.id)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                TextField("Nickname", text: $nickname, prompt: Text("Optional"))
                    .onSubmit { arcade.setNickname(nickname) }
                Text("No account, no subscription. Your ID is anonymous and everything stays on this Mac; a nickname only appears on share cards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show menu bar icon", isOn: $menuBarIcon)
                HStack {
                    Button("Reset all progress…", role: .destructive) {
                        confirmReset = true
                    }
                    Spacer()
                    Button("Quit Notcher") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .onAppear { nickname = arcade.save.profile.nickname ?? "" }
        .onDisappear { arcade.setNickname(nickname) }
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset scores, achievements and idle games", role: .destructive) {
                arcade.resetProgress()
                nickname = ""
            }
        } message: {
            Text("This can't be undone. You'll get a fresh anonymous player ID.")
        }
    }
}

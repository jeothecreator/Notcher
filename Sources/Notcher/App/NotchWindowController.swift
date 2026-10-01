import AppKit
import NotcherCore
import QuartzCore
import SwiftUI

/// Owns the notch panel: positioning, mouse tracking, click-through,
/// keyboard routing, focus hand-off and the game loop.
@MainActor
final class NotchWindowController: NSObject, NSWindowDelegate {
    let panel: NotchPanel
    private let arcade: ArcadeController
    private var hosting: NSView?
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var previousApp: NSRunningApplication?
    private(set) var screen: NSScreen?

    init(arcade: ArcadeController) {
        self.arcade = arcade
        self.panel = NotchPanel(frame: NSRect(x: 0, y: 0, width: 816, height: 480))
        super.init()

        let hosting = NotchHostingView(rootView: NotchRootView(arcade: arcade))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hosting = hosting
        panel.delegate = self

        arcade.requestFocus = { [weak self] in self?.takeFocus() }
        arcade.resignFocus = { [weak self] in self?.releaseFocus() }
        arcade.modeChanged = { [weak self] mode in self?.modeDidChange(mode) }
        arcade.shareRequested = { [weak self] session, summary in
            guard let self, let view = self.hosting else { return }
            ShareService.share(session: session, summary: summary, profile: self.arcade.save.profile, shapeRect: self.arcade.shapeRect, in: view)
            self.arcade.showToast(Toast(symbol: "doc.on.doc.fill", title: "Score card copied", subtitle: "Paste it anywhere, or pick a share target", colors: session.game.style.colors))
        }

        layout()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
    }

    // MARK: - Layout

    static func targetScreen() -> NSScreen? {
        switch Prefs.display {
        case .automatic:
            return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first ?? NSScreen.main
        case .main:
            return NSScreen.screens.first ?? NSScreen.main
        }
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchMetrics(notchWidth: max(120, width), notchHeight: top, hasNotch: true)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchMetrics(notchWidth: 0, notchHeight: menuBar > 12 ? menuBar : 25, hasNotch: false)
    }

    func layout() {
        guard let screen = Self.targetScreen() else { return }
        self.screen = screen
        let metrics = Self.metrics(for: screen)
        if arcade.metrics != metrics { arcade.metrics = metrics }
        let size = ArcadeController.panelSize(for: metrics)
        arcade.panelSize = size
        let frame = NSRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    @objc private func screensChanged() {
        layout()
        panel.orderFrontRegardless()
    }

    // MARK: - Mouse

    private func installMonitors() {
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.trackMouse() }
            return event
        }) {
            monitors.append(local)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp], handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }) {
            monitors.append(keys)
        }
        // A slow poll backs up the monitors (they can miss events around
        // fullscreen transitions and Mission Control).
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private var lastPointer: CGPoint?

    private func trackMouse() {
        let location = NSEvent.mouseLocation
        let frame = panel.frame
        let point = CGPoint(x: location.x - frame.minX, y: frame.maxY - location.y)
        if point == lastPointer { return }
        lastPointer = point
        arcade.pointerMoved(point)
        updateClickThrough(point)
    }

    private func updateClickThrough(_ point: CGPoint?) {
        let interactive: Bool
        if let point, arcade.mode.isExpanded {
            interactive = arcade.shapeRect.contains(point)
        } else {
            interactive = false
        }
        if panel.ignoresMouseEvents == interactive {
            panel.ignoresMouseEvents = !interactive
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel || (event.window == nil && panel.isKeyWindow) else { return false }
        guard let key = KeyMapper.map(event) else { return false }
        if event.type == .keyUp {
            if case .game(let gameKey) = key { arcade.keyUp(gameKey) }
            return true
        }
        return arcade.keyDown(key, isRepeat: event.isARepeat)
    }

    // MARK: - Focus

    private func takeFocus() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        panel.makeKeyAndOrderFront(nil)
        if !panel.isKeyWindow {
            // Some setups refuse key status to a non-activating panel; fall back
            // to activating Notcher for the length of the game.
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func releaseFocus() {
        let app = previousApp
        previousApp = nil
        if NSApp.isActive {
            if let app, !app.isTerminated {
                _ = app.activate(options: [])
            } else {
                NSApp.deactivate()
            }
        }
        if panel.isKeyWindow {
            // Hand keyboard focus back to the app underneath without hiding the notch.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        arcade.focusChanged(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        arcade.focusChanged(false)
    }

    // MARK: - Game loop

    private func modeDidChange(_ mode: NotchMode) {
        if case .game = mode {
            startLoop()
        } else {
            stopLoop()
        }
        lastPointer = nil
        let location = NSEvent.mouseLocation
        let frame = panel.frame
        updateClickThrough(CGPoint(x: location.x - frame.minX, y: frame.maxY - location.y))
    }

    private func startLoop() {
        guard displayLink == nil, let view = panel.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = 0
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrame == 0 ? 1.0 / 60 : now - lastFrame
        lastFrame = now
        arcade.frame(max(0, min(dt, 0.05)))
    }
}

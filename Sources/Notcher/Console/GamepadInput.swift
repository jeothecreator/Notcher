import GameController
import NotcherCore
import Observation

/// Reads whichever game controller is connected (Xbox, PlayStation, Switch
/// Pro, MFi). Buttons map by position like Nintendo's layout: the right face
/// button is A, the bottom one is B.
@MainActor
@Observable
final class GamepadInput {
    static let shared = GamepadInput()

    /// The connected controller's name, if any.
    private(set) var connectedName: String?

    private init() {
        // A notch panel never makes Notcher the active app, so listen in the background.
        GCController.shouldMonitorBackgroundEvents = true
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        GCController.startWirelessControllerDiscovery {}
        refresh()
    }

    private func refresh() {
        let controller = GCController.current ?? GCController.controllers().first
        connectedName = controller.map { $0.vendorName ?? "Controller" }
    }

    /// Buttons currently held on the active controller.
    var buttons: ConsoleButtons {
        guard let controller = GCController.current ?? GCController.controllers().first else { return [] }
        var b: ConsoleButtons = []
        if let pad = controller.extendedGamepad {
            let dpad = pad.dpad
            let stick = pad.leftThumbstick
            if dpad.up.isPressed || stick.yAxis.value > 0.5 { b.insert(.up) }
            if dpad.down.isPressed || stick.yAxis.value < -0.5 { b.insert(.down) }
            if dpad.left.isPressed || stick.xAxis.value < -0.5 { b.insert(.left) }
            if dpad.right.isPressed || stick.xAxis.value > 0.5 { b.insert(.right) }
            if pad.buttonB.isPressed || pad.buttonY.isPressed { b.insert(.a) }
            if pad.buttonA.isPressed || pad.buttonX.isPressed { b.insert(.b) }
            if pad.buttonMenu.isPressed { b.insert(.start) }
            if pad.buttonOptions?.isPressed == true { b.insert(.select) }
        } else if let pad = controller.microGamepad {
            let dpad = pad.dpad
            if dpad.up.isPressed { b.insert(.up) }
            if dpad.down.isPressed { b.insert(.down) }
            if dpad.left.isPressed { b.insert(.left) }
            if dpad.right.isPressed { b.insert(.right) }
            if pad.buttonX.isPressed { b.insert(.a) }
            if pad.buttonA.isPressed { b.insert(.b) }
            if pad.buttonMenu.isPressed { b.insert(.start) }
        }
        return b
    }
}

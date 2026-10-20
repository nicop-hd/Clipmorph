import AppKit
import SwiftUI

/// Borderless panel that can take keyboard focus without activating the app,
/// so the app you copied from stays frontmost (and receives the paste).
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController {
    private let model: TransformModel
    private let panel: KeyPanel
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(model: TransformModel, openSettings: @escaping () -> Void) {
        self.model = model
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PanelView(model: model, openSettings: { [weak self] in
            self?.hide()
            openSettings()
        })
        panel.contentView = NSHostingView(rootView: view)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.reset(input: Clipboard.read() ?? "")
        positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        guard panel.isVisible else { return }
        model.cancel()
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.12)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            hide()
            return true
        case 36, 76: // Return, keypad Enter
            switch model.phase {
            case .picking:
                model.runSelected()
            case .done:
                accept()
            default:
                break
            }
            return true
        case 51: // Delete
            if model.phase != .picking {
                model.backToRecipes()
                return true
            }
            return false
        case 125: // Down
            model.moveSelection(by: 1)
            return true
        case 126: // Up
            model.moveSelection(by: -1)
            return true
        default:
            break
        }

        if model.phase == .picking,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let char = event.charactersIgnoringModifiers?.first,
           let number = char.wholeNumberValue, (1...9).contains(number) {
            model.run(at: number - 1)
            return true
        }
        return false
    }

    /// The result is already on the clipboard; close and optionally paste it into the previous app.
    private func accept() {
        let shouldPaste = model.settings.autoPaste
        hide()
        guard shouldPaste else { return }
        if Clipboard.canAutoPaste(prompt: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Clipboard.pasteIntoFrontApp()
            }
        }
    }
}

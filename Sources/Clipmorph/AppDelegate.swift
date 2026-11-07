import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let settings = SettingsStore()
    private lazy var model = TransformModel(settings: settings)
    private lazy var panel = PanelController(model: model, openSettings: { [weak self] in self?.showSettings() })
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private lazy var updater = UpdateController(settings: settings)
    private var updateItem: NSMenuItem?
    private var transformItem: NSMenuItem?
    private var shortcut = Shortcut.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The "Template" suffix makes AppKit tint the robot for light and dark menu bars.
        let icon = NSImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Clipmorph")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.accessibilityDescription = "Clipmorph"
        statusItem.button?.image = icon

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "About Clipmorph", action: #selector(showAbout), keyEquivalent: "")
        updateItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        transformItem = menu.addItem(withTitle: "", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Change Shortcut…", action: #selector(changeShortcut), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Buy Me a Coffee…", action: #selector(openBuyMeACoffee), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clipmorph", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu

        if !register(shortcut) {
            showShortcutTaken(shortcut)
        }

        updater.onBusyChange = { [weak self] busy in
            self?.updateItem?.title = busy ? "Checking for Updates…" : "Check for Updates…"
            self?.updateItem?.isEnabled = !busy
        }
        updater.start()

        if settings.apiKey(for: settings.provider) == nil {
            showSettings()
        }
    }

    @objc func showPanel() {
        panel.toggle()
    }

    /// Registers the global shortcut; on failure the previous registration is gone, so callers re-register one.
    @discardableResult
    private func register(_ shortcut: Shortcut) -> Bool {
        hotKey = nil // unregister the old one first
        let hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.showPanel()
        }
        transformItem?.title = "Transform Clipboard  \(shortcut.displayString)"
        guard hotKey.isRegistered else { return false }
        self.hotKey = hotKey
        return true
    }

    @objc func changeShortcut() {
        let alert = NSAlert()
        alert.messageText = "Press the new shortcut"
        alert.informativeText = "Currently \(shortcut.displayString). Hold at least one of ⌃, ⌥ or ⌘ and press a key."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset to \(Shortcut.default.displayString)")

        // Unregister while recording, so pressing the current shortcut is captured instead of opening the panel.
        hotKey = nil
        var recorded: Shortcut?
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let candidate = Shortcut(event: event) else { return event } // plain keys reach the alert (Esc cancels)
            recorded = candidate
            NSApp.stopModal(withCode: .OK)
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        alert.window.orderOut(nil)

        if response == .alertSecondButtonReturn { recorded = .default }
        guard let recorded else {
            register(shortcut)
            return
        }
        if register(recorded) {
            shortcut = recorded
            shortcut.save()
        } else {
            showShortcutTaken(recorded)
            register(shortcut)
        }
    }

    private func showShortcutTaken(_ shortcut: Shortcut) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(shortcut.displayString) is already in use"
        alert.informativeText = "Another app or macOS owns this shortcut. Choose a different one with Change Shortcut… in the Clipmorph menu."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.title = "About Clipmorph"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            if let size = window.contentView?.fittingSize {
                window.setContentSize(size)
            }
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.center()
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func checkForUpdates() {
        updater.check(userInitiated: true)
    }

    @objc func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/nicop.hd")!)
    }

    @objc func showSettings() {
        settings.reloadRepository()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "Clipmorph Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

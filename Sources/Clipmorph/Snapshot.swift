import AppKit
import SwiftUI

/// Renders the real panel view offscreen so its look can be checked without opening it.
@MainActor
enum Snapshot {
    static func run(directory: String) -> Never {
        _ = NSApplication.shared
        let settings = SettingsStore()
        let model = TransformModel(settings: settings)
        let input = "hey, can u send me the report by friday? i need it for the meeting with the client"
        let output = "Hi, could you send me the report by Friday? I need it for the client meeting."

        let states: [(String, () -> Void)] = [
            ("panel-recipes", { model.stage(input: input) }),
            ("panel-writing", { model.stage(input: input, recipeIndex: 2, output: "Hi, could you send me the report", phase: .running) }),
            ("panel-done", { model.stage(input: input, recipeIndex: 2, output: output, phase: .done) }),
        ]

        let backdrop = NSColor(red: 0x12 / 255, green: 0x0A / 255, blue: 0x22 / 255, alpha: 1)
        for (name, apply) in states {
            apply()
            let host = NSHostingView(rootView: PanelView(model: model, openSettings: {}).padding(24))
            host.frame = NSRect(x: 0, y: 0, width: 628, height: 488)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = backdrop
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))

            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print(url.path)
        }
        renderSettings(settings, to: directory, backdrop: backdrop)
        settings.isRepositoryDropTargeted = true
        renderSettings(settings, to: directory, backdrop: backdrop, name: "settings-drop-targeted")
        settings.isRepositoryDropTargeted = false
        exit(0)
    }

    private static func renderSettings(_ settings: SettingsStore, to directory: String, backdrop: NSColor, name: String = "settings") {
        settings.reloadRepository()
        // Tall enough to show every section without scrolling.
        let host = NSHostingView(rootView: SettingsView(settings: settings, height: 1180))
        host.frame.size = NSSize(width: 480, height: 1180)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = backdrop
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }
}

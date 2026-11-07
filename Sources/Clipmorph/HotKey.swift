import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey registered through Carbon, which still works without Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    /// False when macOS refused the combination, usually because another app already owns it.
    private(set) var isRegistered = false

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &eventType, userData, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4D50), id: 1) // "CLMP"
        isRegistered = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// The global shortcut that opens the panel, saved in UserDefaults.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (controlKey, optionKey, shiftKey, cmdKey).
    var modifiers: UInt32
    /// How the key is shown, e.g. "`" or "Space".
    var key: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey), key: "`")
    private static let defaultsKey = "shortcut"

    static func load() -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .default }
        return shortcut
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    var displayString: String {
        let parts: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return parts.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    /// Builds a shortcut from a key press; nil unless ⌃, ⌥ or ⌘ is held, so plain typing can't become global.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        let named: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
                                    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
        let typed = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        // Function keys type private-use characters (U+F700…), so they fall back to the key code.
        let printable = !typed.isEmpty && typed.unicodeScalars.allSatisfy { $0.value > 32 && !(0xF700...0xF8FF).contains($0.value) }
        let key = named[Int(event.keyCode)] ?? (printable ? typed : "Key \(event.keyCode)")
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(carbon), key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }
}

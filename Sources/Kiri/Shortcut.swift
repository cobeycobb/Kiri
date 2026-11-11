import AppKit
import Carbon

final class GlobalShortcut {
    static let shared = GlobalShortcut()
    var action: (() -> Void)?
    var keyCode: UInt32 { UInt32(UserDefaults.standard.integer(forKey: "shortcutKey")) }
    var modifiers: UInt32 { UInt32(UserDefaults.standard.integer(forKey: "shortcutModifiers")) }
    var label: String { UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⌘⇧1" }
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    init() {
        UserDefaults.standard.register(defaults: ["shortcutKey": 18, "shortcutModifiers": Int(cmdKey | shiftKey), "shortcutLabel": "⌘⇧1"])
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let object = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { object.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    @discardableResult func register() -> OSStatus {
        register(key: keyCode, modifiers: modifiers)
    }
    private func register(key: UInt32, modifiers: UInt32) -> OSStatus {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x4B495249, id: 1), GetApplicationEventTarget(), 0, &ref)
        if result == noErr { hotKey = ref }
        return result
    }
    func update(event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return "Include Command, Control, or Option in the shortcut." }
        // macOS screenshot shortcuts must remain available to the system.
        if flags.contains(.command), flags.contains(.shift), [20, 21, 23, 22].contains(Int(event.keyCode)) {
            return "That shortcut belongs to macOS screenshots. Choose another combination."
        }
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        let keyLabel = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        guard !keyLabel.isEmpty, keyLabel.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return "Choose a letter, number, or punctuation key."
        }
        label += keyLabel == " " ? "Space" : keyLabel
        guard register(key: UInt32(event.keyCode), modifiers: modifiers) == noErr else {
            register()
            return "That shortcut is unavailable. Choose another combination."
        }
        UserDefaults.standard.set(Int(event.keyCode), forKey: "shortcutKey")
        UserDefaults.standard.set(Int(modifiers), forKey: "shortcutModifiers")
        UserDefaults.standard.set(label, forKey: "shortcutLabel")
        return nil
    }
    func suspend() { if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil } }
}

final class ShortcutRecorder: NSButton {
    var onChange: ((String?) -> Void)?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = GlobalShortcut.shared.label
        target = self; action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func beginRecording() {
        recording = true
        GlobalShortcut.shared.suspend()
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }
    override func resignFirstResponder() -> Bool {
        if recording { finish() }
        return super.resignFirstResponder()
    }
    private func finish() {
        recording = false
        GlobalShortcut.shared.register()
        title = GlobalShortcut.shared.label
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        let error = GlobalShortcut.shared.update(event: event)
        finish(); onChange?(error)
    }
}

import AppKit
import ServiceManagement

@main
struct KiriMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--write-fixtures") {
            for text in ["猫", "鬱", "猫　食べる　日本語"] {
                let image = SelfTests.fixture(text, size: 40)
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                try! data.write(to: URL(fileURLWithPath: "/tmp/kiri-" + text + ".png"))
            }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTests.run() ? 0 : 1)
        }
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var busy = false
    var permission = CGPreflightScreenCaptureAccess()
    var lastStatus = "Ready to capture Japanese text"
    var loginEnabled = SMAppService.mainApp.status == .enabled
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsController?
    private let selection = SelectionController()
    private var previousApp: NSRunningApplication?
    private var toast: NSPanel?
    private var toastDismiss: DispatchWorkItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["copyFeedback": true, "languageCorrection": false])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Kiri")
        if let url = Bundle.main.url(forResource: "Kiri", withExtension: "png"), let logo = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = logo
        }
        statusItem.button?.toolTip = "Kiri — capture Japanese text"
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture Text", action: #selector(captureAction), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Kiri", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Kiri", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
        GlobalShortcut.shared.action = { [weak self] in self?.captureAction() }
        if GlobalShortcut.shared.register() != noErr { lastStatus = "Shortcut unavailable. Choose another shortcut in Settings." }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.permission = CGPreflightScreenCaptureAccess()
                self?.loginEnabled = SMAppService.mainApp.status == .enabled
                self?.settingsController?.refresh()
            }
        }
        if !permission || !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--settings") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc func showSettings() {
        if settingsController == nil { settingsController = SettingsController(model: self) }
        settingsController?.refresh()
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    func grantPermission() {
        permission = CGRequestScreenCaptureAccess()
        if !permission { openPrivacy() }
    }
    func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && SMAppService.mainApp.status == .requiresApproval {
                lastStatus = "Approve Kiri in System Settings → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { lastStatus = "Could not change launch at login: \(error.localizedDescription)" }
    }

    @objc func captureAction() {
        guard !busy else { return }
        permission = CGPreflightScreenCaptureAccess()
        guard permission else {
            showSettings()
            lastStatus = "Allow screen capture below, then try again."
            grantPermission()
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        busy = true
        toast?.orderOut(nil)
        lastStatus = "Select an area…"
        Task { [self] in
            do {
                try await selection.present { [weak self] image in
                    guard let self else { return }
                    if self.previousApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
                        self.previousApp?.activate(options: [])
                    }
                    guard let image else {
                        self.busy = false; self.lastStatus = "Cancelled — clipboard unchanged"; return
                    }
                    self.lastStatus = "Recognizing…"
                    let correction = UserDefaults.standard.bool(forKey: "languageCorrection")
                    Task {
                        do {
                            let result = try await Task.detached(priority: .userInitiated) {
                                try OCR.recognize(image, correction: correction)
                            }.value
                            self.busy = false
                            guard !result.text.isEmpty else {
                                self.lastStatus = "No text found — clipboard unchanged"
                                self.showToast("No text found", detail: "Select the complete text with a little space around it", error: true)
                                return
                            }
                            let clipboard = NSPasteboard.general
                            clipboard.clearContents()
                            guard clipboard.setString(result.text, forType: .string) else {
                                self.lastStatus = "Could not write to the clipboard"
                                self.showToast("Could not copy", detail: "Please try again", error: true)
                                return
                            }
                            self.lastStatus = "Text copied to clipboard"
                            if UserDefaults.standard.bool(forKey: "copyFeedback") {
                                self.showToast("Copied", detail: result.text, error: false)
                            }
                        } catch { self.captureFailed(error) }
                    }
                }
            } catch { captureFailed(error) }
        }
    }

    private func captureFailed(_ error: Error) {
        selection.cancel()
        busy = false
        permission = CGPreflightScreenCaptureAccess()
        lastStatus = "Capture failed: \(error.localizedDescription)"
        if !permission { showSettings() }
        showToast("Capture failed", detail: permission ? error.localizedDescription : "Allow Kiri screen capture in System Settings", error: true)
    }
    private func showToast(_ title: String, detail: String, error: Bool) {
        toastDismiss?.cancel()
        toast?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 92),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = makeToast(title: title, detail: detail, error: error)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.minY + 52))
        }
        panel.orderFrontRegardless(); toast = panel
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        toastDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}


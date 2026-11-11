import AppKit

@MainActor
final class SettingsController: NSWindowController {
    private unowned let model: AppDelegate
    private let permissionLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "Allow Screen Capture…", target: nil, action: nil)
    private let captureButton = NSButton(title: "Capture Text", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Launch Kiri at login", target: nil, action: nil)
    private let recorder = ShortcutRecorder()
    init(model: AppDelegate) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Kiri"; window.isReleasedWhenClosed = false; window.center()
        super.init(window: window)
        let root = NSView(); window.contentView = root
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
                                     stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
                                     stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24)])
        func label(_ text: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            return field
        }
        let heading = label("Kiri", size: 32)
        heading.font = .systemFont(ofSize: 32, weight: .semibold)
        let titleStack = NSStackView(views: [heading, label("A little cut. A word unlocked.", size: 14, secondary: true)])
        titleStack.orientation = .vertical; titleStack.alignment = .leading; titleStack.spacing = 6
        if let url = Bundle.main.url(forResource: "Kiri", withExtension: "png"), let image = NSImage(contentsOf: url) {
            let logo = NSImageView(image: image)
            logo.imageScaling = .scaleProportionallyUpOrDown
            logo.setAccessibilityLabel("Kiri logo")
            logo.widthAnchor.constraint(equalToConstant: 72).isActive = true
            logo.heightAnchor.constraint(equalToConstant: 72).isActive = true
            let header = NSStackView(views: [logo, titleStack]); header.spacing = 14
            stack.addArrangedSubview(header)
        } else { stack.addArrangedSubview(titleStack) }
        stack.addArrangedSubview(label("Press your shortcut, drag around Japanese text, and release to copy. Then look it up in Yomitan.", size: 14))
        let row = NSStackView(views: [label("Capture shortcut"), recorder]); row.spacing = 22
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 145).isActive = true
        recorder.onChange = { [weak self] error in
            guard let self else { return }
            self.model.lastStatus = error ?? "Shortcut saved: \(GlobalShortcut.shared.label)"
            self.refresh()
        }
        stack.addArrangedSubview(row)
        let feedback = NSButton(checkboxWithTitle: "Show a brief preview after copying", target: self, action: #selector(feedbackChanged(_:)))
        feedback.state = UserDefaults.standard.bool(forKey: "copyFeedback") ? .on : .off
        stack.addArrangedSubview(feedback)
        let correction = NSButton(checkboxWithTitle: "Use language correction", target: self, action: #selector(correctionChanged(_:)))
        correction.state = UserDefaults.standard.bool(forKey: "languageCorrection") ? .on : .off
        stack.addArrangedSubview(correction)
        stack.addArrangedSubview(label("Leave correction off for individual kanji and unfamiliar words.", size: 12, secondary: true))
        login.target = self; login.action = #selector(loginChanged(_:)); stack.addArrangedSubview(login)
        let separator = NSBox(); separator.boxType = .separator; stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        permissionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(permissionLabel)
        stack.addArrangedSubview(label("Recognition stays on your Mac. Screenshots are never saved.", size: 12, secondary: true))
        permissionButton.bezelStyle = .rounded; permissionButton.target = self; permissionButton.action = #selector(allowCapture)
        stack.addArrangedSubview(permissionButton)
        stack.addArrangedSubview(label("If macOS asks you to quit and reopen Kiri after allowing access, do that once.", size: 12, secondary: true))
        let footer = NSStackView(views: [statusLabel, captureButton]); footer.spacing = 12
        statusLabel.font = .systemFont(ofSize: 11); statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        captureButton.bezelStyle = .rounded; captureButton.target = self; captureButton.action = #selector(capture)
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func refresh() {
        permissionLabel.stringValue = model.permission ? "✓ Screen capture is allowed" : "Allow screen capture to begin"
        permissionLabel.textColor = model.permission ? .systemGreen : .labelColor
        permissionButton.isHidden = model.permission
        statusLabel.stringValue = model.lastStatus
        captureButton.isEnabled = !model.busy
        login.state = model.loginEnabled ? .on : .off
    }
    @objc private func feedbackChanged(_ sender: NSButton) { UserDefaults.standard.set(sender.state == .on, forKey: "copyFeedback") }
    @objc private func correctionChanged(_ sender: NSButton) { UserDefaults.standard.set(sender.state == .on, forKey: "languageCorrection") }
    @objc private func loginChanged(_ sender: NSButton) { model.setLogin(sender.state == .on); refresh() }
    @objc private func allowCapture() { model.grantPermission(); refresh() }
    @objc private func capture() { model.captureAction(); refresh() }
}

@MainActor
func makeToast(title: String, detail: String, error: Bool) -> NSView {
    let view = NSVisualEffectView()
    view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
    view.wantsLayer = true; view.layer?.cornerRadius = 16
    let icon = NSImageView(image: NSImage(systemSymbolName: error ? "exclamationmark.circle" : "checkmark.circle.fill", accessibilityDescription: title)!)
    icon.contentTintColor = error ? .systemOrange : .systemTeal
    let heading = NSTextField(labelWithString: title); heading.font = .systemFont(ofSize: 14, weight: .semibold)
    let text = NSTextField(wrappingLabelWithString: detail); text.font = .systemFont(ofSize: 16); text.maximumNumberOfLines = 2
    let column = NSStackView(views: [heading, text]); column.orientation = .vertical; column.alignment = .leading; column.spacing = 4
    let row = NSStackView(views: [icon, column]); row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(row)
    NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
                                 row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
                                 row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                                 icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24)])
    return view
}

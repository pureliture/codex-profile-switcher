import AppKit
import CodexProfileSwitcherCore

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var didPlacePanel = false
    private lazy var paths = AppPaths()
    private lazy var store = ProfileStore(appStateRoot: paths.appStateRoot)

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? store.initialize()
        try? OfficialLoginCoordinator.purgeStaleTemporaryLoginHomes(appStateRoot: paths.appStateRoot)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = title()
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item
        rebuildMenu()
        DispatchQueue.main.async { self.showPanel(placement: .centered) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(placement: .centered)
        return false
    }

    private func title() -> String {
        guard let registry = try? store.loadRegistry(),
              let activeId = registry.activeProfileId,
              let active = registry.profiles.first(where: { $0.id == activeId }) else {
            return "Codex"
        }
        return active.label.prefix(2).uppercased()
    }

    private func panelState() -> PanelState {
        let registry = (try? store.loadRegistry()) ?? ProfileRegistry()
        let profiles = registry.profiles.map {
            ProfileSummary(id: $0.id, label: $0.label, email: $0.email, isActive: $0.id == registry.activeProfileId)
        }
        return PanelState(profiles: profiles, status: .idle)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Profiles", action: #selector(togglePanel), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Add Profile...", action: #selector(addProfile), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Refresh Local Profiles", action: #selector(refreshProfiles), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        configureStatusButton()
        statusItem?.menu = nil
    }

    @objc private func refreshProfiles() {
        configureStatusButton()
        panel?.contentView = ProfilePanelView(state: panelState(), target: self)
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
            return
        }
        showPanel(placement: .statusItem)
    }

    private func showPanel(placement: PanelPlacement) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = ProfilePanelView(state: panelState(), target: self)
        if didPlacePanel {
            keepVisible(panel)
        } else {
            position(panel, placement: placement)
            didPlacePanel = true
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStatusButton() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Codex Profile Switcher")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = " " + title()
        button.toolTip = "Codex Profile Switcher"
        button.target = self
        button.action = #selector(togglePanel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Codex Profile Switcher"
        panel.backgroundColor = PanelPalette.background
        panel.isOpaque = true
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace]
        return panel
    }

    private func position(_ panel: NSPanel, placement: PanelPlacement) {
        let screenFrame = screenFrame(for: panel)
        let proposedOrigin: NSPoint
        switch placement {
        case .centered:
            proposedOrigin = NSPoint(
                x: screenFrame.midX - panel.frame.width / 2,
                y: screenFrame.midY - panel.frame.height / 2
            )
        case .statusItem:
            if let button = statusItem?.button, let window = button.window {
                let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
                proposedOrigin = NSPoint(
                    x: rect.midX - panel.frame.width / 2,
                    y: rect.minY - panel.frame.height - 10
                )
            } else {
                proposedOrigin = NSPoint(
                    x: screenFrame.midX - panel.frame.width / 2,
                    y: screenFrame.midY - panel.frame.height / 2
                )
            }
        }
        panel.setFrameOrigin(clamped(origin: proposedOrigin, panelSize: panel.frame.size, screenFrame: screenFrame))
    }

    private func keepVisible(_ panel: NSPanel) {
        let origin = clamped(origin: panel.frame.origin, panelSize: panel.frame.size, screenFrame: screenFrame(for: panel))
        panel.setFrameOrigin(origin)
    }

    private func screenFrame(for panel: NSPanel) -> NSRect {
        if let screen = panel.screen ?? statusItem?.button?.window?.screen ?? NSScreen.main {
            return screen.visibleFrame
        }
        return NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func clamped(origin: NSPoint, panelSize: NSSize, screenFrame: NSRect) -> NSPoint {
        let padding: CGFloat = 12
        let minX = screenFrame.minX + padding
        let maxX = screenFrame.maxX - panelSize.width - padding
        let minY = screenFrame.minY + padding
        let maxY = screenFrame.maxY - panelSize.height - padding
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    @objc fileprivate func addProfile() {
        let alert = NSAlert()
        alert.messageText = "Add Codex Profile"
        alert.informativeText = "Enter a local label. Codex official login will run in an isolated temporary home."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Personal or Enterprise"
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let label = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let coordinator = OfficialLoginCoordinator(
                appStateRoot: self.paths.appStateRoot,
                codexHome: self.paths.codexHome,
                store: self.store,
                runner: DefaultLoginProcessRunner()
            )
            do {
                _ = try coordinator.addProfile(label: label, email: nil)
                DispatchQueue.main.async { self.refreshProfiles() }
            } catch {
                DispatchQueue.main.async {
                    self.showError(title: "Profile was not added", message: "Codex login did not finish. No profile was saved and your active Codex login was not changed.")
                }
            }
        }
    }

    @objc fileprivate func switchProfile(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        let transaction = AuthFileTransaction(codexHome: paths.codexHome, backupRoot: paths.appStateRoot.appendingPathComponent("backups"))
        let service = ProfileSwitchService(
            store: store,
            verifier: SharedStateVerifier(codexHome: paths.codexHome),
            transaction: transaction,
            launcher: MacCodexLauncher()
        )
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try service.switchProfile(id: id)
                DispatchQueue.main.async {
                    self.refreshProfiles()
                    if result.restartSucceeded == false {
                        self.showError(title: "Codex did not reopen", message: "The profile switch succeeded, but Codex Desktop did not reopen automatically. Open Codex manually to use the selected profile.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(title: "Switch blocked", message: "The selected profile could not be activated. Your active Codex account was not changed.")
                }
            }
        }
    }

    @objc fileprivate func removeProfile(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        let label = (try? store.profile(id: id).label) ?? "profile"

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(label)?"
        alert.informativeText = "This deletes only the saved local profile snapshot. Your active Codex login and shared Codex state stay unchanged."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try store.removeProfile(id: id)
            refreshProfiles()
        } catch CodexProfileSwitcherError.activeProfileRemovalBlocked {
            showError(title: "Remove blocked", message: "Switch to another profile before removing the active profile.")
        } catch {
            showError(title: "Remove failed", message: "The selected profile could not be removed. Your active Codex account was not changed.")
        }
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct AppPaths {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    var appStateRoot: URL { home.appendingPathComponent(".codex-profile-switcher") }
    var codexHome: URL { home.appendingPathComponent(".codex") }
}

private enum PanelPlacement {
    case centered
    case statusItem
}

final class ProfilePanelView: NSView {
    private let state: PanelState
    private weak var target: AppDelegate?

    init(state: PanelState, target: AppDelegate) {
        self.state = state
        self.target = target
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        wantsLayer = true
        layer?.backgroundColor = PanelPalette.background.cgColor
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    private func build() {
        add(label("Codex Profiles", x: 26, y: 24, width: 260, height: 28, size: 22, weight: .bold, color: PanelPalette.text))
        add(label("Only auth.json changes. Shared Codex state stays untouched.", x: 26, y: 58, width: 420, height: 20, size: 12, weight: .medium, color: PanelPalette.muted))

        if state.profiles.isEmpty {
            add(emptyCard())
        } else {
            let cards = Array(state.profiles.prefix(2))
            for (index, profile) in cards.enumerated() {
                add(profileCard(profile, index: index))
            }
        }

        let addButton = StyledButton(title: "Add Profile", style: .secondary, target: target, action: #selector(AppDelegate.addProfile))
        addButton.frame = NSRect(x: 24, y: 306, width: 116, height: 28)
        add(addButton)

        let closeButton = StyledButton(title: "Close", style: .secondary, target: self, action: #selector(close))
        closeButton.frame = NSRect(x: 380, y: 306, width: 76, height: 28)
        add(closeButton)
    }

    private func emptyCard() -> NSView {
        let view = rounded(frame: NSRect(x: 26, y: 112, width: 428, height: 170), active: false)
        view.addSubview(label("No profiles yet", x: 24, y: 28, width: 220, height: 24, size: 18, weight: .bold, color: PanelPalette.text))
        view.addSubview(label("Add Personal and Enterprise profiles with official Codex login.", x: 24, y: 62, width: 314, height: 38, size: 12, weight: .medium, color: PanelPalette.muted, lines: 2))
        view.addSubview(PillView(text: "auth.json only", frame: NSRect(x: 24, y: 116, width: 112, height: 26), fill: PanelPalette.activeFill, textColor: PanelPalette.blue))
        return view
    }

    private func profileCard(_ profile: ProfileSummary, index: Int) -> NSView {
        let frame = NSRect(x: 26, y: 112 + index * 92, width: 428, height: 78)
        let view = rounded(frame: frame, active: profile.isActive)
        view.addSubview(label(profile.label, x: 24, y: 18, width: 230, height: 22, size: 17, weight: .bold, color: PanelPalette.text))
        view.addSubview(label(profile.email ?? (profile.isActive ? "Local profile · active auth" : "Ready to switch"), x: 24, y: 44, width: 286, height: 18, size: 12, weight: .medium, color: PanelPalette.muted))
        if profile.isActive {
            view.addSubview(PillView(text: "Active", frame: NSRect(x: 338, y: 27, width: 64, height: 24), fill: PanelPalette.successFill, textColor: PanelPalette.successText))
        } else {
            let button = StyledButton(title: "Switch", style: .primary, target: target, action: #selector(AppDelegate.switchProfile(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
            button.frame = NSRect(x: 300, y: 24, width: 66, height: 30)
            view.addSubview(button)

            let removeButton = IconButton(systemSymbolName: "trash", accessibilityLabel: "Remove \(profile.label)", target: target, action: #selector(AppDelegate.removeProfile(_:)))
            removeButton.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
            removeButton.frame = NSRect(x: 374, y: 24, width: 30, height: 30)
            view.addSubview(removeButton)
        }
        return view
    }

    private func rounded(frame: NSRect, active: Bool) -> NSView {
        CardView(
            frame: frame,
            fill: active ? PanelPalette.activeFill : .white,
            stroke: active ? PanelPalette.blue : PanelPalette.border,
            borderWidth: active ? 2 : 1.3
        )
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor, lines: Int = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byWordWrapping
        return field
    }

    private func add(_ view: NSView) {
        addSubview(view)
    }

    @objc private func close() {
        window?.orderOut(nil)
    }
}

private enum PanelPalette {
    static let background = rgb(0xF8FAFC)
    static let text = rgb(0x111827)
    static let muted = rgb(0x6B7280)
    static let border = rgb(0xD8DEE8)
    static let blue = rgb(0x2563EB)
    static let activeFill = rgb(0xEFF6FF)
    static let successFill = rgb(0xDCFCE7)
    static let successText = rgb(0x15803D)
    static let secondaryFill = rgb(0xF3F4F6)
}

private func rgb(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

final class CardView: NSView {
    init(frame: NSRect, fill: NSColor, stroke: NSColor, borderWidth: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = borderWidth
        layer?.borderColor = stroke.cgColor
        layer?.backgroundColor = fill.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

final class PillView: NSView {
    private let text: String
    private let fill: NSColor
    private let textColor: NSColor

    init(text: String, frame: NSRect, fill: NSColor, textColor: NSColor) {
        self.text = text
        self.fill = fill
        self.textColor = textColor
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textHeight = ceil(attributedText.size().height)
        let textRect = NSRect(
            x: 0,
            y: floor((bounds.height - textHeight) / 2),
            width: bounds.width,
            height: textHeight
        )
        attributedText.draw(in: textRect)
    }
}

final class StyledButton: NSButton {
    enum ButtonStyle {
        case primary
        case secondary
    }

    init(title: String, style: ButtonStyle, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = style == .primary ? 9 : 8
        layer?.borderWidth = style == .primary ? 0 : 1
        layer?.borderColor = PanelPalette.border.cgColor
        layer?.backgroundColor = (style == .primary ? PanelPalette.blue : PanelPalette.secondaryFill).cgColor
        let color: NSColor = style == .primary ? .white : PanelPalette.text
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: color
            ]
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

final class IconButton: NSButton {
    init(systemSymbolName: String, accessibilityLabel: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        wantsLayer = true
        toolTip = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = PanelPalette.border.cgColor
        layer?.backgroundColor = PanelPalette.secondaryFill.cgColor
        image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityLabel)
        image?.isTemplate = true
        contentTintColor = PanelPalette.muted
        imagePosition = .imageOnly
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

struct MacCodexLauncher: CodexLaunching {
    func gracefulRestart() throws {
        for app in NSWorkspace.shared.runningApplications where app.localizedName == "Codex" || app.bundleIdentifier?.localizedCaseInsensitiveContains("codex") == true {
            app.terminate()
        }

        let codexURL = URL(fileURLWithPath: "/Applications/Codex.app")
        if FileManager.default.fileExists(atPath: codexURL.path) {
            NSWorkspace.shared.openApplication(at: codexURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
    }
}

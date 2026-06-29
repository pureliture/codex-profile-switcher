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
        statusItem?.button?.title = title()
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePanel)
        statusItem?.menu = nil
    }

    @objc private func refreshProfiles() {
        statusItem?.button?.title = title()
        panel?.contentView = ProfilePanelView(state: panelState(), target: self)
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = ProfilePanelView(state: panelState(), target: self)
        position(panel)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let button = statusItem?.button, let window = button.window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrameOrigin(NSPoint(x: rect.midX - panel.frame.width / 2, y: rect.minY - panel.frame.height - 10))
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

final class ProfilePanelView: NSView {
    private let state: PanelState
    private weak var target: AppDelegate?

    init(state: PanelState, target: AppDelegate) {
        self.state = state
        self.target = target
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func build() {
        add(label("Codex Profiles", x: 22, y: 22, width: 240, size: 22, weight: .semibold))
        add(label("Only auth.json changes. Config, sessions, MCP, and skills stay shared.", x: 22, y: 50, width: 360, size: 11, weight: .regular, color: .secondaryLabelColor))

        if state.profiles.isEmpty {
            add(emptyCard())
        } else {
            let cards = Array(state.profiles.prefix(4))
            for (index, profile) in cards.enumerated() {
                add(profileCard(profile, index: index))
            }
        }

        let addButton = NSButton(title: "Add Profile", target: target, action: #selector(AppDelegate.addProfile))
        addButton.frame = NSRect(x: 22, y: 270, width: 110, height: 28)
        add(addButton)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(close))
        closeButton.frame = NSRect(x: 320, y: 270, width: 76, height: 28)
        add(closeButton)
    }

    private func emptyCard() -> NSView {
        let view = rounded(frame: NSRect(x: 22, y: 92, width: 376, height: 150), active: false)
        view.addSubview(label("No profiles yet", x: 20, y: 22, width: 220, size: 17, weight: .semibold))
        view.addSubview(label("Add a profile with Codex official login.", x: 20, y: 52, width: 280, size: 12, weight: .regular, color: .secondaryLabelColor))
        return view
    }

    private func profileCard(_ profile: ProfileSummary, index: Int) -> NSView {
        let column = index % 2
        let row = index / 2
        let frame = NSRect(x: 22 + column * 192, y: 92 + row * 84, width: 180, height: 74)
        let view = rounded(frame: frame, active: profile.isActive)
        view.addSubview(label(profile.label, x: 14, y: 12, width: 120, size: 16, weight: .semibold))
        view.addSubview(label(profile.email ?? "Local profile", x: 14, y: 36, width: 140, size: 10, weight: .regular, color: .secondaryLabelColor))
        let button = NSButton(title: profile.isActive ? "Active" : "Switch", target: target, action: #selector(AppDelegate.switchProfile(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
        button.isEnabled = !profile.isActive
        button.frame = NSRect(x: 94, y: 44, width: 72, height: 24)
        view.addSubview(button)
        return view
    }

    private func rounded(frame: NSRect, active: Bool) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 1
        view.layer?.borderColor = (active ? NSColor.systemGreen : NSColor.separatorColor).cgColor
        view.layer?.backgroundColor = (active ? NSColor.systemGreen.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).cgColor
        return view
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = NSRect(x: x, y: y, width: width, height: 22)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func add(_ view: NSView) {
        addSubview(view)
    }

    @objc private func close() {
        window?.orderOut(nil)
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

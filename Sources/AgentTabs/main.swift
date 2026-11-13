import AppKit
import SwiftTerm

final class Session: NSWindowController, NSWindowDelegate, NSTabViewDelegate, LocalProcessTerminalViewDelegate {
    let dir: URL
    let tabs = NSTabView()
    var onClose: ((Session) -> Void)?
    // Terminal tabs prefer fish (autosuggestions, completions, history out of the box); agents run via $SHELL.
    static let terminalShell = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"].first { FileManager.default.isExecutableFile(atPath: $0) }
        ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    init(dir: URL, command: String) {
        self.dir = dir
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.tabbingMode = .preferred
        window.title = "\(dir.lastPathComponent) — \(command)"
        window.contentView = tabs
        super.init(window: window)
        window.delegate = self
        tabs.delegate = self
        addTerminal(label: command, command: command)
        addShell()
        tabs.selectTabViewItem(at: 0)
    }

    func addShell() { addTerminal(label: (Session.terminalShell as NSString).lastPathComponent) }

    required init?(coder: NSCoder) { fatalError() }

    func addTerminal(label: String, command: String? = nil) {
        let term = DropTerminalView(frame: tabs.contentRect)
        term.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        term.processDelegate = self
        term.optionAsMetaKey = false // ⌥ composes chars (@ { } [ ] | on Nordic layouts), not Meta
        var env = ProcessInfo.processInfo.environment
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" } // Finder-launched apps get no locale; fish needs UTF-8 for æøå
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env.removeValue(forKey: "CLAUDECODE")
        let shell = command == nil ? Session.terminalShell : env["SHELL"] ?? "/bin/zsh"
        // fish doesn't read ~/.zprofile/~/.zshrc: pull zsh's login PATH (brew etc.) and aliases in so they keep working.
        let fishInit = ["-C", "fish_add_path -gP (zsh -lc 'print -rl -- $path' 2>/dev/null); zsh -ic alias 2>/dev/null | while read -l a; eval alias $a 2>/dev/null; end"]
        let args = command.map { ["-l", "-i", "-c", "exec \($0)"] } ?? ["-l"] + (shell.hasSuffix("/fish") ? fishInit : [])
        term.startProcess(executable: shell, args: args, environment: env.map { "\($0)=\($1)" },
                          execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: dir.path)
        let item = NSTabViewItem(identifier: term)
        item.label = label
        item.view = term
        tabs.addTabViewItem(item)
        tabs.selectTabViewItem(item)
    }

    // Every tab switch (⌃1…9, ⌘⌥[ ], click, close) lands keyboard focus in the terminal.
    func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        window?.makeFirstResponder(item?.view)
    }

    func item(for view: TerminalView) -> NSTabViewItem? {
        tabs.tabViewItems.first { $0.view === view }
    }

    func windowWillClose(_ notification: Notification) {
        tabs.tabViewItems.forEach { ($0.view as? LocalProcessTerminalView)?.process.terminate() }
        onClose?(self)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard !title.isEmpty else { return }
        item(for: source)?.label = String(title.prefix(30))
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [self] in
            guard let item = item(for: source) else { return }
            if let code = exitCode, code != 0 {
                source.feed(text: "\r\n\u{1b}[31m[exited with code \(code) — ⌘W closes this tab]\u{1b}[0m\r\n")
                return
            }
            close(item)
        }
    }

    func close(_ item: NSTabViewItem) {
        (item.view as? LocalProcessTerminalView)?.process.terminate()
        tabs.removeTabViewItem(item)
        if tabs.numberOfTabViewItems == 0 { window?.close() }
    }
}

// SwiftTerm ignores drops: paste dropped files' escaped paths like Terminal.app (Claude Code attaches image paths).
final class DropTerminalView: LocalProcessTerminalView {
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        let escaped = urls.map { $0.path.map { $0.isLetter || $0.isNumber || "_./-".contains($0) ? "\($0)" : "\\\($0)" }.joined() }
        pasteText(escaped.joined(separator: " ") + " ")
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var sessions: [Session] = []
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleDigit($0) == true ? nil : $0 }
        if !defaults.bool(forKey: "hideGuide") { showGuide(nil) }
        newSession(nil)
    }

    func handleDigit(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .control, event.charactersIgnoringModifiers == "n" {
            newTerminal(nil)
            return true
        }
        guard let n = Int(event.charactersIgnoringModifiers ?? ""), n >= 1, let key = NSApp.keyWindow else { return false }
        if mods == .command {
            let windows = key.tabbedWindows ?? [key]
            guard n <= windows.count else { return true }
            windows[n - 1].makeKeyAndOrderFront(nil)
            return true
        }
        if mods == .control, let tabs = current?.tabs {
            if n <= tabs.numberOfTabViewItems { tabs.selectTabViewItem(at: n - 1) }
            return true
        }
        return false
    }

    @objc func showGuide(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "AgentTabs"
        alert.informativeText = """
        Each top tab is one agent session in a folder. Inside it, a terminal tab (fish if installed) opens in the same folder.

        ⌘N          New agent session (pick folder + agent)
        ⌃N          New terminal in this session
        ⌘1…9       Switch session
        ⌃1…9       Switch terminal inside session
        ⌥⌘[ / ]    Previous / next terminal
        ⌘W          Close current tab (last one closes the session)
        ⇧⌘W        Close whole session

        The agent list is editable: type any command, e.g. "claude --resume".
        If ⌃1…9 does nothing, turn off "Switch to Desktop N" in System Settings › Keyboard › Shortcuts › Mission Control.
        """
        alert.showsSuppressionButton = sender == nil
        alert.suppressionButton?.title = "Don't show on start"
        alert.runModal()
        if alert.suppressionButton?.state == .on { defaults.set(true, forKey: "hideGuide") }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { newSession(nil) }
        return true
    }

    @objc func newWindowForTab(_ sender: Any?) { newSession(sender) }

    @objc func newSession(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Start Agent"
        panel.message = "Pick the working directory for the new agent session"
        if let last = defaults.string(forKey: "lastDir") { panel.directoryURL = URL(fileURLWithPath: last) }
        let field = NSComboBox()
        field.addItems(withObjectValues: ["claude", "claude --resume", "codex", "gemini", "opencode", "aider", "cursor-agent", "zsh"])
        field.stringValue = defaults.string(forKey: "agentCommand") ?? "claude"
        field.completes = true
        field.frame = NSRect(x: 0, y: 0, width: 400, height: 24)
        let label = NSTextField(labelWithString: "Agent:")
        let accessory = NSStackView(views: [label, field])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let command = field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? "claude" : field.stringValue
        defaults.set(dir.path, forKey: "lastDir")
        defaults.set(command, forKey: "agentCommand")

        let session = Session(dir: dir, command: command)
        session.onClose = { [weak self] s in self?.sessions.removeAll { $0 === s } }
        sessions.append(session)
        if let current = NSApp.keyWindow, let new = session.window {
            current.addTabbedWindow(new, ordered: .above)
        }
        session.showWindow(nil)
    }

    var current: Session? { sessions.first { $0.window === NSApp.keyWindow } }

    @objc func newTerminal(_ sender: Any?) {
        current?.addShell()
    }

    @objc func closeInner(_ sender: Any?) {
        if let s = current, let item = s.tabs.selectedTabViewItem { s.close(item) }
    }

    @objc func nextInner(_ sender: Any?) { current?.tabs.selectNextTabViewItem(nil) }
    @objc func prevInner(_ sender: Any?) { current?.tabs.selectPreviousTabViewItem(nil) }

    func buildMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let host = NSMenuItem()
            host.submenu = menu
            main.addItem(host)
            return menu
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        _ = submenu("AgentTabs", [item("Quit AgentTabs", #selector(NSApplication.terminate(_:)), "q")])
        _ = submenu("File", [
            item("New Agent Session…", #selector(newSession(_:)), "n"),
            item("New Terminal in Session", #selector(newTerminal(_:)), "n", [.control]),
            item("Next Inner Tab", #selector(nextInner(_:)), "]", [.command, .option]),
            item("Previous Inner Tab", #selector(prevInner(_:)), "[", [.command, .option]),
            .separator(),
            item("Close Tab", #selector(closeInner(_:)), "w"),
            item("Close Session", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
        ])
        _ = submenu("Edit", [
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        NSApp.windowsMenu = submenu("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
        NSApp.helpMenu = submenu("Help", [item("Shortcuts", #selector(showGuide(_:)), "/", [.command])])
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let focus = FocusManager()
    private let toggleItem = NSMenuItem(title: "Focus Mode", action: #selector(toggleFocus), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        toggleItem.target = self
        menu.addItem(toggleItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        focus.onChange = { [weak self] _ in self?.render() }
        // Re-read login item state each time the menu opens; the user may change it in System Settings.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: menu, queue: .main
        ) { [weak self] _ in self?.render() }
        render()
    }

    private func render() {
        let on = focus.isEnabled
        toggleItem.state = on ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let symbol = on ? "rectangle.inset.filled" : "rectangle.on.rectangle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Active Window")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = on ? "Focus Mode: on" : "Focus Mode: off"
    }

    @objc private func toggleFocus() {
        focus.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        render()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

import AppKit
import os.log

private let log = Logger(subsystem: "com.nick318.ActiveWindow", category: "focus")

/// Hides every other regular application whenever a new application becomes frontmost.
final class FocusManager {
    private let defaultsKey = "focusModeEnabled"
    private var observer: NSObjectProtocol?
    /// Incremented on each activation; stale scheduled passes compare against it and exit.
    private var generation = 0

    var onChange: ((Bool) -> Void)?

    private(set) var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    init() {
        if isEnabled { start() }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? start() : stop()
        onChange?(enabled)
    }

    private func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleActivation(of: app)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            handleActivation(of: front)
        }
    }

    private func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        generation += 1
    }

    private func handleActivation(of front: NSRunningApplication) {
        // Ignore Spotlight, menu bar helpers, and other non-window apps.
        guard front.activationPolicy == .regular else { return }
        generation += 1
        log.info("activated \(front.localizedName ?? "?", privacy: .public) hidden=\(front.isHidden) active=\(front.isActive)")
        settle(front, generation: generation, attempt: 0)
    }

    /// Waits until `front` is unhidden and active before hiding the others.
    ///
    /// With Focus Mode on, the previous frontmost app is the only visible app. If we hide it
    /// while the target is still marked hidden (Cmd+Tab to a hidden app), macOS sees zero
    /// visible apps and unhides Finder as a fallback. Waiting avoids that.
    private func settle(_ front: NSRunningApplication, generation gen: Int, attempt: Int) {
        guard gen == generation else { return }
        let ready = !front.isHidden && front.isActive
        if ready || attempt >= 20 {
            if !ready { log.info("gave up waiting for \(front.localizedName ?? "?", privacy: .public)") }
            hideOthers(except: front)
            // Second pass catches anything macOS unhid in the meantime (typically Finder).
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                guard let self, gen == self.generation, front.isActive else { return }
                self.hideOthers(except: front)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
            self?.settle(front, generation: gen, attempt: attempt + 1)
        }
    }

    private func hideOthers(except front: NSRunningApplication) {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != front.processIdentifier,
                  app.processIdentifier != me,
                  !app.isHidden
            else { continue }
            log.info("hide \(app.localizedName ?? "?", privacy: .public)")
            app.hide()
        }
    }
}

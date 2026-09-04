import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var panel: PanelController?
    private var statusItem: StatusItemController?
    private var hotkey: HotkeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()

        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.close() }

        let state = AppState()
        let panel = PanelController(state: state)
        let statusItem = StatusItemController(state: state, panel: panel)

        let hotkey = HotkeyService(
            identifier: HotkeyService.toggleID,
            keyCode: state.settings.hotkeyKeyCode,
            modifiers: state.settings.hotkeyModifiers
        ) {
            panel.toggle()
        }
        hotkey.register()

        state.onHotkeyChange = { [weak hotkey, weak state] in
            guard let state else { return }
            hotkey?.register(keyCode: state.settings.hotkeyKeyCode, modifiers: state.settings.hotkeyModifiers)
        }

        state.start()

        self.appState = state
        self.panel = panel
        self.statusItem = statusItem
        self.hotkey = hotkey
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.toggle()
        return false
    }

    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != pid }
        guard !others.isEmpty else { return }

        others.forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}

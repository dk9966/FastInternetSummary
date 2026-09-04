import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let state: AppState
    private weak var statusButton: NSStatusBarButton?
    private var escapeMonitor: Any?
    private var isPresented = false

    init(state: AppState) {
        self.state = state
        super.init()

        let hosting = NSHostingController(rootView: RootPanel(state: state))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        state.onClosePanel = { [weak self] in
            self?.close()
        }
    }

    func attach(button: NSStatusBarButton) {
        statusButton = button
    }

    func toggle() {
        if isPresented {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard !isPresented, let button = statusButton else { return }
        isPresented = true
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        installEscapeMonitor()
        state.speedTest.run()
    }

    func close() {
        guard isPresented else { return }
        isPresented = false
        popover.performClose(nil)
        statusButton?.highlight(false)
        state.isShowingSettings = false
        removeEscapeMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        isPresented = false
        statusButton?.highlight(false)
        state.isShowingSettings = false
        state.speedTest.cancel()
        removeEscapeMonitor()
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }
}

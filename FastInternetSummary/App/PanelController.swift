import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let state: AppState
    private weak var statusButton: NSStatusBarButton?
    private var escapeMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var screenParamsObserver: NSObjectProtocol?
    private var isPresented = false
    private var positioningWindow: NSWindow?
    private var trailingOffset: CGFloat = 120

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
        cacheTrailingOffsetIfSettled()
    }

    func toggle() {
        if isPresented || popover.isShown {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard !isPresented, !popover.isShown else { return }

        let mouse = NSEvent.mouseLocation
        cacheTrailingOffsetIfSettled()
        guard let screen = screenContaining(mouse) else { return }

        isPresented = true
        guard let view = placePositioningWindow(on: screen) else {
            isPresented = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.animates = true
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)

        if !popover.isShown {
            isPresented = false
            hidePositioningWindow()
            return
        }

        statusButton?.highlight(true)
        installEscapeMonitor()
        installScreenFollowMonitors()
        state.runSpeedTest()
    }

    func close() {
        guard isPresented || popover.isShown else { return }
        isPresented = false
        popover.performClose(nil)
        statusButton?.highlight(false)
        state.isShowingSettings = false
        hidePositioningWindow()
        removeEscapeMonitor()
        removeScreenFollowMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        isPresented = false
        statusButton?.highlight(false)
        state.isShowingSettings = false
        state.speedTest.cancel()
        hidePositioningWindow()
        removeEscapeMonitor()
        removeScreenFollowMonitors()
    }

    private func followMouseScreen() {
        guard isPresented, popover.isShown else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = screenContaining(mouse) else { return }
        if let current = screenContaining(positioningCenter), current.frame.equalTo(screen.frame) {
            return
        }
        popover.animates = false
        if let view = placePositioningWindow(on: screen) {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        popover.animates = true
    }

    @discardableResult
    private func placePositioningWindow(on screen: NSScreen) -> NSView? {
        let window = makePositioningWindow()
        window.setFrame(positioningFrame(on: screen), display: true)
        window.orderFront(nil)
        return window.contentView
    }

    private func positioningFrame(on screen: NSScreen) -> NSRect {
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 1)
        let x = settledStatusButtonMidX(on: screen) ?? (screen.frame.maxX - trailingOffset)
        let clampedX = min(max(x, screen.frame.minX + 8), screen.frame.maxX - 8)
        return NSRect(x: clampedX, y: screen.visibleFrame.maxY, width: 1, height: menuBarHeight)
    }

    private func settledStatusButtonMidX(on screen: NSScreen) -> CGFloat? {
        guard let rect = statusButtonScreenRect() else { return nil }
        let mid = NSPoint(x: rect.midX, y: rect.midY)
        guard NSMouseInRect(mid, screen.frame, false) else { return nil }
        return rect.midX
    }

    private func cacheTrailingOffsetIfSettled() {
        guard let rect = statusButtonScreenRect() else { return }
        let mid = NSPoint(x: rect.midX, y: rect.midY)
        guard let screen = screenContaining(mid) else { return }
        trailingOffset = screen.frame.maxX - rect.midX
    }

    private func statusButtonScreenRect() -> NSRect? {
        guard let button = statusButton, let window = button.window else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard rect.width > 1, rect.height > 1 else { return nil }
        return rect
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
    }

    private var positioningCenter: NSPoint {
        let frame = positioningWindow?.frame ?? .zero
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    /// Invisible window in the target display's menu bar. Never attach the
    /// popover to the real status button: that button jumps between menu bars
    /// when you click another display, and the popover rides the jump through
    /// a wrong coordinate before it settles.
    private func makePositioningWindow() -> NSWindow {
        if let positioningWindow { return positioningWindow }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        positioningWindow = window
        return window
    }

    private func hidePositioningWindow() {
        positioningWindow?.orderOut(nil)
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

    private func installScreenFollowMonitors() {
        removeScreenFollowMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.followMouseScreen()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.followMouseScreen()
        }
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followMouseScreen()
            }
        }
    }

    private func removeScreenFollowMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
            self.screenParamsObserver = nil
        }
    }
}

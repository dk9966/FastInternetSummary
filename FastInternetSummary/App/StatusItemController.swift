import AppKit
import Observation

@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let state: AppState
    private let panel: PanelController
    private let quitMenu: NSMenu

    init(state: AppState, panel: PanelController) {
        self.state = state
        self.panel = panel
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        quitMenu = NSMenu()
        quitMenu.addItem(
            NSMenuItem(title: "Quit Fast Internet Summary", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        super.init()

        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        button.image = Self.makeImage(named: "network")
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Fast Internet Summary"
        panel.attach(button: button)
        refresh()
        observe()
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else {
            panel.toggle()
            return
        }

        if event.type == .rightMouseUp {
            if let button = item.button {
                quitMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            }
            return
        }

        panel.toggle()
    }

    private func observe() {
        withObservationTracking {
            _ = state.snapshot
            _ = state.rates
            _ = state.settings.showLiveRatesInMenuBar
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observe()
            }
        }
    }

    private func refresh() {
        guard let button = item.button else { return }
        button.image = Self.makeImage(named: symbolName)

        if state.settings.showLiveRatesInMenuBar {
            let down = ByteRateFormat.compact(bytesPerSecond: state.rates.downloadBytesPerSecond)
            let up = ByteRateFormat.compact(bytesPerSecond: state.rates.uploadBytesPerSecond)
            button.title = " \(down)↓ \(up)↑"
        } else {
            button.title = ""
        }
    }

    private var symbolName: String {
        if !state.snapshot.hasInternet, state.snapshot.inUseKind != nil || state.snapshot.wifi.status == .noInternet || state.snapshot.ethernet.status == .noInternet {
            return "exclamationmark.triangle"
        }
        switch state.snapshot.inUseKind {
        case .wifi:
            return "wifi"
        case .ethernet:
            return "cable.connector"
        case nil:
            return "network"
        }
    }

    private static func makeImage(named symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Fast Internet Summary")
        image?.isTemplate = true
        return image
    }
}

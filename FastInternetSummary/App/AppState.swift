import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var snapshot = NetworkSnapshot.empty
    var rates = LiveRates.pending
    var settings = AppSettings()
    var speedTest = SpeedTestRunner()
    var isShowingSettings = false
    var launchAtLogin = LoginItemService.isEnabled

    var onHotkeyChange: (() -> Void)?
    var onClosePanel: (() -> Void)?
    private(set) var isPanelOpen = false

    private let routeMonitor = RouteMonitor()
    private let sampler = ByteRateSampler()
    private var needsPathRerun = false
    private var pathRerunTask: Task<Void, Never>?

    func start() {
        sampler.onTick = { [weak self] rates in
            self?.rates = rates
        }
        sampler.setInterval(settings.sampleInterval)
        sampler.start()

        routeMonitor.onChange { [weak self] snapshot in
            Task { @MainActor in
                self?.apply(snapshot)
            }
        }
        routeMonitor.start()
    }

    func apply(_ snapshot: NetworkSnapshot) {
        let previous = self.snapshot
        self.snapshot = snapshot
        sampler.setInterface(snapshot.activeInterfaceName)
        warmOoklaIfNeeded()
        considerPathRerun(from: previous, to: snapshot)
    }

    func setPanelOpen(_ open: Bool) {
        isPanelOpen = open
        if !open {
            pathRerunTask?.cancel()
            pathRerunTask = nil
        }
    }

    func setSampleInterval(_ interval: TimeInterval) {
        settings.sampleInterval = interval
        sampler.setInterval(interval)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
        } catch {
            // Status is re-read below so the toggle reflects the system.
        }
        launchAtLogin = LoginItemService.isEnabled
    }

    func refreshLoginItem() {
        launchAtLogin = LoginItemService.isEnabled
    }

    func setHotkey(keyCode: UInt32, modifiers: UInt32) {
        settings.hotkeyKeyCode = keyCode
        settings.hotkeyModifiers = modifiers
        onHotkeyChange?()
    }

    func setUseOoklaSpeedTest(_ enabled: Bool) {
        settings.useOoklaSpeedTest = enabled
        warmOoklaIfNeeded()
    }

    func runSpeedTest() {
        needsPathRerun = false
        pathRerunTask?.cancel()
        pathRerunTask = nil
        if settings.useOoklaSpeedTest {
            let key = OoklaNearbyServer.networkKey(from: snapshot)
            speedTest.run(sequential: true, using: OoklaSpeedTestProvider(networkKey: key))
        } else {
            speedTest.run(sequential: !settings.simultaneousSpeedTest)
        }
    }

    // Panel open and the path in use changed (ethernet unplug → wifi): wait for
    // the route to settle, then start a fresh test on the new path.
    private func considerPathRerun(from previous: NetworkSnapshot, to snapshot: NetworkSnapshot) {
        let pathChanged = !snapshot.isSamePath(as: previous)
        if pathChanged {
            needsPathRerun = true
        }

        let internetCameBack = !previous.hasInternet && snapshot.hasInternet
        guard needsPathRerun, isPanelOpen else { return }
        guard pathChanged || internetCameBack else { return }
        guard snapshot.hasInternet else { return }

        pathRerunTask?.cancel()
        pathRerunTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let self, self.isPanelOpen, self.needsPathRerun, self.snapshot.hasInternet else { return }
            self.runSpeedTest()
        }
    }

    private func warmOoklaIfNeeded() {
        guard settings.useOoklaSpeedTest, snapshot.hasInternet, OoklaCLI.isAvailable else { return }
        OoklaNearbyServer.warm(networkKey: OoklaNearbyServer.networkKey(from: snapshot))
    }

    func closePanel() {
        onClosePanel?()
    }
}

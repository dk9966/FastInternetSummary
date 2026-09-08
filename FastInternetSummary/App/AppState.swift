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

    private let routeMonitor = RouteMonitor()
    private let sampler = ByteRateSampler()

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
        self.snapshot = snapshot
        sampler.setInterface(snapshot.activeInterfaceName)
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

    func runSpeedTest() {
        if settings.useOoklaSpeedTest {
            speedTest.run(sequential: true, using: OoklaSpeedTestProvider())
        } else {
            speedTest.run(sequential: !settings.simultaneousSpeedTest)
        }
    }

    func closePanel() {
        onClosePanel?()
    }
}

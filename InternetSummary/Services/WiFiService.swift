import CoreWLAN
import Foundation

struct WiFiInfo: Sendable, Equatable {
    var interfaceName: String?
    var isPowered: Bool
    var isAssociated: Bool
    var ssid: String?
}

final class WiFiService: NSObject, CWEventDelegate, @unchecked Sendable {
    private let client = CWWiFiClient.shared()
    private let lock = NSLock()
    private var changeHandler: (@Sendable () -> Void)?

    override init() {
        super.init()
        client.delegate = self
        startMonitoring()
    }

    deinit {
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
    }

    func onChange(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func current() -> WiFiInfo {
        guard let iface = client.interface() else {
            return WiFiInfo(interfaceName: nil, isPowered: false, isAssociated: false, ssid: nil)
        }

        let powered = iface.powerOn()
        let mode = iface.interfaceMode()
        let associated = powered && (mode == .station || iface.serviceActive() || iface.ssid() != nil)
        let ssid = sanitizedSSID(iface.ssid())

        return WiFiInfo(
            interfaceName: iface.interfaceName,
            isPowered: powered,
            isAssociated: associated,
            ssid: ssid
        )
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        notify()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        notify()
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        notify()
    }

    func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        notify()
    }

    private func startMonitoring() {
        let events: [CWEventType] = [.ssidDidChange, .linkDidChange, .powerDidChange, .modeDidChange]
        for event in events {
            try? client.startMonitoringEvent(with: event)
        }
    }

    private func notify() {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?()
    }

    private func sanitizedSSID(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw != "<redacted>" else { return nil }
        return raw
    }
}

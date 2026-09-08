import Foundation
import Network
import SystemConfiguration

final class RouteMonitor: @unchecked Sendable {
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.danielku.FastInternetSummary.route")
    private let wifi = WiFiService()
    private var store: SCDynamicStore?
    private var handler: (@Sendable (NetworkSnapshot) -> Void)?

    func onChange(_ handler: @escaping @Sendable (NetworkSnapshot) -> Void) {
        self.handler = handler
    }

    func start() {
        wifi.onChange { [weak self] in
            self?.publish()
        }

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            self?.publish()
        }
        pathMonitor.start(queue: queue)

        startStore()
        publish()
    }

    func stop() {
        pathMonitor.cancel()
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        store = nil
    }

    private func startStore() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<RouteMonitor>.fromOpaque(info).takeUnretainedValue().publish()
        }

        guard let store = SCDynamicStoreCreate(
            nil,
            "com.danielku.FastInternetSummary" as CFString,
            callback,
            &context
        ) else {
            return
        }

        let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] as CFArray
        let patterns = ["State:/Network/Interface/.*/Link"] as CFArray
        SCDynamicStoreSetNotificationKeys(store, keys, patterns)
        SCDynamicStoreSetDispatchQueue(store, queue)
        self.store = store
    }

    private func publish() {
        let snapshot = Self.build(path: pathMonitor.currentPath, wifi: wifi.current())
        handler?(snapshot)
    }

    static func build(path: NWPath, wifi: WiFiInfo) -> NetworkSnapshot {
        let classified = classifiedInterfaces()
        let ethernetNames = classified.filter { $0.kind == .ethernet }.map(\.name)
        let wifiNames = classified.filter { $0.kind == .wifi }.map(\.name)
        let primary = primaryInterfaceName()

        let wifiName = wifi.interfaceName ?? wifiNames.first
        let ethernetName = ethernetNames.first(where: { InterfaceCounters.isUp($0) }) ?? ethernetNames.first

        let ethernetUp = ethernetNames.contains { InterfaceCounters.isUp($0) }
        let wifiUp = wifi.isAssociated
            || (wifiName.map { InterfaceCounters.isUp($0) } ?? false)
            || path.usesInterfaceType(.wifi)

        let physicalInUse: ConnectionKind? = inUseKind(
            primary: primary,
            ethernetNames: ethernetNames,
            wifiNames: wifiNames,
            path: path
        )

        let hasInternet = path.status == .satisfied

        let ethernetStatus = status(kind: .ethernet, connected: ethernetUp, inUse: physicalInUse, hasInternet: hasInternet)
        let wifiStatus = status(kind: .wifi, connected: wifiUp, inUse: physicalInUse, hasInternet: hasInternet)

        let activeForRates = samplingInterface(
            primary: primary,
            physicalInUse: physicalInUse,
            ethernetNames: ethernetNames,
            wifiName: wifiName
        )

        let speed = ethernetUp ? ethernetName.flatMap { LinkSpeedService.displayString(for: $0) } : nil

        return NetworkSnapshot(
            ethernet: InterfaceInfo(
                kind: .ethernet,
                interfaceName: ethernetName,
                status: ethernetStatus,
                ssid: nil,
                linkSpeed: speed
            ),
            wifi: InterfaceInfo(
                kind: .wifi,
                interfaceName: wifiName,
                status: wifiStatus,
                ssid: wifi.ssid,
                linkSpeed: nil
            ),
            activeInterfaceName: activeForRates,
            hasInternet: hasInternet
        )
    }

    private struct ClassifiedInterface {
        var name: String
        var kind: ConnectionKind
    }

    private static func classifiedInterfaces() -> [ClassifiedInterface] {
        guard let list = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }

        return list.compactMap { interface in
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
            let kind: ConnectionKind?
            if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                kind = .wifi
            } else if type == (kSCNetworkInterfaceTypeEthernet as String) {
                kind = .ethernet
            } else {
                kind = nil
            }
            guard let kind else { return nil }
            return ClassifiedInterface(name: name, kind: kind)
        }
    }

    private static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "com.danielku.FastInternetSummary.primary" as CFString, nil, nil) else {
            return nil
        }
        if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let name = ipv4["PrimaryInterface"] as? String {
            return name
        }
        if let ipv6 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any],
           let name = ipv6["PrimaryInterface"] as? String {
            return name
        }
        return nil
    }

    private static func inUseKind(
        primary: String?,
        ethernetNames: [String],
        wifiNames: [String],
        path: NWPath
    ) -> ConnectionKind? {
        if let primary {
            if ethernetNames.contains(primary) { return .ethernet }
            if wifiNames.contains(primary) { return .wifi }
        }

        if path.status == .satisfied {
            if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
            if path.usesInterfaceType(.wifi) { return .wifi }
        } else if let primary {
            // VPN or unknown primary: prefer the path's physical types if any are up.
            if ethernetNames.contains(where: { InterfaceCounters.isUp($0) }), path.availableInterfaces.contains(where: { $0.type == .wiredEthernet }) {
                return .ethernet
            }
            if wifiNames.contains(where: { InterfaceCounters.isUp($0) }), path.availableInterfaces.contains(where: { $0.type == .wifi }) {
                return .wifi
            }
            _ = primary
        }

        if let preferred = path.availableInterfaces.first {
            if preferred.type == .wiredEthernet { return .ethernet }
            if preferred.type == .wifi { return .wifi }
        }

        return nil
    }

    private static func status(
        kind: ConnectionKind,
        connected: Bool,
        inUse: ConnectionKind?,
        hasInternet: Bool
    ) -> LinkStatus {
        guard connected else { return .disconnected }
        if inUse == kind {
            return hasInternet ? .inUse : .noInternet
        }
        return .connected
    }

    private static func samplingInterface(
        primary: String?,
        physicalInUse: ConnectionKind?,
        ethernetNames: [String],
        wifiName: String?
    ) -> String? {
        if let primary, InterfaceCounters.isUp(primary) {
            return primary
        }
        if physicalInUse == .ethernet {
            return ethernetNames.first(where: { InterfaceCounters.isUp($0) })
        }
        if physicalInUse == .wifi {
            return wifiName
        }
        return nil
    }
}

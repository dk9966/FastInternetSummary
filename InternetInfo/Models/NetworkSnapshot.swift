import Foundation

enum ConnectionKind: String, Sendable, Equatable {
    case ethernet
    case wifi

    var title: String {
        switch self {
        case .ethernet: "Ethernet"
        case .wifi: "Wi‑Fi"
        }
    }

    var symbolName: String {
        switch self {
        case .ethernet: "cable.connector"
        case .wifi: "wifi"
        }
    }
}

enum LinkStatus: Sendable, Equatable {
    case disconnected
    case connected
    case inUse
    case noInternet

    var isForeground: Bool {
        self == .inUse || self == .noInternet
    }
}

struct InterfaceInfo: Sendable, Equatable {
    var kind: ConnectionKind
    var interfaceName: String?
    var status: LinkStatus
    var ssid: String?
    var linkSpeed: String?

    func detailLine() -> String {
        var parts: [String] = []

        if kind == .wifi, let ssid, !ssid.isEmpty {
            parts.append("“\(ssid)”")
        }

        switch status {
        case .disconnected:
            parts.append("Disconnected")
        case .connected:
            parts.append("Connected, not in use")
        case .inUse:
            parts.append("Connected")
            parts.append("In use")
        case .noInternet:
            parts.append("No internet")
        }

        if let linkSpeed, status != .disconnected {
            parts.append(linkSpeed)
        }

        return parts.joined(separator: " · ")
    }
}

struct NetworkSnapshot: Sendable, Equatable {
    var ethernet: InterfaceInfo
    var wifi: InterfaceInfo
    /// BSD name used for live byte-rate sampling (default route).
    var activeInterfaceName: String?
    var hasInternet: Bool

    static let empty = NetworkSnapshot(
        ethernet: InterfaceInfo(kind: .ethernet, interfaceName: nil, status: .disconnected, ssid: nil, linkSpeed: nil),
        wifi: InterfaceInfo(kind: .wifi, interfaceName: nil, status: .disconnected, ssid: nil, linkSpeed: nil),
        activeInterfaceName: nil,
        hasInternet: false
    )

    var ordered: (primary: InterfaceInfo, secondary: InterfaceInfo) {
        if ethernet.status.isForeground {
            return (ethernet, wifi)
        }
        if wifi.status.isForeground {
            return (wifi, ethernet)
        }
        if wifi.status != .disconnected, ethernet.status == .disconnected {
            return (wifi, ethernet)
        }
        return (ethernet, wifi)
    }

    var inUseKind: ConnectionKind? {
        if ethernet.status == .inUse { return .ethernet }
        if wifi.status == .inUse { return .wifi }
        return nil
    }
}

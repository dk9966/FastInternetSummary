import Foundation

enum LinkSpeedService {
    static func displayString(for interfaceName: String) -> String? {
        let mbps = interfaceName.withCString { IIEthernetLinkSpeedMbps($0) }
        guard mbps > 0 else { return nil }
        return format(mbps: Int(mbps))
    }

    static func format(mbps: Int) -> String {
        if mbps >= 1000 {
            let gbps = Double(mbps) / 1000.0
            if gbps.rounded() == gbps {
                return "\(Int(gbps)) Gbps"
            }
            return String(format: "%g Gbps", gbps)
        }
        return "\(mbps) Mbps"
    }
}

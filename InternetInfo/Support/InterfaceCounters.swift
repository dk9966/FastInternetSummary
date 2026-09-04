import Foundation

enum InterfaceCounters {
    static func bytes(for name: String) -> (in: UInt64, out: UInt64)? {
        var ibytes: UInt64 = 0
        var obytes: UInt64 = 0
        let ok = name.withCString { IIInterfaceBytes($0, &ibytes, &obytes) }
        guard ok else { return nil }
        return (ibytes, obytes)
    }

    static func isUp(_ name: String) -> Bool {
        name.withCString { IIInterfaceIsUp($0) }
    }
}

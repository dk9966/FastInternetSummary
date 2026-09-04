import Foundation

struct LiveRates: Sendable, Equatable {
    /// Bytes per second inbound, or nil until two samples exist.
    var downloadBytesPerSecond: Double?
    var uploadBytesPerSecond: Double?

    static let pending = LiveRates(downloadBytesPerSecond: nil, uploadBytesPerSecond: nil)

    var isPending: Bool {
        downloadBytesPerSecond == nil || uploadBytesPerSecond == nil
    }
}

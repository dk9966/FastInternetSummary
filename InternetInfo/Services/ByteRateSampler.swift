import Foundation

@MainActor
final class ByteRateSampler {
    var onTick: ((LiveRates) -> Void)?

    private var timer: Timer?
    private var interfaceName: String?
    private var previous: (incoming: UInt64, outgoing: UInt64, date: Date)?
    private var interval: TimeInterval = 1

    func setInterface(_ name: String?) {
        guard name != interfaceName else { return }
        interfaceName = name
        previous = nil
        onTick?(LiveRates.pending)
    }

    func setInterval(_ interval: TimeInterval) {
        let clamped = max(1, interval)
        guard clamped != self.interval else { return }
        self.interval = clamped
        start()
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        timer.tolerance = min(0.2, interval / 5)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        guard let interfaceName, let counters = InterfaceCounters.bytes(for: interfaceName) else {
            previous = nil
            onTick?(LiveRates.pending)
            return
        }

        let now = Date()
        if let previous {
            let delta = now.timeIntervalSince(previous.date)
            if delta >= 0.4 {
                let down = wrappedDelta(new: counters.in, old: previous.incoming) / delta
                let up = wrappedDelta(new: counters.out, old: previous.outgoing) / delta
                onTick?(LiveRates(downloadBytesPerSecond: down, uploadBytesPerSecond: up))
            }
        }

        previous = (counters.in, counters.out, now)
    }

    private func wrappedDelta(new: UInt64, old: UInt64) -> Double {
        if new >= old {
            return Double(new - old)
        }
        return Double(new + UInt64(UInt32.max) + 1 - old)
    }
}

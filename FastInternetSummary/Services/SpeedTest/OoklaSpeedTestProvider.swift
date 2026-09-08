import Foundation

/// Locates the official Ookla CLI. A menu-bar app does not inherit the user's
/// Homebrew PATH, so we look at the two standard prefix locations.
enum OoklaCLI {
    static var isAvailable: Bool { executablePath != nil }

    static var executablePath: String? {
        ["/opt/homebrew/bin/speedtest", "/usr/local/bin/speedtest"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func isRateLimitText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("too many requests") || lowered.contains("limit reached")
    }

    static func isRateLimitOutput(_ output: CommandOutput) -> Bool {
        let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
        let stdout = String(data: output.stdout, encoding: .utf8) ?? ""
        return isRateLimitText(stderr) || isRateLimitText(stdout)
    }
}

/// Ookla does not publish the CLI limit. Overlapping launches can trip a
/// block in seconds; ~30–40 tests at once a minute can trip an hour block.
/// One process at a time, a tiny debounce, and a cap well under that.
/// Every CLI launch counts, including nearby-server prefetch (`-L`).
enum OoklaLaunchBudget {
    static let minInterval: TimeInterval = 2
    static let hourWindow: TimeInterval = 60 * 60
    static let hourMax = 40
    /// Prefetch leaves these slots so a real test can still run this hour.
    static let prefetchReserve = 2

    private static let timesKey = "ookla.launchTimes"
    private static let lock = NSLock()

    static func canLaunch(reserving extraSlots: Int = 0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allows(prunedTimes(), reserving: extraSlots)
    }

    static func underHourCap() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return prunedTimes().count < hourMax
    }

    static func record() {
        lock.lock()
        defer { lock.unlock() }
        var times = prunedTimes()
        times.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(times, forKey: timesKey)
    }

    private static func prunedTimes() -> [TimeInterval] {
        let now = Date().timeIntervalSince1970
        let stored = UserDefaults.standard.array(forKey: timesKey) as? [TimeInterval] ?? []
        return stored.filter { now - $0 < hourWindow }
    }

    private static func allows(_ times: [TimeInterval], reserving extraSlots: Int) -> Bool {
        let now = Date().timeIntervalSince1970
        if let last = times.last, now - last < minInterval { return false }
        if times.count + extraSlots >= hourMax { return false }
        return true
    }
}

/// Last nearby server we can skip shopping for. Prefetch and finished tests
/// both write this. A stale pin is still used for a test; refresh is background.
enum OoklaServerPin {
    static let timeToLive: TimeInterval = 30 * 60

    private static let idKey = "ookla.pinnedServerID"
    private static let networkKeyKey = "ookla.pinnedNetworkKey"
    private static let atKey = "ookla.pinnedAt"
    private static let lock = NSLock()

    static func id(for networkKey: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard UserDefaults.standard.object(forKey: idKey) != nil else { return nil }
        if let storedKey = UserDefaults.standard.string(forKey: networkKeyKey), storedKey != networkKey {
            return nil
        }
        return UserDefaults.standard.integer(forKey: idKey)
    }

    static func needsRefresh(for networkKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard UserDefaults.standard.object(forKey: idKey) != nil else { return true }
        if let storedKey = UserDefaults.standard.string(forKey: networkKeyKey), storedKey != networkKey {
            return true
        }
        guard let pinnedAt = UserDefaults.standard.object(forKey: atKey) as? TimeInterval else {
            return false
        }
        return Date().timeIntervalSince1970 - pinnedAt >= timeToLive
    }

    static func store(id: Int, networkKey: String) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(id, forKey: idKey)
        UserDefaults.standard.set(networkKey, forKey: networkKeyKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: networkKeyKey)
        UserDefaults.standard.removeObject(forKey: atKey)
    }
}

actor OoklaCLIGate {
    static let shared = OoklaCLIGate()
    private var locked = false
    private var waiters = 0

    func acquire() async throws {
        waiters += 1
        defer { waiters -= 1 }
        while locked {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(50))
        }
        while !OoklaLaunchBudget.canLaunch() {
            try Task.checkCancellation()
            guard OoklaLaunchBudget.underHourCap() else {
                throw SpeedTestError.skipped
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        locked = true
        OoklaLaunchBudget.record()
    }

    /// Nearby-list prefetch. Same budget as a test, but it never waits, never
    /// cuts in front of a waiting test, and never takes the last hour slots.
    func tryAcquireForPrefetch() -> Bool {
        if locked || waiters > 0 { return false }
        guard OoklaLaunchBudget.canLaunch(reserving: OoklaLaunchBudget.prefetchReserve) else {
            return false
        }
        locked = true
        OoklaLaunchBudget.record()
        return true
    }

    func release() {
        locked = false
    }
}

/// Background `speedtest -L`. Never called from the test path: a cold shortcut
/// runs without `--server-id` rather than spending a second launch at click time.
enum OoklaNearbyServer {
    static func networkKey(from snapshot: NetworkSnapshot) -> String {
        if snapshot.wifi.status == .inUse, let ssid = snapshot.wifi.ssid, !ssid.isEmpty {
            return "wifi:\(ssid)"
        }
        if let name = snapshot.activeInterfaceName, !name.isEmpty {
            return "if:\(name)"
        }
        return "default"
    }

    static func warm(networkKey: String) {
        Task {
            await Store.shared.warm(networkKey: networkKey)
        }
    }

    private actor Store {
        static let shared = Store()
        private var inFlight = false

        func warm(networkKey: String) async {
            guard OoklaCLI.executablePath != nil else { return }
            guard OoklaServerPin.needsRefresh(for: networkKey) else { return }
            guard !inFlight else { return }
            inFlight = true
            defer { inFlight = false }

            guard await OoklaCLIGate.shared.tryAcquireForPrefetch() else { return }
            defer {
                Task { await OoklaCLIGate.shared.release() }
            }

            guard let serverID = await Self.fetchNearestID() else { return }
            OoklaServerPin.store(id: serverID, networkKey: networkKey)
        }

        private static func fetchNearestID() async -> Int? {
            guard let executable = OoklaCLI.executablePath else { return nil }
            do {
                let output = try await CommandRunner.runStreaming(
                    executable: executable,
                    arguments: ["--accept-license", "--accept-gdpr", "--format=jsonl", "--servers"],
                    timeout: 15
                ) { _ in }
                if OoklaCLI.isRateLimitOutput(output) {
                    return nil
                }
                return parseNearestID(output.stdout)
            } catch {
                return nil
            }
        }

        private static func parseNearestID(_ data: Data) -> Int? {
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            if let id = decode(text) { return id }
            for line in text.split(whereSeparator: \.isNewline) {
                if let id = decode(String(line)) { return id }
            }
            if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
                return decode(String(text[start...end]))
            }
            return nil
        }

        private static func decode(_ text: String) -> Int? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8) else { return nil }
            if let list = try? JSONDecoder().decode(ServerList.self, from: data),
               let id = list.servers?.compactMap(\.id).first {
                return id
            }
            if let items = try? JSONDecoder().decode([ServerList.Item].self, from: data),
               let id = items.compactMap(\.id).first {
                return id
            }
            return nil
        }
    }

    private struct ServerList: Decodable {
        var servers: [Item]?

        struct Item: Decodable {
            var id: Int?
        }
    }
}

/// Optional provider. The app still ships with Apple's `networkQuality` as the default.
struct OoklaSpeedTestProvider: SpeedTestProvider {
    var name: String { "speedtest" }
    var networkKey: String = "default"

    func run(sequential _: Bool, progress: @escaping @Sendable (SpeedTestProgress) async -> Void) async throws -> SpeedTestResult {
        guard let executable = OoklaCLI.executablePath else {
            throw SpeedTestError.failed(
                "Speedtest CLI is not installed. Install it with brew tap teamookla/speedtest && brew install speedtest."
            )
        }

        try await OoklaCLIGate.shared.acquire()
        defer {
            Task { await OoklaCLIGate.shared.release() }
        }
        return try await execute(
            executable: executable,
            progress: progress
        )
    }

    private func execute(
        executable: String,
        progress: @escaping @Sendable (SpeedTestProgress) async -> Void
    ) async throws -> SpeedTestResult {
        var arguments = [
            "--accept-license",
            "--accept-gdpr",
            "--format=jsonl",
            "--progress-update-interval=200"
        ]
        if let serverID = OoklaServerPin.id(for: networkKey) {
            arguments.append("--server-id=\(serverID)")
        }
        try Task.checkCancellation()

        let parser = OoklaStreamParser()

        let output = try await CommandRunner.runStreaming(
            executable: executable,
            arguments: arguments,
            timeout: 120
        ) { chunk in
            if let update = parser.ingest(chunk) {
                Task {
                    await progress(update)
                }
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        if let serverID = parser.selectedServerID {
            OoklaServerPin.store(id: serverID, networkKey: networkKey)
        }

        let latest = parser.finish() ?? parser.current ?? SpeedTestProgress()

        if OoklaCLI.isRateLimitOutput(output) || (parser.lastError.map(OoklaCLI.isRateLimitText) ?? false) {
            throw SpeedTestError.skipped
        }

        guard output.status == 0 || latest.downloadMbps != nil else {
            OoklaServerPin.clear()
            throw SpeedTestError.skipped
        }

        guard let downloadMbps = latest.downloadMbps, let uploadMbps = latest.uploadMbps else {
            throw SpeedTestError.skipped
        }

        let final = SpeedTestProgress(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            latencyMs: latest.latencyMs,
            downloadLatencyMs: latest.downloadLatencyMs,
            uploadLatencyMs: latest.uploadLatencyMs,
            fractionComplete: 1,
            isFinal: true
        )
        await progress(final)

        return SpeedTestResult(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            latencyMs: latest.latencyMs,
            downloadLatencyMs: latest.downloadLatencyMs,
            uploadLatencyMs: latest.uploadLatencyMs,
            testedAt: .now,
            source: name
        )
    }
}

final class OoklaStreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private(set) var current: SpeedTestProgress?
    private(set) var lastError: String?
    private(set) var selectedServerID: Int?

    func ingest(_ chunk: String) -> SpeedTestProgress? {
        lock.lock()
        defer { lock.unlock() }
        if lastError == nil, OoklaCLI.isRateLimitText(chunk) {
            lastError = chunk
        }
        pending += chunk
        return drain(flushRemainder: false)
    }

    func finish() -> SpeedTestProgress? {
        lock.lock()
        defer { lock.unlock() }
        return drain(flushRemainder: true)
    }

    private func drain(flushRemainder: Bool) -> SpeedTestProgress? {
        var changed = false
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending = String(pending[pending.index(after: newline)...])
            if apply(line) {
                changed = true
            }
        }
        if flushRemainder, apply(pending) {
            pending = ""
            changed = true
        }
        return changed ? current : nil
    }

    private func apply(_ rawLine: String) -> Bool {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("{"), let data = line.data(using: .utf8) else {
            return false
        }
        guard let event = try? JSONDecoder().decode(Event.self, from: data) else {
            return false
        }

        if let id = event.server?.id {
            selectedServerID = id
        }

        if event.type == "log", event.level == "error" {
            lastError = event.message?.nilIfEmpty
            return false
        }

        var next = current ?? SpeedTestProgress()
        var changed = false

        switch event.type {
        case "testStart":
            return false
        case "ping":
            if let ms = event.ping?.latency?.value {
                next.latencyMs = ms
                changed = true
            }
            next.fractionComplete = overallProgress(stage: 0, fraction: event.ping?.progress?.value ?? 0)
        case "download":
            if next.liveStage != .download {
                next.liveStage = .download
                changed = true
            }
            if let mbps = mbps(fromBytesPerSecond: event.download?.bandwidth?.value), mbps > 0.05 {
                next.downloadMbps = mbps
                changed = true
            }
            if let ms = event.download?.latency?.iqm?.value, ms > 0 {
                next.downloadLatencyMs = ms
                changed = true
            }
            next.fractionComplete = overallProgress(stage: 1, fraction: event.download?.progress?.value ?? 0)
        case "upload":
            if next.liveStage != .upload {
                next.liveStage = .upload
                changed = true
            }
            if let mbps = mbps(fromBytesPerSecond: event.upload?.bandwidth?.value), mbps > 0.05 {
                next.uploadMbps = mbps
                changed = true
            }
            if let ms = event.upload?.latency?.iqm?.value, ms > 0 {
                next.uploadLatencyMs = ms
                changed = true
            }
            next.fractionComplete = overallProgress(stage: 2, fraction: event.upload?.progress?.value ?? 0)
        case "result":
            if let ms = event.ping?.latency?.value {
                next.latencyMs = ms
            }
            if let mbps = mbps(fromBytesPerSecond: event.download?.bandwidth?.value), mbps > 0.05 {
                next.downloadMbps = mbps
            }
            if let mbps = mbps(fromBytesPerSecond: event.upload?.bandwidth?.value), mbps > 0.05 {
                next.uploadMbps = mbps
            }
            if let ms = event.download?.latency?.iqm?.value, ms > 0 {
                next.downloadLatencyMs = ms
            }
            if let ms = event.upload?.latency?.iqm?.value, ms > 0 {
                next.uploadLatencyMs = ms
            }
            next.fractionComplete = 1
            next.isFinal = true
            changed = true
        default:
            return false
        }

        guard changed || next.fractionComplete != current?.fractionComplete else {
            return false
        }
        current = next
        return true
    }

    /// Ping, download, then upload — the same order as the Speedtest app.
    private func overallProgress(stage: Int, fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        switch stage {
        case 0: return 0.04 + 0.08 * clamped
        case 1: return 0.12 + 0.40 * clamped
        default: return 0.52 + 0.44 * clamped
        }
    }

    private func mbps(fromBytesPerSecond bytes: Double?) -> Double? {
        guard let bytes else { return nil }
        return bytes * 8 / 1_000_000
    }

    private struct Event: Decodable {
        var type: String
        var ping: Ping?
        var download: Transfer?
        var upload: Transfer?
        var server: ServerRef?
        var message: String?
        var level: String?
    }

    private struct ServerRef: Decodable {
        var id: Int?
    }

    private struct Ping: Decodable {
        var latency: FlexibleDouble?
        var progress: FlexibleDouble?
    }

    private struct Transfer: Decodable {
        var bandwidth: FlexibleDouble?
        var progress: FlexibleDouble?
        var latency: LoadedLatency?
    }

    private struct LoadedLatency: Decodable {
        var iqm: FlexibleDouble?
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

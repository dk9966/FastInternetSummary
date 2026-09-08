import Foundation

/// Locates the official Ookla CLI. A menu-bar app does not inherit the user's
/// Homebrew PATH, so we look at the two standard prefix locations.
enum OoklaCLI {
    static var isAvailable: Bool { executablePath != nil }

    static var executablePath: String? {
        ["/opt/homebrew/bin/speedtest", "/usr/local/bin/speedtest"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Optional provider. The app still ships with Apple's `networkQuality` as the default.
struct OoklaSpeedTestProvider: SpeedTestProvider {
    var name: String { "speedtest" }

    func run(sequential _: Bool, progress: @escaping @Sendable (SpeedTestProgress) async -> Void) async throws -> SpeedTestResult {
        guard let executable = OoklaCLI.executablePath else {
            throw SpeedTestError.failed(
                "Speedtest CLI is not installed. Install it with brew tap teamookla/speedtest && brew install speedtest."
            )
        }

        let parser = OoklaStreamParser()

        let output = try await CommandRunner.runStreaming(
            executable: executable,
            arguments: [
                "--accept-license",
                "--accept-gdpr",
                "--format=jsonl",
                "--progress-update-interval=200"
            ],
            timeout: 120
        ) { chunk in
            if let update = parser.ingest(chunk) {
                Task {
                    await progress(update)
                }
            }
        }

        let latest = parser.finish() ?? parser.current ?? SpeedTestProgress()

        guard output.status == 0 || latest.downloadMbps != nil else {
            throw SpeedTestError.failed(parser.lastError ?? "Speedtest CLI failed.")
        }

        guard let downloadMbps = latest.downloadMbps, let uploadMbps = latest.uploadMbps else {
            throw SpeedTestError.unreadableOutput
        }

        let final = SpeedTestProgress(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            latencyMs: latest.latencyMs,
            fractionComplete: 1,
            isFinal: true
        )
        await progress(final)

        return SpeedTestResult(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            latencyMs: latest.latencyMs,
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

    func ingest(_ chunk: String) -> SpeedTestProgress? {
        lock.lock()
        defer { lock.unlock() }
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

        if event.type == "log", event.level == "error" {
            lastError = event.message?.nilIfEmpty
            return false
        }

        var next = current ?? SpeedTestProgress()
        var changed = false

        switch event.type {
        case "ping":
            if let ms = event.ping?.latency?.value {
                next.latencyMs = ms
                changed = true
            }
            next.fractionComplete = overallProgress(stage: 0, fraction: event.ping?.progress?.value ?? 0)
        case "download":
            if let mbps = mbps(fromBytesPerSecond: event.download?.bandwidth?.value), mbps > 0.05 {
                next.downloadMbps = mbps
                changed = true
            }
            next.fractionComplete = overallProgress(stage: 1, fraction: event.download?.progress?.value ?? 0)
        case "upload":
            if let mbps = mbps(fromBytesPerSecond: event.upload?.bandwidth?.value), mbps > 0.05 {
                next.uploadMbps = mbps
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
        var message: String?
        var level: String?
    }

    private struct Ping: Decodable {
        var latency: FlexibleDouble?
        var progress: FlexibleDouble?
    }

    private struct Transfer: Decodable {
        var bandwidth: FlexibleDouble?
        var progress: FlexibleDouble?
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

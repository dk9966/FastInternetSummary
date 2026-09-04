import Foundation

struct SpeedTestProgress: Sendable, Equatable {
    var downloadMbps: Double?
    var uploadMbps: Double?
    var latencyMs: Double?
    var downloadFlows: Int?
    var uploadFlows: Int?
    var hasLoadedRoundTrip: Bool = false
    var isFinal: Bool = false
}

protocol SpeedTestProvider: Sendable {
    var name: String { get }
    func run(sequential: Bool, progress: @escaping @Sendable (SpeedTestProgress) async -> Void) async throws -> SpeedTestResult
}

/// Built-in macOS provider. This is the default and the only one shipped enabled.
struct NetworkQualityProvider: SpeedTestProvider {
    var name: String { "networkQuality" }

    func run(sequential: Bool, progress: @escaping @Sendable (SpeedTestProgress) async -> Void) async throws -> SpeedTestResult {
        // Idle latency is measured on a quiet line before capacity testing saturates it.
        // Verbose capacity output never streams ms — only the summary at the end — so we
        // probe first (`-d -u`) and publish base_rtt before the capacity run starts.
        let idleLatencyMs = try await streamIdleLatency(progress: progress)

        let parser = NetworkQualityStreamParser()

        // `script` allocates a TTY so networkQuality prints live Downlink/Uplink lines.
        // `-v` also includes flow counts, which we use to estimate progress.
        // `-s` is download, then upload — the same order as a typical website test.
        var arguments = ["-q", "/dev/null", "/usr/bin/networkQuality"]
        if sequential {
            arguments.append("-s")
        }
        arguments.append("-v")

        let output = try await CommandRunner.runStreaming(
            executable: "/usr/bin/script",
            arguments: arguments,
            timeout: sequential ? 120 : 90
        ) { chunk in
            if let update = parser.ingest(chunk) {
                Task {
                    await progress(update)
                }
            }
        }

        let latest = parser.current
            ?? (try? NetworkQualityParser.parse(output.stdout)).map {
                SpeedTestProgress(
                    downloadMbps: $0.downloadMbps,
                    uploadMbps: $0.uploadMbps,
                    latencyMs: $0.latencyMs,
                    isFinal: true
                )
            }
            ?? SpeedTestProgress()

        guard output.status == 0 || latest.downloadMbps != nil else {
            let stderr = String(data: output.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SpeedTestError.failed(stderr?.nilIfEmpty ?? "networkQuality failed.")
        }

        guard let downloadMbps = latest.downloadMbps, let uploadMbps = latest.uploadMbps else {
            throw SpeedTestError.unreadableOutput
        }

        let latencyMs = latest.latencyMs ?? idleLatencyMs

        let final = SpeedTestProgress(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            latencyMs: latencyMs,
            downloadFlows: latest.downloadFlows,
            uploadFlows: latest.uploadFlows,
            isFinal: true
        )
        await progress(final)

        return SpeedTestResult(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            latencyMs: latencyMs,
            testedAt: .now,
            source: name
        )
    }

    /// Idle-only `networkQuality` JSON (`-d -u -c`) finishes in ~0.1s with `base_rtt`.
    /// Publish that on the same async path so the panel updates before capacity testing starts.
    private func streamIdleLatency(
        progress: @escaping @Sendable (SpeedTestProgress) async -> Void
    ) async throws -> Double? {
        let output = try await CommandRunner.runStreaming(
            executable: "/usr/bin/networkQuality",
            arguments: ["-d", "-u", "-c"],
            timeout: 15
        ) { _ in }

        if let ms = NetworkQualityParser.parseIdleLatency(output.stdout) {
            await progress(SpeedTestProgress(latencyMs: ms))
            return ms
        }

        let verbose = try await CommandRunner.runStreaming(
            executable: "/usr/bin/networkQuality",
            arguments: ["-d", "-u", "-v"],
            timeout: 15
        ) { _ in }
        let parser = NetworkQualityStreamParser()
        guard let ms = parser.ingest(String(data: verbose.stdout, encoding: .utf8) ?? "")?.latencyMs else {
            return nil
        }
        await progress(SpeedTestProgress(latencyMs: ms))
        return ms
    }
}

/// Optional future provider for an installed Ookla `speedtest` CLI.
/// The app does not require Homebrew or that binary to function.
struct OoklaSpeedTestProvider: SpeedTestProvider {
    var name: String { "speedtest" }

    func run(sequential _: Bool, progress: @escaping @Sendable (SpeedTestProgress) async -> Void) async throws -> SpeedTestResult {
        throw SpeedTestError.notConfigured
    }
}

final class NetworkQualityStreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var raw = ""
    private(set) var current: SpeedTestProgress?

    func ingest(_ chunk: String) -> SpeedTestProgress? {
        lock.lock()
        defer { lock.unlock() }
        if !chunk.isEmpty {
            raw += chunk
        }
        let parsed = Self.parse(raw)
        guard parsed != current else { return nil }
        current = parsed
        return parsed
    }

    static func parse(_ raw: String) -> SpeedTestProgress? {
        let text = stripANSI(raw)
        var progress = SpeedTestProgress()

        if let download = lastMbps(in: text, patterns: [
            #"Downlink capacity:\s*([0-9.]+)\s*Mbps"#,
            #"Download capacity:\s*([0-9.]+)\s*Mbps"#,
            #"Downlink:\s*(?:capacity\s*)?([0-9.]+)\s*Mbps"#
        ]), download > 0.05 {
            progress.downloadMbps = download
        }
        if let upload = lastMbps(in: text, patterns: [
            #"Uplink capacity:\s*([0-9.]+)\s*Mbps"#,
            #"Upload capacity:\s*([0-9.]+)\s*Mbps"#,
            #"Uplink:\s*(?:capacity\s*)?([0-9.]+)\s*Mbps"#
        ]), upload > 0.05 {
            progress.uploadMbps = upload
        }

        progress.downloadFlows = lastInt(in: text, pattern: #"Downlink:.*?([0-9]+)\s*flows?"#)
        progress.uploadFlows = lastInt(in: text, pattern: #"Uplink:.*?([0-9]+)\s*flows?"#)
        progress.hasLoadedRoundTrip = (lastNumber(in: text, pattern: #"([1-9][0-9.]*)\s*RPM"#) ?? 0) > 0

        if let idle = lastNumber(in: text, pattern: #"Idle Latency:\s*([0-9.]+)\s*milliseconds"#) {
            progress.latencyMs = idle
        } else if let idle = lastNumber(
            in: text,
            pattern: #"Idle Latency:[\s\S]*?\(([0-9.]+)\s*milliseconds\)"#
        ) {
            progress.latencyMs = idle
        }

        let hasCapacitySummary = text.contains("==== SUMMARY ====")
            || text.contains("Downlink capacity:")
            || text.contains("Download capacity:")
        // Sequential `-s` prints downlink capacity before upload starts. Both
        // directions have to be present or the panel would jump to "done" early.
        progress.isFinal = hasCapacitySummary
            && progress.downloadMbps != nil
            && progress.uploadMbps != nil

        if progress.downloadMbps == nil,
           progress.uploadMbps == nil,
           progress.latencyMs == nil,
           progress.downloadFlows == nil {
            return nil
        }
        return progress
    }

    private static func lastMbps(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            if let value = lastNumber(in: text, pattern: pattern) {
                return value
            }
        }
        return nil
    }

    private static func lastInt(in text: String, pattern: String) -> Int? {
        lastNumber(in: text, pattern: pattern).map { Int($0.rounded()) }
    }

    private static func lastNumber(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard let match = matches.last, match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[valueRange])
    }

    private static func stripANSI(_ text: String) -> String {
        let withoutCSI = text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        return withoutCSI
            .replacingOccurrences(of: "\u{08}", with: "")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

enum NetworkQualityParser {
    struct Payload: Decodable {
        var dl_throughput: FlexibleDouble?
        var ul_throughput: FlexibleDouble?
        var base_rtt: FlexibleDouble?
        var error_domain: String?
        var error_code: Int?
    }

    static func decodePayload(_ data: Data) throws -> Payload {
        let json = try extractJSON(from: data)
        let decoded = try JSONDecoder().decode(Payload.self, from: json)
        if let domain = decoded.error_domain, !domain.isEmpty {
            throw SpeedTestError.failed("Speed test failed (\(domain)).")
        }
        return decoded
    }

    static func parse(_ data: Data) throws -> SpeedTestResult {
        let decoded = try decodePayload(data)
        guard let downBps = decoded.dl_throughput?.value, let upBps = decoded.ul_throughput?.value else {
            throw SpeedTestError.unreadableOutput
        }

        return SpeedTestResult(
            downloadMbps: downBps / 1_000_000,
            uploadMbps: upBps / 1_000_000,
            latencyMs: decoded.base_rtt?.value,
            testedAt: .now,
            source: "networkQuality"
        )
    }

    static func parseIdleLatency(_ data: Data) -> Double? {
        (try? decodePayload(data))?.base_rtt?.value
    }

    private static func extractJSON(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SpeedTestError.unreadableOutput
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let slice = text[start...end]
            if let json = slice.data(using: .utf8) {
                return json
            }
        }
        throw SpeedTestError.unreadableOutput
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

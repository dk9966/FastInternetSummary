import CryptoKit
import Darwin
import Foundation

/// Locates the official Ookla CLI. A menu-bar app does not inherit the user's
/// Homebrew PATH, so we look at the two standard prefixes and our own copy.
/// Keep the download URL, version, and SHA256 in sync with install-speedtest.sh.
enum OoklaCLI {
    private static let downloadURL = URL(
        string: "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-macosx-universal.tgz"
    )!
    private static let expectedSHA256 = "c9f8192149ebc88f8699998cecab1ce144144045907ece6f53cf50877f4de66f"

    static var isAvailable: Bool { executablePath != nil }

    static var executablePath: String? {
        candidatePaths.first { isOfficialCLI(at: $0) }
    }

    private static var candidatePaths: [String] {
        [
            "/opt/homebrew/bin/speedtest",
            "/usr/local/bin/speedtest",
            supportBinary.path
        ]
    }

    private static var supportBinary: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.danielku.FastInternetSummary", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("speedtest")
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

    /// Downloads the official CLI when none is on disk. Safe to call often;
    /// Homebrew copies are left alone. Used on first launch (including DMG installs).
    static func installIfNeeded() async {
        await InstallGate.shared.installIfNeeded()
    }

    private static func isOfficialCLI(at path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic.count == 4 else { return false }
        let bytes = [UInt8](magic)
        // Fat / 64-bit fat / 64-bit Mach-O / 32-bit Mach-O.
        return bytes == [0xCA, 0xFE, 0xBA, 0xBE]
            || bytes == [0xCA, 0xFE, 0xBA, 0xBF]
            || bytes == [0xCF, 0xFA, 0xED, 0xFE]
            || bytes == [0xCE, 0xFA, 0xED, 0xFE]
    }

    private actor InstallGate {
        static let shared = InstallGate()

        func installIfNeeded() async {
            if OoklaCLI.isAvailable { return }
            do {
                try await OoklaCLI.downloadOfficialCLI()
            } catch {
                // Next launch retries. Apple's networkQuality still works.
            }
        }
    }

    private static func downloadOfficialCLI() async throws {
        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SpeedTestError.failed("Speedtest CLI download failed (\(http.statusCode)).")
        }

        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == expectedSHA256 else {
            throw SpeedTestError.failed("Speedtest CLI download did not match the expected checksum.")
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("fis-speedtest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let archive = work.appendingPathComponent("speedtest.tgz")
        try data.write(to: archive, options: .atomic)

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", work.path]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw SpeedTestError.failed("Speedtest CLI archive could not be unpacked.")
        }

        let extracted = work.appendingPathComponent("speedtest")
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw SpeedTestError.failed("Speedtest CLI archive did not contain a speedtest binary.")
        }

        let destination = supportBinary
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: extracted, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destination.path
        )
        _ = removexattr(destination.path, "com.apple.quarantine", 0)
        guard isOfficialCLI(at: destination.path) else {
            throw SpeedTestError.failed("Speedtest CLI was installed but is not a usable binary.")
        }
    }
}

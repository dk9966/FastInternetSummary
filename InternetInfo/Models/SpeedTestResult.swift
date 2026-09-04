import Foundation

struct SpeedTestResult: Sendable, Equatable, Codable {
    var downloadMbps: Double?
    var uploadMbps: Double?
    var latencyMs: Double?
    var testedAt: Date
    var source: String

    var isComplete: Bool {
        downloadMbps != nil && uploadMbps != nil
    }

    private enum Keys {
        static let payload = "speedTest.lastResult"
    }

    func save(defaults: UserDefaults = .standard) {
        guard isComplete else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Keys.payload)
        }
    }

    static func load(defaults: UserDefaults = .standard) -> SpeedTestResult? {
        guard let data = defaults.data(forKey: Keys.payload) else { return nil }
        return try? JSONDecoder().decode(SpeedTestResult.self, from: data)
    }
}

enum SpeedTestError: LocalizedError {
    case timedOut
    case failed(String)
    case unreadableOutput
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "The speed test timed out."
        case .failed(let message):
            message
        case .unreadableOutput:
            "Could not read the speed test result."
        case .notConfigured:
            "This speed test provider is not available."
        }
    }
}

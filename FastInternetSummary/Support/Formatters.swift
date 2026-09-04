import Foundation

enum ByteRateFormat {
    static func string(bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "—" }

        let magnitude = max(bytesPerSecond, 0)
        if magnitude >= 1_000_000_000 {
            return String(format: "%0.1f GB/s", magnitude / 1_000_000_000)
        }
        if magnitude >= 1_000_000 {
            return String(format: "%0.1f MB/s", magnitude / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%0.1f KB/s", magnitude / 1_000)
        }
        return String(format: "%0.0f KB/s", magnitude / 1_000)
    }

    static func compact(bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "—" }

        let magnitude = max(bytesPerSecond, 0)
        if magnitude >= 1_000_000_000 {
            return String(format: "%0.1fG", magnitude / 1_000_000_000)
        }
        if magnitude >= 1_000_000 {
            return String(format: "%0.1fM", magnitude / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%0.0fK", magnitude / 1_000)
        }
        return "0K"
    }
}

enum ThroughputFormat {
    static func mbps(_ value: Double) -> String {
        if value >= 10 {
            return "\(Int(value.rounded())) Mbps"
        }
        return String(format: "%0.1f Mbps", value)
    }

    static func latency(_ milliseconds: Double) -> String {
        "\(Int(milliseconds.rounded())) ms"
    }
}

enum RelativeTimeFormat {
    static func checkedPhrase(from date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 20 {
            return "Checked just now"
        }
        if elapsed < 60 {
            return "Checked \(Int(elapsed))s ago"
        }
        if elapsed < 3_600 {
            let minutes = max(1, Int(elapsed / 60))
            return minutes == 1 ? "Checked 1 min ago" : "Checked \(minutes) min ago"
        }
        if elapsed < 86_400 {
            let hours = max(1, Int(elapsed / 3_600))
            return hours == 1 ? "Checked 1 hour ago" : "Checked \(hours) hours ago"
        }
        let days = max(1, Int(elapsed / 86_400))
        return days == 1 ? "Checked yesterday" : "Checked \(days) days ago"
    }
}

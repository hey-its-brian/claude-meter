import Foundation

/// One rate-limit window from the plan usage endpoint (for example the 5-hour session or the weekly cap).
struct UsageWindow: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var shortLabel: String
    /// Percent of the window's allowance used, 0...100.
    var utilization: Double
    var resetsAt: Date?
    /// Total length of the window, used to draw the "time elapsed" pace marker.
    var duration: TimeInterval?

    var fraction: Double { min(max(utilization / 100, 0), 1) }

    /// How far through the window we are, 0...1, or nil when the reset time is unknown.
    func elapsedFraction(at now: Date = .now) -> Double? {
        guard let resetsAt, let duration, duration > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / duration, 0), 1)
    }

    /// The same window after its reset, when usage drops back to zero.
    func afterReset() -> UsageWindow {
        var copy = self
        copy.utilization = 0
        if let resetsAt, let duration { copy.resetsAt = resetsAt.addingTimeInterval(duration) }
        return copy
    }
}

struct UsageSnapshot: Codable, Hashable {
    var fetchedAt: Date
    var plan: String?
    var windows: [UsageWindow]
    var error: String?

    var session: UsageWindow? { windows.first { $0.id == "five_hour" } }
    var weekly: UsageWindow? { windows.first { $0.id == "seven_day" } }
    var weeklyModels: [UsageWindow] { windows.filter { $0.id != "five_hour" && $0.id != "seven_day" } }

    static let placeholder = UsageSnapshot(
        fetchedAt: .now,
        plan: "Max",
        windows: [
            UsageWindow(id: "five_hour", label: "Current session", shortLabel: "Session",
                        utilization: 42, resetsAt: .now.addingTimeInterval(2.4 * 3600), duration: 5 * 3600),
            UsageWindow(id: "seven_day", label: "Weekly · all models", shortLabel: "Week",
                        utilization: 27, resetsAt: .now.addingTimeInterval(4.2 * 86400), duration: 7 * 86400),
            UsageWindow(id: "seven_day_opus", label: "Weekly · Opus", shortLabel: "Opus",
                        utilization: 12, resetsAt: .now.addingTimeInterval(4.2 * 86400), duration: 7 * 86400),
        ],
        error: nil)
}

/// Shared storage between the menu bar app (writer) and the widget (reader), via the app group container.
enum SnapshotStore {
    static let groupID = "54U9L6YAF4.com.heyitsbrian.claudemeter"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("usage.json")
    }

    static func load() -> UsageSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

import Foundation
import WidgetKit

/// Reads Claude Code's OAuth login and polls Anthropic's plan usage endpoint
/// (the same data Claude Code's `/usage` command shows).
@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false

    private let pollInterval: TimeInterval = 5 * 60
    private var timer: Timer?

    init() {
        snapshot = SnapshotStore.load()
    }

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var next: UsageSnapshot
        do {
            let credentials = try await Credentials.load()
            let windows = try await Self.fetchUsage(token: credentials.accessToken)
            next = UsageSnapshot(fetchedAt: .now, plan: credentials.planName, windows: windows, error: nil)
        } catch {
            // Keep the last good numbers visible, but flag that they are stale.
            next = snapshot ?? UsageSnapshot(fetchedAt: .now, plan: nil, windows: [], error: nil)
            next.error = error.localizedDescription
        }
        snapshot = next
        SnapshotStore.save(next)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Networking

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static func fetchUsage(token: String) async throws -> [UsageWindow] {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeMeter/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401, 403: throw MeterError.tokenExpired
        default: throw MeterError.http(status)
        }
        return try parseWindows(data)
    }

    /// Parses the response leniently: any top-level object with a numeric `utilization` is a window.
    /// That way new limit types (per-model weekly caps and so on) show up without an app update.
    static func parseWindows(_ data: Data) throws -> [UsageWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MeterError.badResponse
        }
        let windows = root.compactMap { key, value -> UsageWindow? in
            guard let dict = value as? [String: Any],
                  let utilization = (dict["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let resetsAt = (dict["resets_at"] as? String).flatMap(parseDate)
            // Buckets with no usage and no reset time are inactive; skip them to keep the widget tidy.
            if resetsAt == nil && utilization == 0 { return nil }
            let meta = WindowMeta.for(key)
            return UsageWindow(id: key, label: meta.label, shortLabel: meta.short,
                               utilization: utilization, resetsAt: resetsAt, duration: meta.duration)
        }
        return windows.sorted { WindowMeta.order($0.id) < WindowMeta.order($1.id) }
    }

    private static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

private struct WindowMeta {
    var label: String
    var short: String
    var duration: TimeInterval?

    static let known: [String: WindowMeta] = [
        "five_hour": WindowMeta(label: "Current session", short: "Session", duration: 5 * 3600),
        "seven_day": WindowMeta(label: "Weekly · all models", short: "Week", duration: 7 * 86400),
        "seven_day_opus": WindowMeta(label: "Weekly · Opus", short: "Opus", duration: 7 * 86400),
        "seven_day_sonnet": WindowMeta(label: "Weekly · Sonnet", short: "Sonnet", duration: 7 * 86400),
        "seven_day_oauth_apps": WindowMeta(label: "Weekly · OAuth apps", short: "Apps", duration: 7 * 86400),
    ]

    static func `for`(_ key: String) -> WindowMeta {
        if let meta = known[key] { return meta }
        let pretty = key.replacingOccurrences(of: "_", with: " ").capitalized
        return WindowMeta(label: pretty, short: pretty, duration: key.hasPrefix("seven_day") ? 7 * 86400 : nil)
    }

    static func order(_ key: String) -> Int {
        ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"].firstIndex(of: key) ?? 99
    }
}

enum MeterError: LocalizedError {
    case notLoggedIn
    case tokenExpired
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "No Claude Code login found. Run `claude` and sign in with your Claude plan."
        case .tokenExpired: "Login token expired. Run any `claude` command to refresh it."
        case .http(let code): "Usage request failed (HTTP \(code))."
        case .badResponse: "Unexpected response from the usage endpoint."
        }
    }
}

// MARK: - Credentials

/// Claude Code stores its OAuth login in the login keychain ("Claude Code-credentials"),
/// or in ~/.claude/.credentials.json on some setups. We only read it; Claude Code owns refreshing it.
struct Credentials {
    var accessToken: String
    var expiresAt: Date?
    var subscriptionType: String?

    var planName: String? {
        guard let subscriptionType, !subscriptionType.isEmpty else { return nil }
        return subscriptionType.prefix(1).uppercased() + subscriptionType.dropFirst()
    }

    static func load() async throws -> Credentials {
        let json = await Task.detached { readKeychain() ?? readFile() }.value
        guard let json,
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw MeterError.notLoggedIn
        }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        if let expires, expires < .now { throw MeterError.tokenExpired }
        return Credentials(accessToken: token, expiresAt: expires, subscriptionType: oauth["subscriptionType"] as? String)
    }

    /// Uses /usr/bin/security because Claude Code creates the item with it, so it is already
    /// on the item's access list and macOS does not prompt on every poll.
    private static func readKeychain() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    private static func readFile() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }
}

import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: UsageSnapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, snapshot: context.isPreview ? .placeholder : SnapshotStore.load() ?? .placeholder))
    }

    /// The menu bar app pushes fresh data and reloads timelines every few minutes. Here we also
    /// schedule entries at each reset time so a window drops to 0% on time even if the app is idle.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date.now
        guard var snapshot = SnapshotStore.load() else {
            completion(Timeline(entries: [UsageEntry(date: now, snapshot: nil)], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        var entries = [UsageEntry(date: now, snapshot: snapshot)]
        let resets = Set(snapshot.windows.compactMap(\.resetsAt)).filter { $0 > now }.sorted().prefix(4)
        for reset in resets {
            snapshot.windows = snapshot.windows.map { ($0.resetsAt ?? .distantFuture) <= reset ? $0.afterReset() : $0 }
            entries.append(UsageEntry(date: reset, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct ClaudeMeterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.session != nil || snapshot.weekly != nil {
                switch family {
                case .systemSmall: SmallView(snapshot: snapshot, now: entry.date)
                default: MediumView(snapshot: snapshot, now: entry.date)
                }
            } else {
                EmptyStateView(message: entry.snapshot?.error)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct Header: View {
    var snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
                .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
            Text("Claude").font(.caption.weight(.semibold))
            if let plan = snapshot.plan {
                Text(plan).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if snapshot.error != nil || snapshot.fetchedAt < .now.addingTimeInterval(-30 * 60) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct SmallView: View {
    var snapshot: UsageSnapshot
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(snapshot: snapshot)
            ForEach([snapshot.session, snapshot.weekly].compactMap { $0 }) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(window.shortLabel).font(.caption)
                        Spacer()
                        Text(UsageStyle.percent(window.utilization))
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    UsageBar(window: window, now: now, height: 5)
                    ResetText(window: window)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MediumView: View {
    var snapshot: UsageSnapshot
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(snapshot: snapshot)
            HStack(spacing: 14) {
                if let session = snapshot.session {
                    VStack(spacing: 4) {
                        UsageRing(window: session)
                        Text("Session").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 84)
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(snapshot.windows.filter { $0.id != "five_hour" }.prefix(3)) { window in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.label).font(.caption).lineLimit(1)
                                Spacer()
                                Text(UsageStyle.percent(window.utilization))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                            }
                            UsageBar(window: window, now: now, height: 5)
                        }
                    }
                    if let session = snapshot.session {
                        ResetText(window: session, prefix: "Session resets")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ResetText: View {
    var window: UsageWindow
    var prefix = "Resets"

    var body: some View {
        if let resetsAt = window.resetsAt {
            if resetsAt.timeIntervalSinceNow < 86400 {
                Text("\(prefix) in \(resetsAt, style: .relative)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("\(prefix) \(resetsAt.formatted(.dateTime.weekday(.abbreviated).hour()))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct EmptyStateView: View {
    var message: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.0percent").font(.title2)
            Text(message ?? "Open ClaudeMeter to start tracking usage.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

@main
struct ClaudeMeterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeMeterWidget", provider: UsageProvider()) { entry in
            ClaudeMeterWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your Claude plan's session and weekly limits.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ClaudeMeterWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder)
}

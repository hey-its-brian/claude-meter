import ServiceManagement
import SwiftUI

enum Prefs {
    static let showMenuBarItem = "showMenuBarItem"
}

/// Owns the poller so it keeps running while the menu bar item is hidden.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = UsageService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        service.start()
    }

    /// Opening the app again (Finder, Spotlight, or clicking the widget) brings a hidden menu bar item back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: Prefs.showMenuBarItem)
        return false
    }
}

@main
struct ClaudeMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.showMenuBarItem) private var showMenuBarItem = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarItem) {
            MenuView()
                .environmentObject(appDelegate.service)
        } label: {
            MenuBarLabel(service: appDelegate.service)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var service: UsageService

    var body: some View {
        let snapshot = service.snapshot
        if let session = snapshot?.session {
            let weekly = snapshot?.weekly.map { " · \(UsageStyle.percent($0.utilization))" } ?? ""
            Text("\(Image(systemName: "gauge.with.dots.needle.33percent")) \(UsageStyle.percent(session.utilization))\(weekly)")
                .monospacedDigit()
        } else {
            Image(systemName: "gauge.with.dots.needle.0percent")
        }
    }
}

struct MenuView: View {
    @EnvironmentObject private var service: UsageService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Prefs.showMenuBarItem) private var showMenuBarItem = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude usage").font(.headline)
                if let plan = service.snapshot?.plan {
                    Text(plan)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Button {
                    Task { await service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(service.isRefreshing)
            }

            if let snapshot = service.snapshot, !snapshot.windows.isEmpty {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.windows) { window in
                            WindowRow(window: window, now: context.date)
                        }
                    }
                }
            } else if service.snapshot?.error == nil {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let error = service.snapshot?.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                if let fetched = service.snapshot?.fetchedAt {
                    Text("Updated \(fetched, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Open at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
            HStack {
                Button("Hide menu bar icon") { showMenuBarItem = false }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("The widget keeps updating. Open ClaudeMeter again or click the widget to bring the icon back.")
                Spacer()
            }
            HStack {
                Text("Tick mark = time elapsed in the window")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct WindowRow: View {
    var window: UsageWindow
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label).font(.subheadline)
                Spacer()
                Text(UsageStyle.percent(window.utilization))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            UsageBar(window: window, now: now)
            if let resetsAt = window.resetsAt {
                Text("Resets \(resetsAt, format: .relative(presentation: .named)) · \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

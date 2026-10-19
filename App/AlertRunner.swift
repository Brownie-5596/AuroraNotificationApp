import AuroraKit
import Foundation
import UserNotifications

/// Fetch → evaluate → notify. Used by background refreshes and while the app is open.
enum AlertRunner {
    private static let gate = RunGate()

    /// Returns false if the refresh failed outright.
    @discardableResult
    static func run(reason: String) async -> Bool {
        guard await gate.begin() else { return true }
        defer { Task { await gate.end() } }

        let store = Store.shared
        let settings = store.settings
        let client = SpaceWeatherClient(nasaAPIKey: store.nasaAPIKey)
        let snapshot = await client.fetchSnapshot(location: settings.location, previous: store.loadSnapshot())
        if Task.isCancelled { return false }
        guard snapshot.latestMag != nil || !snapshot.kpForecast.isEmpty else {
            store.log("\(reason): refresh failed (\(snapshot.errors.count) feeds)")
            return false
        }
        store.saveSnapshot(snapshot)

        var state = store.alertState
        let alerts = AlertEngine.evaluate(snapshot: snapshot, settings: settings, state: &state)
        store.alertState = state
        for alert in alerts { await Notifier.post(alert) }

        if reason == "background" { store.lastBackgroundRun = Date() }
        store.log("\(reason): \(alerts.isEmpty ? "no new alerts" : alerts.map(\.title).joined(separator: ", "))")
        let finalState = state
        await MainActor.run { AppModel.shared.apply(snapshot: snapshot, state: finalState) }
        return true
    }
}

/// Prevents overlapping runs (e.g. a background refresh firing while the foreground timer runs).
actor RunGate {
    private var running = false
    func begin() -> Bool {
        if running { return false }
        running = true
        return true
    }
    func end() { running = false }
}

enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func post(_ alert: AuroraAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.kind.group
        content.interruptionLevel = alert.priority >= 4 ? .timeSensitive : .active
        content.relevanceScore = Double(alert.priority) / 5
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

import AuroraKit
import Foundation
import UserNotifications

/// Fetch → evaluate → notify. Used by background refreshes, Night Watch, Shortcuts and while the app is open.
enum AlertRunner {
    private static let gate = RunGate()

    enum Outcome { case done, failed, skipped }

    /// - Parameters:
    ///   - quick: the small, fast refresh (~100 KB, short timeouts) used in the background,
    ///     where iOS gives the app only ~30 seconds. The full refresh feeds the charts.
    ///   - waitIfBusy: if another check is running, wait for it and then run (used when you're
    ///     looking at the app); otherwise skip (background checks).
    @discardableResult
    static func run(reason: String, quick: Bool = false, waitIfBusy: Bool = false) async -> Outcome {
        await gate.run(wait: waitIfBusy) { await perform(reason: reason, quick: quick) }
    }

    private static func perform(reason: String, quick: Bool) async -> Outcome {
        let store = Store.shared
        let settings = store.settings
        let client = SpaceWeatherClient(nasaAPIKey: store.nasaAPIKey, quick: quick)
        let previous = store.loadSnapshot()
        let snapshot = quick
            ? await client.fetchAlertSnapshot(location: settings.location, previous: previous)
            : await client.fetchSnapshot(location: settings.location, previous: previous)
        if Task.isCancelled { return .failed }
        guard snapshot.latestMag != nil || !snapshot.kpForecast.isEmpty else {
            store.log("\(reason): refresh failed (\(snapshot.errors.keys.sorted().joined(separator: ", ")))")
            return .failed
        }

        // Notify first — saving the snapshot is the slow part and iOS may stop us at any moment.
        // Save what was sent before posting, so a check that's cut short can't send it twice.
        var state = store.alertState
        let alerts = AlertEngine.evaluate(snapshot: snapshot, settings: settings, state: &state)
        let plans = AlertEngine.plan(snapshot: snapshot, settings: settings, state: &state)
        store.alertState = state
        for alert in alerts { await Notifier.post(alert) }
        await Notifier.schedule(plans)

        store.lastCheck = Date()
        if ["background", "processing"].contains(reason) { store.lastBackgroundRun = Date() }
        store.log("\(reason): \(alerts.isEmpty ? "no new alerts" : alerts.map(\.title).joined(separator: ", "))"
                  + (plans.isEmpty ? "" : " · \(plans.count) reminder(s) scheduled"))
        store.saveSnapshot(snapshot)
        let finalState = state
        await MainActor.run { AppModel.shared.apply(snapshot: snapshot, state: finalState) }
        return .done
    }
}

/// Runs one check at a time (e.g. a background refresh firing while the app's own refresh runs).
actor RunGate {
    private var current: Task<AlertRunner.Outcome, Never>?

    func run(wait: Bool, _ work: @escaping @Sendable () async -> AlertRunner.Outcome) async -> AlertRunner.Outcome {
        while let running = current {
            guard wait else { return .skipped }
            _ = await running.value
        }
        let task = Task { await work() }
        current = task
        let outcome = await task.value
        current = nil
        return outcome
    }
}

enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func post(_ alert: AuroraAlert) async {
        let request = UNNotificationRequest(identifier: alert.id, content: content(alert), trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func content(_ alert: AuroraAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.kind.group
        // Time-sensitive delivery needs an entitlement sideloaded apps can't get, so stay "active".
        content.interruptionLevel = .active
        content.relevanceScore = Double(alert.priority) / 5
        return content
    }

    /// Replaces previously scheduled reminders with `plans`, so iOS delivers them on time even if
    /// the app doesn't run again before then.
    static func schedule(_ plans: [PlannedAlert]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("plan-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for plan in plans {
            let interval = plan.fireDate.timeIntervalSinceNow
            guard interval > 60 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.notificationID, content: content(plan.alert), trigger: trigger))
        }
    }
}

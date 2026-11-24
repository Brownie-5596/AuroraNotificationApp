import AuroraKit
import Foundation
import UserNotifications

/// The buttons on notifications (press and hold, or pull down, a notification to see them).
enum NotificationActions {
    static let realtimeCategory = "REALTIME"
    static let tonightCategory = "TONIGHT"

    static let headingOut = "HEADING_OUT"
    static let snoozeHour = "SNOOZE_1H"
    static let snoozeNight = "SNOOZE_NIGHT"
    static let remindDark = "REMIND_DARK"

    static func register() {
        let out = UNNotificationAction(identifier: headingOut, title: "I'm heading out", options: [.foreground],
                                       icon: UNNotificationActionIcon(systemImageName: "figure.walk"))
        let hour = UNNotificationAction(identifier: snoozeHour, title: "Snooze 1 hour", options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "moon.zzz"))
        let night = UNNotificationAction(identifier: snoozeNight, title: "Snooze tonight", options: [],
                                         icon: UNNotificationActionIcon(systemImageName: "bed.double"))
        let remind = UNNotificationAction(identifier: remindDark, title: "Remind me when it's dark", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "alarm"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: realtimeCategory, actions: [out, hour, night], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: tonightCategory, actions: [remind, night], intentIdentifiers: [], options: []),
        ])
    }

    /// Which buttons an alert gets: "happening now" alerts can be snoozed or acted on; tonight's
    /// forecast can turn into a reminder at dark.
    static func category(for kind: AlertKind) -> String? {
        switch kind {
        // The test notification gets them too, so you can try the buttons.
        case .bzSouth, .shock, .activity, .goes, .ground, .noaa, .test: return realtimeCategory
        case .forecastTonight: return tonightCategory
        default: return nil
        }
    }

    /// Handles a button press. iOS runs the app briefly in the background for these (or opens it,
    /// for "I'm heading out").
    @MainActor
    static func handle(_ action: String) async {
        switch action {
        case headingOut: OutingControl.headOut()
        case snoozeHour: await OutingControl.snooze(until: Date().addingTimeInterval(3600))
        case snoozeNight: await OutingControl.snoozeTonight()
        case remindDark: await OutingControl.remindWhenDark()
        default: break
        }
    }
}

/// Snooze and "I'm heading out", from a notification button or the Now tab's menu.
@MainActor
enum OutingControl {
    /// While you're out, the app checks every minute (keeping itself running like Night Watch, even
    /// if Night Watch is off) and only tells you what changed.
    static func headOut() {
        let now = Date()
        let location = Store.shared.settings.location
        let until = Outing.outingEnd(location: location, now: now)
        update { $0.startOuting(now: now, until: until) }
        Store.shared.log("Heading out until \(TimeText.time(until, location.timeZone))")
        NightWatch.shared.startForOuting()
        AppModel.shared.selectedTab = .now
        Task { await AlertRunner.run(reason: "heading out", quick: true, waitIfBusy: true) }
    }

    static func snooze(until: Date) async {
        update { state in
            state.snooze(until: until)
            // Reminders that would have gone off during the snooze are dropped below.
            state.planned = state.planned.filter { $0.value.fireDate >= until }
        }
        await Notifier.dropPlans(before: until)
        stopOutingWatchIfNeeded()
        Store.shared.log("Alerts snoozed until \(TimeText.dayTime(until, Store.shared.settings.location.timeZone))")
    }

    static func snoozeTonight() async {
        let location = Store.shared.settings.location
        await snooze(until: Outing.endOfNight(location: location, now: Date()))
    }

    static func resume() {
        update { $0.resume() }
        stopOutingWatchIfNeeded()
        Store.shared.log("Alerts back to normal")
    }

    /// Books a notification for when the sky gets properly dark tonight (nautical dusk), with the
    /// best viewing stretch from the hour-by-hour plan.
    static func remindWhenDark() async {
        let store = Store.shared
        let location = store.settings.location
        let tz = location.timeZone
        let now = Date()
        let nightOf = Sky.currentNightOf(now: now, location: location)
        let sky = Sky.nightSky(nightOf: nightOf, location: location)
        let dark = sky.nauticalDusk ?? sky.sunset ?? now
        let fire = max(dark, now.addingTimeInterval(60))

        var body = "It's dark now in \(location.name)."
        if let snapshot = store.loadSnapshot() {
            let night = Outlook.nights(snapshot: snapshot, location: location, now: now).first { $0.daysAhead == 0 }
            if let night { body += " Forecast Kp up to \(KpFormat.label(night.maxKp)) tonight." }
            let plan = Outlook.viewingPlan(snapshot: snapshot, location: location, nightOf: nightOf, now: now)
            if let best = plan.best {
                body += " Best viewing looks like \(TimeText.time(best.start, tz))–\(TimeText.time(best.end, tz))."
            }
            if let cover = night?.cloudCover { body += " Clouds ~\(Int(cover))%." }
        }
        body += " Open the app for live conditions."

        let alert = AuroraAlert(id: "remind-dark-\(TimeText.format(nightOf, tz, "yyyy-MM-dd"))", date: fire, kind: .activity,
                                title: "🌌 It's dark — time to look for aurora", body: body, priority: 3)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSinceNow, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: alert.id, content: Notifier.content(alert), trigger: trigger))
        store.log("Reminder booked for \(TimeText.time(fire, tz))")
    }

    private static func update(_ change: (inout AlertState) -> Void) {
        var state = Store.shared.alertState
        change(&state)
        Store.shared.alertState = state
        AppModel.shared.updateOuting(from: state)
    }

    private static func stopOutingWatchIfNeeded() {
        let watch = NightWatch.shared
        if watch.isRunning && !watch.enabled { watch.stop() }
    }
}

import AuroraKit
import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct AuroraWatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.aurora)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                model.startAutoRefresh()
                NightWatch.shared.startIfEnabled()
            case .background:
                model.stopAutoRefresh()
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register()
        BackgroundRefresh.schedule()
        // If iOS relaunched us in the background (e.g. for a refresh), try to resume Night Watch.
        Task { @MainActor in NightWatch.shared.startIfEnabled() }
        return true
    }

    // Show banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppModel.shared.selectedTab = .now }
    }
}

/// iOS decides when background refreshes actually run (typically every 15 min – few hours,
/// more often for apps you open regularly, never after the app is swiped away). Each run does a
/// small, fast check and sends any alerts. A second, "processing" task gives iOS another chance
/// to wake the app — it tends to run those overnight while the phone is charging.
enum BackgroundRefresh {
    static let identifier = "com.brownie5596.aurorawatch.refresh"
    static let processingIdentifier = "com.brownie5596.aurorawatch.processing"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task, reason: "background")
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
            handle(task, reason: "processing")
        }
    }

    static func schedule() {
        let refresh = BGAppRefreshTaskRequest(identifier: identifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        let processing = BGProcessingTaskRequest(identifier: processingIdentifier)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        for request in [refresh, processing] as [BGTaskRequest] {
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                Store.shared.log("Could not schedule \(request.identifier): \(error.localizedDescription)")
            }
        }
    }

    static func handle(_ task: BGTask, reason: String) {
        schedule()
        let work = Task {
            let result = await AlertRunner.run(reason: reason, quick: true)
            if !Task.isCancelled { task.setTaskCompleted(success: result) }
        }
        task.expirationHandler = {
            Store.shared.log("\(reason): iOS ended the check early")
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

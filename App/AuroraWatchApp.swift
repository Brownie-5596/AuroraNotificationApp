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
/// more often for apps you open regularly). Each run fetches data and evaluates the alert rules.
enum BackgroundRefresh {
    static let identifier = "com.brownie5596.aurorawatch.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Store.shared.log("Could not schedule background refresh: \(error.localizedDescription)")
        }
    }

    static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            let result = await AlertRunner.run(reason: "background")
            task.setTaskCompleted(success: result)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

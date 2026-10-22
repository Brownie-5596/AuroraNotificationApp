import AppIntents
import AuroraKit
import Foundation

/// "Check for aurora" action for the Shortcuts app. Runs in the background without opening the
/// app, so a personal automation (e.g. every evening at 9, 10, 11 PM… or "when charger connects")
/// can trigger checks on a schedule iOS doesn't control.
struct CheckAuroraIntent: AppIntent {
    static var title: LocalizedStringResource = "Check for Aurora"
    static var description = IntentDescription("Downloads the latest space weather and sends any aurora alerts.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AlertRunner.run(reason: "shortcut", quick: true)
        let summary = await MainActor.run { () -> String in
            guard let nowcast = AppModel.shared.nowcast else { return "Couldn't get space weather data." }
            var text = "\(nowcast.level.title): aurora chance \(nowcast.score)/100."
            if let kp = nowcast.estimatedKp { text += " Kp \(String(format: "%.1f", kp))." }
            if let bz = nowcast.bz { text += " Bz \(String(format: "%+.1f", bz)) nT." }
            return text
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

struct AuroraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckAuroraIntent(), phrases: ["Check for aurora with \(.applicationName)"])
    }
}

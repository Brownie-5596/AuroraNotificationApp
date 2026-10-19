import AuroraKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Tab: Hashable { case now, forecast, sky, alerts, settings }

    @Published var selectedTab: Tab = .now
    @Published private(set) var snapshot: SpaceWeatherSnapshot?
    @Published private(set) var nowcast: Nowcast?
    @Published private(set) var nights: [NightOutlook] = []
    @Published private(set) var history: [AuroraAlert] = []
    @Published private(set) var isRefreshing = false
    @Published var settings: AlertSettings {
        didSet {
            guard settings != oldValue else { return }
            Store.shared.settings = settings
            recompute()
        }
    }

    private var timer: Timer?

    private init() {
        settings = Store.shared.settings
        snapshot = Store.shared.loadSnapshot()
        history = Store.shared.alertState.history.reversed()
        recompute()
    }

    var location: ObserverLocation { settings.location }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await AlertRunner.run(reason: "app")
        isRefreshing = false
    }

    func apply(snapshot: SpaceWeatherSnapshot, state: AlertState) {
        self.snapshot = snapshot
        history = state.history.reversed()
        recompute()
    }

    func recompute() {
        guard let snapshot else { return }
        let now = Date()
        nowcast = Outlook.nowcast(snapshot: snapshot, location: settings.location, now: now)
        nights = Outlook.nights(snapshot: snapshot, location: settings.location, now: now)
    }

    func clearHistory() {
        var state = Store.shared.alertState
        state.history = []
        Store.shared.alertState = state
        history = []
    }

    /// Forget what was already sent, so current conditions can alert again (handy after changing rules).
    func resetAlertMemory() {
        var state = AlertState()
        state.history = Store.shared.alertState.history
        state.initialized = true
        Store.shared.alertState = state
    }

    func startAutoRefresh() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}

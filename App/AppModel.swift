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
    @Published private(set) var tonightSky: NightSky?
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
        // Launch argument used by the UI smoke test: `-initialTab forecast`
        switch UserDefaults.standard.string(forKey: "initialTab") {
        case "forecast": selectedTab = .forecast
        case "sky": selectedTab = .sky
        case "alerts": selectedTab = .alerts
        case "settings": selectedTab = .settings
        default: break
        }
        history = Store.shared.alertState.history.reversed()
        recompute()
    }

    var location: ObserverLocation { settings.location }

    private var lastFullRefresh: Date?

    /// Pull-to-refresh and opening the app do a full refresh (all feeds, for the charts). The
    /// once-a-minute timer only does the small, fast update unless the last full one is 10 min old.
    func refresh(full: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let doFull = full || lastFullRefresh.map { Date().timeIntervalSince($0) > 10 * 60 } ?? true
        await AlertRunner.run(reason: "app", quick: !doFull)
        if doFull { lastFullRefresh = Date() }
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
        tonightSky = Sky.nightSky(nightOf: Sky.currentNightOf(now: now, location: settings.location), location: settings.location)
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
        Task { await refresh(full: false) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh(full: false) }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}

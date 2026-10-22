import AuroraKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var checkResult: String?
    @State private var nasaKey = Store.shared.nasaAPIKey
    @AppStorage("nightWatchEnabled") private var nightWatchEnabled = false
    @ObservedObject private var nightWatch = NightWatch.shared

    private let kpChoices: [Double] = [3.0, 3.33, 3.67, 4.0, 4.33, 4.67, 5.0, 5.33, 5.67, 6.0, 6.33, 6.67, 7.0, 7.67, 8.67]

    var body: some View {
        NavigationStack {
            Form {
                notificationsSection
                backgroundSection
                forecastSection
                realtimeSection
                otherSection
                etiquetteSection
                locationSection
                Section("Help") {
                    NavigationLink("How aurora forecasting works") { GuideView() }
                    NavigationLink("Scheduled checks with Shortcuts") { ShortcutsHelpView() }
                    NavigationLink("Push alerts via ntfy (advanced)") { PushSetupView() }
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .screenBackground()
            .task { notificationStatus = await Notifier.status() }
        }
    }

    // MARK: Sections

    var notificationsSection: some View {
        Section {
            HStack {
                Text("Notifications")
                Spacer()
                Text(statusText).foregroundStyle(notificationStatus == .authorized ? Theme.aurora : .orange)
            }
            if notificationStatus != .authorized {
                Button("Allow notifications") {
                    Task {
                        _ = await Notifier.requestPermission()
                        notificationStatus = await Notifier.status()
                        if notificationStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    }
                }
            }
            Button("Send test notification") {
                Task {
                    await Notifier.post(AuroraAlert(id: "test-\(Date().timeIntervalSince1970)", date: Date(), kind: .test,
                                                    title: "🌌 Test alert", body: "Notifications are working. Clear skies!", priority: 3))
                }
            }
            Button("Check conditions now") {
                Task {
                    checkResult = "Checking…"
                    let before = model.history.count
                    await AlertRunner.run(reason: "manual")
                    let new = model.history.count - before
                    checkResult = new > 0 ? "Sent \(new) alert\(new == 1 ? "" : "s")" : "Nothing new to alert about right now"
                }
            }
            if let checkResult { Text(checkResult).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Notifications")
        }
    }

    var backgroundSection: some View {
        Section {
            Toggle(isOn: $nightWatchEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Night Watch")
                    Text("Keep checking every \(Int(NightWatch.nightInterval / 60)) min after dark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: nightWatchEnabled) { on in
                if on { nightWatch.start() } else { nightWatch.stop() }
            }
            if nightWatchEnabled {
                LabeledContent("Night Watch", value: nightWatch.isRunning ? "Running" : "Stopped — open the app to restart")
                    .foregroundStyle(nightWatch.isRunning ? Theme.aurora : .orange)
                if let error = nightWatch.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            LabeledContent("Last check", value: ago(Store.shared.lastCheck))
            LabeledContent("Last iOS background refresh", value: ago(Store.shared.lastBackgroundRun))
            let reminders = Store.shared.alertState.planned.count
            if reminders > 0 {
                LabeledContent("Reminders booked with iOS", value: "\(reminders)")
            }
        } header: {
            Text("When the app is closed")
        } footer: {
            Text("""
            Forecast alerts (tonight / tomorrow / CME) are booked with iOS ahead of time, so they arrive even if the app is closed.
            Real-time heads-ups need the app to be running. iOS only wakes sideloaded apps every few hours at best, so turn on **Night Watch**: the app keeps running in the background (it plays silence, mixed with your music) and checks every \(Int(NightWatch.nightInterval / 60)) min after dark, \(Int(NightWatch.dayInterval / 60)) min by day. It uses extra battery — charging overnight helps. Swiping the app away or restarting the phone stops it; just open the app again.
            Also keep Background App Refresh on (iOS Settings → General) and Low Power Mode off.
            """)
        }
    }

    func ago(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let seconds = Date().timeIntervalSince(date)
        return seconds < 60 ? "Just now" : "\(TimeText.duration(seconds)) ago"
    }

    var forecastSection: some View {
        Section {
            Toggle("Forecast alerts", isOn: $model.settings.forecastEnabled)
            Picker("Alert when Kp reaches", selection: $model.settings.forecastKp) {
                ForEach(kpChoices, id: \.self) { kp in
                    Text("Kp \(KpFormat.label(kp))\(KpFormat.gLabel(kp).map { " · \($0)" } ?? "")").tag(kp)
                }
            }
            Toggle("2–3 days ahead", isOn: $model.settings.earlyEnabled)
            Toggle("Day before", isOn: $model.settings.tomorrowEnabled)
            Toggle("Day of (tonight)", isOn: $model.settings.tonightEnabled)
        } header: {
            Text("Forecast (days ahead)")
        } footer: {
            let t = model.location.visibility
            Text("Uses NOAA's 3-day Kp forecast during your dark hours (and the 27-day outlook further out). From \(model.location.name) aurora is usually visible on the northern horizon around Kp \(t.horizon.f(1)) and overhead around Kp \(t.overhead.f(1)). You'll get another alert if the forecast is upgraded by a full Kp.")
        }
    }

    var realtimeSection: some View {
        Section {
            Toggle("Real-time alerts", isOn: $model.settings.nowcastEnabled)
            VStack(alignment: .leading) {
                HStack {
                    Text("Bz at or below")
                    Spacer()
                    Text("\(model.settings.bzThreshold.f(0)) nT").monospacedDigit().foregroundStyle(Theme.south)
                }
                Slider(value: $model.settings.bzThreshold, in: -25 ... -3, step: 1)
            }
            Stepper("for \(Int(model.settings.bzMinutes)) minutes", value: $model.settings.bzMinutes, in: 5...60, step: 5)
            Toggle("Shock / sudden jump at L1", isOn: $model.settings.shockEnabled)
            Toggle("Activity level alerts", isOn: $model.settings.activityEnabled)
            Picker("Minimum level", selection: $model.settings.minActivity) {
                ForEach([ActivityLevel.possible, .likely, .strong], id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Only when it's dark", isOn: $model.settings.darknessGate)
            if model.settings.darknessGate {
                Picker("Dark means sun below", selection: $model.settings.maxSunAltitude) {
                    Text("0° (sunset)").tag(0.0)
                    Text("−6° (civil dusk)").tag(-6.0)
                    Text("−12° (nautical)").tag(-12.0)
                    Text("−18° (full dark)").tag(-18.0)
                }
            }
        } header: {
            Text("Real time (next ~30–60 min)")
        } footer: {
            Text("\"Heads up\" alerts fire when Bz stays south past your limit, when a shock hits the L1 spacecraft (it reaches Earth in 30–60 min), or when the overall aurora chance climbs. Good starting point: −7 nT for 15 min. Lower it (−5) to hear about more events, raise it (−10) for only big ones.")
        }
    }

    var otherSection: some View {
        Section {
            Toggle("CME arrival predictions", isOn: $model.settings.cmeEnabled)
            Toggle("Big solar flares", isOn: $model.settings.flareEnabled)
            if model.settings.flareEnabled {
                Picker("Flare class", selection: $model.settings.flareClass) {
                    ForEach(["M5.0", "X1.0", "X5.0"], id: \.self) { Text("\($0)+").tag($0) }
                }
            }
            Toggle("Relay NOAA watches/warnings", isOn: $model.settings.noaaEnabled)
            if model.settings.noaaEnabled {
                Stepper("K-index \(model.settings.noaaMinK) or higher", value: $model.settings.noaaMinK, in: 4...8)
            }
        } header: {
            Text("Sun & NOAA")
        }
    }

    var etiquetteSection: some View {
        Section {
            Stepper("Repeat after \(Int(model.settings.cooldownHours)) h", value: $model.settings.cooldownHours, in: 1...12)
            Toggle("Quiet hours", isOn: $model.settings.quietHoursEnabled)
            if model.settings.quietHoursEnabled {
                Stepper("From \(hourText(model.settings.quietStartHour))", value: $model.settings.quietStartHour, in: 0...23)
                Stepper("Until \(hourText(model.settings.quietEndHour))", value: $model.settings.quietEndHour, in: 0...23)
            }
            Toggle("Skip real-time alerts when overcast", isOn: $model.settings.skipWhenCloudy)
            if model.settings.skipWhenCloudy {
                Stepper("Cloud cover ≥ \(Int(model.settings.cloudLimit))%", value: $model.settings.cloudLimit, in: 50...100, step: 5)
            }
            Button("Reset alert memory") { model.resetAlertMemory() }
        } header: {
            Text("Repeats & quiet hours")
        } footer: {
            Text("A real-time alert won't repeat for the same condition until the repeat time passes, unless things get stronger. Quiet hours silence real-time alerts only — forecasts and CME warnings still come through.")
        }
    }

    var locationSection: some View {
        Section {
            TextField("Name", text: $model.settings.location.name)
            HStack {
                Text("Latitude")
                Spacer()
                TextField("Latitude", value: $model.settings.location.latitude, format: .number.precision(.fractionLength(4)))
                    .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation)
            }
            HStack {
                Text("Longitude")
                Spacer()
                TextField("Longitude", value: $model.settings.location.longitude, format: .number.precision(.fractionLength(4)))
                    .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation)
            }
            Picker("Time zone", selection: $model.settings.location.timeZoneID) {
                ForEach(timeZones, id: \.self) { Text($0).tag($0) }
            }
            Button("Reset to Grand Forks, ND") { model.settings.location = .grandForks }
            LabeledContent("Geomagnetic latitude", value: "\(model.location.geomagneticLatitude.f(1))°")
            TextField("NASA API key (optional)", text: $nasaKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit { Store.shared.nasaAPIKey = nasaKey }
                .onChange(of: nasaKey) { Store.shared.nasaAPIKey = $0 }
        } header: {
            Text("Location")
        } footer: {
            Text("The NASA key is only used if the keyless CME source is down. Get one free at api.nasa.gov.")
        }
    }

    var timeZones: [String] {
        var zones = ["America/Chicago", "America/Denver", "America/Winnipeg", "America/New_York", "America/Los_Angeles", "America/Anchorage"]
        let current = model.settings.location.timeZoneID
        if !zones.contains(current) { zones.insert(current, at: 0) }
        return zones
    }

    var statusText: String {
        switch notificationStatus {
        case .authorized: return "On"
        case .denied: return "Off — enable in iOS Settings"
        case .provisional, .ephemeral: return "Quiet"
        default: return "Not set up"
        }
    }

    func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section("Background refresh") {
                LabeledContent("Status", value: refreshStatus)
                LabeledContent("Last background run", value: Store.shared.lastBackgroundRun?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                LabeledContent("Night Watch", value: NightWatch.shared.isRunning ? "Running" : "Off")
            }
            let planned = Store.shared.alertState.planned.values.sorted { $0.fireDate < $1.fireDate }
            if !planned.isEmpty {
                Section("Reminders booked with iOS") {
                    ForEach(planned, id: \.key) { plan in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.alert.title).font(.subheadline)
                            Text(plan.fireDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let errors = model.snapshot?.errors, !errors.isEmpty {
                Section("Feeds with problems") {
                    ForEach(errors.sorted(by: { $0.key < $1.key }), id: \.key) { LabeledContent($0.key, value: $0.value) }
                }
            }
            Section("Activity log") {
                ForEach(Store.shared.activityLog.reversed(), id: \.self) { Text($0).font(.caption) }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Diagnostics")
        .screenBackground()
    }

    var refreshStatus: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return "Available"
        case .denied: return "Turned off"
        case .restricted: return "Restricted (Low Power Mode?)"
        @unknown default: return "Unknown"
        }
    }
}

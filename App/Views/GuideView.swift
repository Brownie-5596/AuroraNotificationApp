import AuroraKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            NowView()
                .tabItem { Label("Now", systemImage: "sparkles") }
                .tag(AppModel.Tab.now)
            ForecastView()
                .tabItem { Label("Forecast", systemImage: "calendar") }
                .tag(AppModel.Tab.forecast)
            SkyView()
                .tabItem { Label("Sky & Sun", systemImage: "sun.max") }
                .tag(AppModel.Tab.sky)
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
                .tag(AppModel.Tab.alerts)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppModel.Tab.settings)
        }
        .task {
            guard !UserDefaults.standard.bool(forKey: "uiSmoke") else { return }
            if await Notifier.status() == .notDetermined { _ = await Notifier.requestPermission() }
        }
    }
}

/// Plain-language primer on reading the data, and what the alerts are based on.
struct GuideView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let t = model.location.visibility
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("The chain of events", """
                1. The Sun throws out plasma — either a **CME** (an eruption, often after a big flare) or a **high-speed stream** from a coronal hole.
                2. It takes **1–4 days** to cross to Earth. Faster CMEs arrive sooner (Forecast → travel-time calculator).
                3. Spacecraft at **L1**, 1.5 million km out, measure it **30–60 minutes** before it hits Earth. That's your short-range warning.
                4. If the magnetic field in it points **south (negative Bz)**, it connects with Earth's field and dumps energy in → aurora.
                """)
                section("Kp index", """
                Kp (0–9) measures how disturbed Earth's magnetic field is over 3 hours. Higher Kp pushes the aurora further south. For \(model.location.name) (geomagnetic latitude \(model.location.geomagneticLatitude.f(0))°):
                • Kp \(t.camera.f(1))+ — maybe on a phone/camera long exposure, low in the north
                • Kp \(t.horizon.f(1))+ — usually visible by eye on the northern horizon
                • Kp \(t.overhead.f(1))+ — can be overhead
                NOAA writes Kp in thirds: 5- = 4.67, 5 = 5.00, 5+ = 5.33. G1 storms start at 5-.
                """)
                section("Bz — the most important number", """
                Bz is the north–south direction of the solar wind's magnetic field (in nT). **Negative = south = good.**
                • Brief dips don't do much. Bz needs to stay south for **15–30+ minutes**.
                • −5 nT sustained: minor activity. −10 nT: good chance. −20 nT or lower: major storm.
                • The Bz card shows how long it's been south, the lowest value and the total "nT·minutes", so you can judge if energy is piling up.
                """)
                section("Speed, density, Bt", """
                • **Speed**: normal ~350–400 km/s; 500+ is fast, 700+ very fast. Faster wind multiplies the effect of southward Bz.
                • **Density**: more particles = more pressure; a sudden jump with speed means a shock (CME front) has arrived.
                • **Bt**: total field strength. High Bt (15+ nT) means Bz *can* go strongly south — watch it.
                • **Ey = speed × southward Bz**: one number for how hard the solar wind is driving. Above ~3 mV/m substorms are likely.
                """)
                section("Hemispheric power & OVATION", """
                **Hemispheric power** (GW) is the estimated energy going into the aurora. 50+ GW is active; 100+ GW is a good show.
                **OVATION** is NOAA's 30–90 minute aurora map. The app reads the probability in the sky north of you.
                """)
                section("What triggers alerts", """
                **Forecast** — NOAA's 3-day Kp forecast during your dark hours reaches your Kp setting: one alert 2–3 days ahead, one the day before, one the day of. Upgrades by a full Kp alert again.
                **CME** — NASA's WSA-ENLIL model predicts an Earth impact; another alert when the arrival window is <8 h away.
                **Heads up** — Bz stays at or below your limit for your chosen minutes, or a shock hits L1 (with time-to-Earth).
                **Happening now** — the aurora chance score (Kp, Ey, hemispheric power, OVATION) reaches Possible / Likely / Strong.
                Real-time alerts only fire when it's dark (configurable) and repeat at most every \(Int(model.settings.cooldownHours)) h unless things get stronger.
                """)
                section("Viewing tips", """
                • Get away from town lights and look **north**. A phone in night mode often shows colour your eyes can't.
                • Activity comes in waves (substorms) that last 15–45 min — if it fades, wait.
                • Best hours are usually 10 PM–2 AM local, but strong storms can go all night.
                """)
                section("About alerts while the app is closed", """
                iOS — not the app — decides when sideloaded apps may run in the background: at best every few hours, never after you swipe the app away, and not in Low Power Mode.
                • **Forecast alerts** (tonight, tomorrow night, CME arrival) are booked with iOS in advance, so they arrive even if the app stays closed.
                • **Real-time heads-ups** need the app running. Turn on **Night Watch** (Settings) to keep it checking every few minutes after dark, or use a Shortcuts automation to trigger checks at set times.
                """)
                Text("Data: NOAA SWPC, NASA DONKI/CCMC, Open-Meteo. Not an official forecast.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("How it works")
        .screenBackground()
    }

    func section(_ title: String, _ body: String) -> some View {
        Card(title: title, systemImage: "book") {
            Text(LocalizedStringKey(body)).font(.subheadline)
        }
    }
}

struct PushSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(title: "Why", systemImage: "questionmark.circle") {
                    Text("An alternative to Night Watch that doesn't use your phone's battery: the same alert engine runs on GitHub Actions and pushes to the free **ntfy** app. Note: GitHub heavily delays scheduled runs on small repos (this repo's every-10-minute schedule has been running only every 3–5 hours), so for real-time alerts you also need an outside timer — step 5.")
                        .font(.subheadline)
                }
                Card(title: "Setup (5 minutes)", systemImage: "list.number") {
                    Text(LocalizedStringKey("""
                    1. Install **ntfy** from the App Store and subscribe to a hard-to-guess topic, e.g. `aurora-gf-7k2p9x`.
                    2. In the GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**, name `NTFY_TOPIC`, value = your topic.
                    3. Optional: edit `Watcher/settings.json` in the repo to change thresholds (same options as this screen).
                    4. Open **Actions → Aurora watcher → Run workflow** once to test.
                    5. For on-time runs: create a fine-grained GitHub token with **Actions: read & write** for this repo, then make a free job at **cron-job.org** that every 10 minutes sends `POST https://api.github.com/repos/Brownie-5596/AuroraNotificationApp/actions/workflows/aurora-watcher.yml/dispatches` with header `Authorization: Bearer <token>` and body `{"ref":"claude/aurora-notification-ios-app-e2ucwa"}`.
                    """)).font(.subheadline)
                }
                Card(title: "Notes", systemImage: "info.circle") {
                    Text("GitHub pauses scheduled workflows after 60 days without repo activity (runs started from cron-job.org keep going). You can keep this app's own alerts on too; the two don't share state, so you may occasionally get both.")
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle("Push alerts via ntfy")
        .screenBackground()
    }
}

struct ShortcutsHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(title: "Why", systemImage: "questionmark.circle") {
                    Text("Shortcuts automations run when *you* say, not when iOS feels like it. The app adds a **Check for Aurora** action that runs quietly in the background and sends any alerts — a good backup to Night Watch, or a battery-friendly alternative.")
                        .font(.subheadline)
                }
                Card(title: "Set up (iOS 17 or later)", systemImage: "list.number") {
                    Text(LocalizedStringKey("""
                    1. Open **Shortcuts → Automation → + → Time of Day**.
                    2. Pick a time (e.g. 9:00 PM), **Daily**, and choose **Run Immediately** (turn off *Notify When Run*).
                    3. Tap **New Blank Automation → Add Action**, search **Aurora Watch** and choose **Check for Aurora**.
                    4. Repeat for more times through the night — e.g. every 30 or 60 minutes from 9 PM to 2 AM.
                    Tip: a **Charger → Is Connected** automation runs a check whenever you plug in for the night.
                    """)).font(.subheadline)
                }
                Card(title: "Try it", systemImage: "mic") {
                    Text("You can also say \"Check for aurora with Aurora Watch\" to Siri.")
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle("Shortcuts")
        .screenBackground()
    }
}

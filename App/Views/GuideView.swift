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
                NOAA writes Kp in thirds: 5- = 4.67, 5o = 5.00, 5+ = 5.33. G1 storms start at 5-.
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
                section("About background alerts on iOS", """
                iOS — not the app — decides when background refreshes run. Usually every 15 min to a few hours, more often if you open the app regularly; never if you force-quit it or Low Power Mode is on. Forecast alerts are reliable this way; the 30-minute heads-ups may arrive late. For dependable real-time pushes, set up the optional cloud watcher (Settings → Reliable push alerts).
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
            Text(.init(body)).font(.subheadline)
        }
    }
}

struct PushSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(title: "Why", systemImage: "questionmark.circle") {
                    Text("Sideloaded apps can't receive Apple push notifications, and iOS limits background refreshes. To get real-time alerts within ~10 minutes, the same alert engine can run for free on GitHub Actions and push to the **ntfy** app.")
                        .font(.subheadline)
                }
                Card(title: "Setup (5 minutes)", systemImage: "list.number") {
                    Text(.init("""
                    1. Install **ntfy** from the App Store and subscribe to a hard-to-guess topic, e.g. `aurora-gf-7k2p9x`.
                    2. In the GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**, name `NTFY_TOPIC`, value = your topic.
                    3. Optional: edit `Watcher/settings.json` in the repo to change thresholds (same options as this screen).
                    4. Make sure the code is on the default branch — GitHub only runs scheduled workflows there. Then open **Actions → Aurora watcher → Run workflow** once to test.
                    """)).font(.subheadline)
                }
                Card(title: "Notes", systemImage: "info.circle") {
                    Text("The watcher runs every ~10 minutes (GitHub sometimes delays scheduled runs). GitHub pauses scheduled workflows after 60 days without repo activity — re-enable it on the Actions tab if that happens. You can keep this app's own alerts on too; the two don't share state, so you may occasionally get both.")
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle("Reliable push alerts")
        .screenBackground()
    }
}

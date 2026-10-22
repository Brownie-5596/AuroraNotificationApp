# Aurora Watch 🌌

A sideloadable iOS app that tells you when there's a real chance of seeing the northern lights from **Grand Forks, ND** (or anywhere you set). It shows a Pettus Plots–style live space-weather dashboard and sends notifications days ahead, the day before, the day of, and in the ~30 minutes before something happens.

## What's in the app

**Now** (live dashboard)
- **Aurora chance score (0–100)** for your location, with the reasons behind it: Kp, Bz, solar wind speed, hemispheric power, OVATION, darkness, clouds and moon.
- Tiles: Kp (in NOAA thirds, e.g. `5-`), NOAA R/S/G scales, Bz, Bt, speed, density, temperature, Ey (coupling), hemispheric power, X-ray class, OVATION %, dynamic pressure.
- **Bz streak card:** how long Bz has been south, the lowest and average value, total nT·min, time spent below your alert threshold, and the share of the last 3 h that was south.
- **Time to Earth:** what L1 measures now reaches Earth in N minutes (from NOAA's propagated solar wind). Shock detection with an impact time. CME arrival countdowns.
- Charts with 30M–24H ranges: Bz/Bt (south shaded red), Bx/By, speed, density, temperature, Ey, 7-day Kp with forecast, hemispheric power, 1-min Kp, GOES magnetometers, GOES X-ray.

**Forecast**
- Tonight + the next 3 nights: highest Kp *during your dark hours*, the peak time, what you'll likely see, cloud cover (Open-Meteo), moon.
- NOAA 3-day Kp forecast, 3-day geomagnetic probabilities, NOAA scales outlook, 27-day outlook chart.
- **CMEs heading for Earth** (NASA WSA-ENLIL via DONKI): arrival time ±7 h, Kp estimate, plus a drag-based-model estimate from the CME's launch speed.
- **CME travel-time calculator**: slide the launch speed, get the arrival time.
- Full text of NOAA's 3-Day Forecast, 3-Day Geomagnetic Forecast and 27-Day Outlook.

**Sky & Sun** — OVATION aurora map (24 h animation), WSA-ENLIL animation, SUVI 195/304, LASCO C2/C3, CCOR-1.

**Alerts** — your alert history and NOAA's watches/warnings/alerts feed.

**Settings** — every threshold below, plus test notification, "check now", a plain-English guide to reading the data, and diagnostics.

## The alerts

| Alert | Fires when | Default |
| --- | --- | --- |
| 🔭 Outlook (2–3 days) | NOAA forecast / 27-day outlook reaches your Kp during your dark hours | Kp 5- (G1) |
| 🌌 Tomorrow night | Same, for tomorrow night | Kp 5- |
| 🌌 Tonight | Same, for tonight | Kp 5- |
| ☀️ CME heading for Earth | NASA's ENLIL model predicts an Earth impact; a second alert when arrival is < 8 h away | on |
| ⚡ Shock at L1 | Solar wind speed jumps ≥ 60 km/s with compressed density/field — includes time to Earth | on |
| 🧲 Heads up: Bz south | Bz averages ≤ your limit for your chosen minutes | −7 nT for 15 min |
| 👀 / 🌌 / 🚨 Activity | Aurora chance reaches Possible / Likely / Strong | Possible |
| ☀️ Big flare | X-ray flare at or above a class | X1 |
| NOAA relay | NOAA K-index warnings/alerts, G watches, sudden impulses | K ≥ 5 |

Forecast alerts re-fire only if the forecast is upgraded by a full Kp. Real-time alerts are only sent when it's dark (sun below −6° by default), repeat at most every 3 h unless conditions get stronger, and can be muted with quiet hours or when it's overcast.

From Grand Forks (geomagnetic latitude ≈ 56°) the app treats Kp ≈ 3.6 as "maybe on camera", ≈ 4.1 as "visible on the northern horizon" and ≈ 5.1 as "could be overhead".

## Install (sideload)

Every push builds an unsigned `.ipa` on GitHub's macOS runners.

1. Go to the repo's **Releases → "Aurora Watch (latest build)"** and download `AuroraWatch.ipa` (or grab it from the latest **Build IPA** run under **Actions → Artifacts**).
2. Install it with **Sideloadly**, **AltStore** or **SideStore** — they sign it with your Apple ID.
3. **AltStore / SideStore auto-updates:** add this source:
   `https://github.com/Brownie-5596/AuroraNotificationApp/releases/download/latest/altstore-source.json`
4. Open the app, allow notifications, and make sure **Settings → General → Background App Refresh** is on for Aurora Watch.
5. For real-time heads-ups while the app is closed, turn on **Night Watch** (see [below](#alerts-while-the-app-is-closed)).

The app uses no special entitlements (no push, app groups or extensions), so it works with a free Apple ID. Free-account apps expire after 7 days unless AltStore/SideStore refreshes them.

### Building it yourself (Mac)

```sh
brew install xcodegen
xcodegen generate
open AuroraWatch.xcodeproj
```

## Alerts while the app is closed

iOS decides when a sideloaded app may run in the background (at best every few hours, never after you swipe it away, not in Low Power Mode), and sideloaded apps can't receive Apple push notifications. The app works around this in layers:

| What | How it reaches you when the app is closed |
| --- | --- |
| Tonight / tomorrow night / CME arrival alerts | **Booked with iOS in advance** each time the app runs, so they go off on time even if the app never runs again |
| Real-time heads-ups (Bz, shocks, activity) | **Night Watch** (Settings → When the app is closed): keeps the app running in the background with silent audio and checks every 3 min after dark, 20 min by day. Uses extra battery; stops if you swipe the app away or restart — open the app to resume |
| Extra checks | iOS background refresh (quick ~100 KB check), an overnight "processing" task, and a **Check for Aurora** Shortcuts action you can run from Time-of-Day or "charger connected" automations |

Settings shows when the last check ran, whether Night Watch is running, and which reminders are booked (more in Settings → Diagnostics).

### Optional: push via GitHub Actions + ntfy

The same alert engine (`Packages/AuroraKit`) can run on GitHub Actions and push to the free **[ntfy](https://ntfy.sh)** app — no phone battery needed.

1. Install **ntfy** from the App Store and subscribe to a hard-to-guess topic, e.g. `aurora-gf-7k2p9x`.
2. In this repo: **Settings → Secrets and variables → Actions → New repository secret** → name `NTFY_TOPIC`, value = your topic.
3. Optionally edit [`Watcher/settings.json`](Watcher/settings.json) to change the thresholds (same options as in the app; `minActivity`: 1 = Possible, 2 = Likely, 3 = Strong).
4. Test it with **Actions → Aurora watcher (ntfy push) → Run workflow** and tick **Send a test notification** (or "dry run" to just see what it would send).
5. **Important:** GitHub heavily throttles scheduled workflows on small repos — this repo's every-10-minute schedule has actually been running every 3–5 hours. For on-time checks, trigger it from outside: create a fine-grained GitHub token with *Actions: read and write* for this repo, then add a free job on [cron-job.org](https://cron-job.org) that every 10 minutes sends
   `POST https://api.github.com/repos/Brownie-5596/AuroraNotificationApp/actions/workflows/aurora-watcher.yml/dispatches`
   with headers `Authorization: Bearer <token>` and `Accept: application/vnd.github+json`, and body `{"ref":"claude/aurora-notification-ios-app-e2ucwa"}`.

GitHub pauses schedules after 60 days without repo activity (runs triggered from cron-job.org are unaffected). The repo is public, so Actions minutes are free.

## How it works

```
App/                      SwiftUI app (iOS 16+)
Packages/AuroraKit/       Shared engine — runs on iOS and Linux
  Sources/AuroraKit/
    SpaceWeatherClient    downloads ~20 NOAA/NASA/Open-Meteo feeds
    Parsing               lenient parsers for every feed
    SolarWind             Bz streaks, Ey, shock detection, L1→Earth travel time
    Outlook               aurora chance score + night-by-night forecast
    Alerts                the alert rules, de-duplication and settings
    Astronomy             sun altitude / darkness, moon, geomagnetic latitude
    CMETransit            drag-based CME travel-time model
  Sources/AuroraWatchCLI  the cloud watcher (ntfy)
  Tests/                  unit tests with real NOAA fixtures
Watcher/settings.json     thresholds for the cloud watcher
```

CI: **Build IPA** (Linux engine tests + unsigned IPA + release), **UI smoke test** (launches the app in the iOS Simulator against live data and screenshots every tab — see the run's artifacts), and the optional **Aurora watcher**.

Run the engine tests on any machine with Swift: `swift test --package-path Packages/AuroraKit`.
Try the watcher locally without sending anything: `swift run --package-path Packages/AuroraKit aurora-watch --dry-run`.

**Data sources:** NOAA Space Weather Prediction Center (real-time solar wind, Kp, forecasts, OVATION, alerts, imagery), NASA CCMC DONKI (WSA-ENLIL CME runs), Open-Meteo (clouds). Not an official forecast — the sky gets the final say.

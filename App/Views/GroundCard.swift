import AuroraKit
import SwiftUI

/// The nearest ground magnetometer: how far the field is from normal, and its recent swings.
struct GroundCard: View {
    var snapshot: SpaceWeatherSnapshot
    var station: GroundStation
    var location: ObserverLocation
    var threshold: Double

    var body: some View {
        let now = Date()
        let tz = location.timeZone
        let lt = LocalTime(tz: tz)
        let reading = snapshot.groundReading(now: now)
        let sorted = snapshot.groundMag.map(\.x).sorted()
        let baseline = reading?.baseline ?? (sorted.isEmpty ? 0 : sorted[sorted.count / 2])
        let points = snapshot.groundMag.map { TimePoint(time: $0.time, value: $0.x - baseline) }
        let km = Int((station.distanceKm(to: location) / 10).rounded()) * 10
        Card(title: "Nearby magnetometer", systemImage: "location.north.line", info: .ground) {
            if let r = reading {
                VStack(alignment: .leading, spacing: 3) {
                    (Text("\(r.level.title): ").bold().foregroundColor(Theme.groundColor(r.level))
                     + Text("\(r.deviation.signedWhole) nT from normal, \(Int(r.range60)) nT swing in the last hour."))
                        .font(.subheadline)
                    if let s = r.surge, abs(s.change) >= threshold / 2 {
                        Text("Biggest 15-min change: \(s.change.signedWhole) nT at \(lt.time(s.time))\(abs(s.change) >= threshold ? " — a substorm" : "").")
                            .font(.caption).foregroundStyle(abs(s.change) >= threshold ? Theme.aurora : .secondary)
                    }
                    if !r.isFresh(now: now) {
                        Text("Latest data is from \(lt.time(r.time)) — the station may be offline.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                Text(snapshot.groundMag.isEmpty
                     ? "No data from \(station.name) yet."
                     : "Collecting data — a reading needs about 2 hours of it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ExpandableChart(info: .ground, range: .h6) { r, big in
                SeriesChart(title: "\(station.name) — change from normal", unit: "nT", points: points, color: .mint, range: r,
                            rules: [(0, "normal"), (-150, "active"), (-300, "storm")],
                            height: big ? 300 : 140, tz: tz, info: .ground, interactive: big)
            }
            Text("\(km) km from \(location.name). Data: \(station.source == .nrcan ? "Natural Resources Canada" : "USGS").")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Shown at the top of the Now tab while alerts are snoozed or you're out.
struct OutingBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let lt = LocalTime(tz: model.location.timeZone)
        if let until = model.outUntil {
            banner(icon: "figure.walk", title: "You're out until \(lt.time(until))",
                   detail: "Checking every minute. You'll only hear about stronger activity, a substorm, or when it fades.",
                   button: "I'm back")
        } else if let until = model.snoozedUntil {
            banner(icon: "moon.zzz", title: "Alerts snoozed until \(lt.dayTime(until))",
                   detail: "No real-time alerts until then. CME news and forecasts for later nights still come through.",
                   button: "Resume")
        }
    }

    func banner(icon: String, title: String, detail: String, button: String) -> some View {
        Card(title: nil, systemImage: nil, info: nil) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(Theme.aurora)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(button) { OutingControl.resume() }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
            }
        }
    }
}

/// Toolbar menu with the same choices as the notification buttons.
struct OutingMenu: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Menu {
            Button { OutingControl.headOut() } label: { Label("I'm heading out", systemImage: "figure.walk") }
            Button { Task { await OutingControl.snooze(until: Date().addingTimeInterval(3600)) } } label: {
                Label("Snooze alerts 1 hour", systemImage: "moon.zzz")
            }
            Button { Task { await OutingControl.snoozeTonight() } } label: {
                Label("Snooze alerts tonight", systemImage: "bed.double")
            }
            if model.snoozedUntil != nil || model.outUntil != nil {
                Divider()
                Button { OutingControl.resume() } label: { Label("Back to normal alerts", systemImage: "bell") }
            }
        } label: {
            Image(systemName: model.outUntil != nil ? "figure.walk.circle.fill"
                  : (model.snoozedUntil != nil ? "moon.zzz.fill" : "figure.walk.circle"))
        }
        .accessibilityLabel("Heading out or snooze alerts")
    }
}

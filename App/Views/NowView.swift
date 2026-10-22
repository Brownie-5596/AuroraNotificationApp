import AuroraKit
import SwiftUI

struct NowView: View {
    @EnvironmentObject var model: AppModel
    @State private var range: ChartRange = .h6
    @AppStorage("nightWatchEnabled") private var nightWatchEnabled = false
    @AppStorage("nightWatchPromptDismissed") private var promptDismissed = false
    @ObservedObject private var nightWatch = NightWatch.shared

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if let snapshot = model.snapshot, let nowcast = model.nowcast {
                            header(snapshot)
                            if !nightWatchEnabled && !promptDismissed { nightWatchPrompt }
                            ChanceCard(nowcast: nowcast, location: model.location)
                            TilesGrid(snapshot: snapshot, nowcast: nowcast).id("tiles")
                            BzStreakCard(snapshot: snapshot, threshold: model.settings.bzThreshold, tz: model.location.timeZone)
                            ArrivalCard(snapshot: snapshot, nowcast: nowcast, tz: model.location.timeZone)
                            solarWindCharts(snapshot).id("wind")
                            indicesCharts(snapshot).id("indices")
                        } else {
                            ProgressView("Loading space weather…").padding(.top, 80)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .onChange(of: model.snapshot?.fetchedAt) { _ in scrollForSmokeTest(proxy) }
                .onAppear { scrollForSmokeTest(proxy) }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Aurora Now")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if model.isRefreshing { ProgressView() }
                }
            }
            .screenBackground()
        }
    }

    /// `-scrollTo wind` launch argument, used by the UI smoke test to screenshot further down.
    func scrollForSmokeTest(_ proxy: ScrollViewProxy) {
        guard let anchor = UserDefaults.standard.string(forKey: "scrollTo") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(anchor, anchor: .top) }
    }

    func header(_ snapshot: SpaceWeatherSnapshot) -> some View {
        HStack {
            Label(model.location.name, systemImage: "location.fill").font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Updated \(LocalTime(tz: model.location.timeZone).time(snapshot.fetchedAt))")
                if let source = snapshot.magSource ?? snapshot.plasmaSource {
                    Text("L1 spacecraft: \(source)")
                }
                if nightWatch.isRunning {
                    Label("Night Watch on", systemImage: "moon.stars.fill").foregroundStyle(Theme.aurora)
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    var nightWatchPrompt: some View {
        Card(title: "Get real-time alerts with the app closed", systemImage: "moon.stars.fill") {
            Text("iOS rarely lets sideloaded apps check in the background, so \"heads up\" alerts can be hours late. Night Watch keeps the app running and checks every few minutes after dark. It uses extra battery.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Turn on Night Watch") {
                    nightWatchEnabled = true
                    nightWatch.start()
                }
                .buttonStyle(.borderedProminent)
                Button("Not now") { promptDismissed = true }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    func solarWindCharts(_ snapshot: SpaceWeatherSnapshot) -> some View {
        let tz = model.location.timeZone
        Card(title: "Solar wind — real time", systemImage: "wind") {
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            BzChart(samples: snapshot.mag, range: range, threshold: model.settings.bzThreshold, tz: tz)
            MultiSeriesChart(
                title: "Bx / By", unit: "nT",
                points: snapshot.mag.flatMap { s -> [TimePoint] in
                    [s.bx.map { TimePoint(time: s.time, value: $0, series: "Bx") },
                     s.by.map { TimePoint(time: s.time, value: $0, series: "By") }].compactMap { $0 }
                },
                colors: ["Bx": .orange, "By": .teal], range: range, tz: tz, height: 110
            )
            SeriesChart(
                title: "Speed", unit: "km/s",
                points: snapshot.plasma.compactMap { s in s.speed.map { TimePoint(time: s.time, value: $0) } },
                color: Theme.violet, range: range, rules: [(500, "fast"), (700, "very fast")], tz: tz
            )
            SeriesChart(
                title: "Density", unit: "p/cm³",
                points: snapshot.plasma.compactMap { s in s.density.map { TimePoint(time: s.time, value: $0) } },
                color: .cyan, range: range, height: 110, tz: tz
            )
            SeriesChart(
                title: "Temperature", unit: "K",
                points: snapshot.plasma.compactMap { s in s.temperature.map { TimePoint(time: s.time, value: $0) } },
                color: .yellow, range: range, height: 100, tz: tz
            )
            SeriesChart(
                title: "Ey = V × Bs (coupling)", unit: "mV/m",
                points: electricField(snapshot), color: .pink, range: range,
                rules: [(3, "substorms"), (6, "storm")], height: 110, tz: tz
            )
        }
    }

    @ViewBuilder
    func indicesCharts(_ snapshot: SpaceWeatherSnapshot) -> some View {
        let tz = model.location.timeZone
        Card(title: "Planetary Kp — 7 days + forecast", systemImage: "chart.bar.fill") {
            KpBarChart(points: kpSeries(snapshot), thresholds: model.location.visibility, tz: tz)
            Text("Solid = observed, faded = forecast. Dashed lines show the Kp \(model.location.name) needs to see aurora on the horizon / overhead.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        Card(title: "Auroral activity", systemImage: "sparkles") {
            SeriesChart(
                title: "Hemispheric power (north)", unit: "GW",
                points: snapshot.hemiPower.map { TimePoint(time: $0.observed, value: $0.north) },
                color: Theme.aurora, range: .h24, rules: [(50, "active"), (100, "strong")], tz: tz
            )
            SeriesChart(
                title: "Estimated Kp (1-min)", unit: "",
                points: snapshot.kp1m.map { TimePoint(time: $0.time, value: $0.kp) },
                color: .orange, range: .h6, height: 100, tz: tz
            )
        }
        Card(title: "GOES magnetometers", systemImage: "dot.radiowaves.left.and.right") {
            MultiSeriesChart(
                title: "Hp", unit: "nT",
                points: snapshot.goesPrimary.map { TimePoint(time: $0.time, value: $0.hp, series: "GOES-\($0.satellite)") }
                    + snapshot.goesSecondary.map { TimePoint(time: $0.time, value: $0.hp, series: "GOES-\($0.satellite)") },
                colors: goesColors(snapshot), range: .h24, tz: tz
            )
            Text("Sudden jumps mark shocks hitting Earth's magnetic field; sharp dips and recoveries often accompany substorms.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        Card(title: "Sun — X-ray flux", systemImage: "sun.max.fill") {
            XrayChart(samples: snapshot.xray, tz: tz)
            if let flare = snapshot.latestFlare, let cls = flare.maxClass {
                Text("Latest flare: \(cls)" + (flare.peak.map { " at \(LocalTime(tz: tz).dayTime($0))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func goesColors(_ snapshot: SpaceWeatherSnapshot) -> KeyValuePairs<String, Color> {
        let a = "GOES-\(snapshot.goesPrimary.first?.satellite ?? 19)"
        let b = "GOES-\(snapshot.goesSecondary.first?.satellite ?? 18)"
        return [a: .blue, b: .red]
    }

    func kpSeries(_ snapshot: SpaceWeatherSnapshot) -> [KpPoint] {
        let observed = snapshot.kpObserved
        let lastObserved = observed.last?.time ?? .distantPast
        let future = snapshot.kpForecast.filter { $0.time > lastObserved }
        return Array((observed + future).suffix(80))
    }

    func electricField(_ snapshot: SpaceWeatherSnapshot) -> [TimePoint] {
        var speedByMinute: [Int: Double] = [:]
        for p in snapshot.plasma { if let v = p.speed { speedByMinute[Int(p.time.timeIntervalSince1970 / 60)] = v } }
        var lastSpeed = snapshot.latestPlasma?.speed ?? 400
        return snapshot.mag.compactMap { m in
            guard let bz = m.bz else { return nil }
            if let v = speedByMinute[Int(m.time.timeIntervalSince1970 / 60)] { lastSpeed = v }
            return TimePoint(time: m.time, value: SolarWind.electricField(speed: lastSpeed, bz: bz))
        }
    }
}

struct ChanceCard: View {
    var nowcast: Nowcast
    var location: ObserverLocation

    var body: some View {
        let lt = LocalTime(tz: location.timeZone)
        Card {
            HStack(alignment: .center, spacing: 16) {
                ScoreRing(score: nowcast.score, level: nowcast.level)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aurora chance now").font(.caption).foregroundStyle(.secondary)
                    Text(nowcast.headline).font(.headline)
                    Text(nowcast.visibility.description).font(.subheadline).foregroundStyle(Theme.aurora)
                    HStack(spacing: 10) {
                        Label(nowcast.isDark ? "Dark" : "Sun \(nowcast.sunAltitude.f(0))°",
                              systemImage: nowcast.isDark ? "moon.stars.fill" : "sun.horizon.fill")
                        Label("\(Int(nowcast.moonIllumination * 100))%", systemImage: "moonphase.waxing.gibbous")
                        if let c = nowcast.cloudCover { Label("\(Int(c))%", systemImage: "cloud.fill") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !nowcast.dataIsFresh {
                Label("Live solar wind data is delayed — real-time alerts are paused until it returns.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.yellow)
            }
            Divider().overlay(Color.white.opacity(0.1))
            ForEach(nowcast.factors) { FactorRow(factor: $0) }
            if let dark = Sky.darkWindow(nightOf: Sky.currentNightOf(now: Date(), location: location), location: location) {
                Text("Dark tonight \(lt.time(dark.start)) – \(lt.time(dark.end)) (sun 12° below horizon)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct TilesGrid: View {
    var snapshot: SpaceWeatherSnapshot
    var nowcast: Nowcast

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        let kp = nowcast.estimatedKp ?? snapshot.latestKp?.kp
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("NOAA scales").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ScaleBadge(letter: "R", value: snapshot.scales?.current?.r)
                ScaleBadge(letter: "S", value: snapshot.scales?.current?.s)
                ScaleBadge(letter: "G", value: snapshot.scales?.current?.g)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                Group {
                    StatTile(title: "Kp", value: kp.map { KpFormat.label($0) } ?? "--",
                             color: kp.map(Theme.kpColor) ?? .primary,
                             footnote: kp.map { "est. \($0.f(2))" })
                    StatTile(title: "Bz", value: nowcast.bz.f(), unit: "nT",
                             color: (nowcast.bz ?? 0) < 0 ? Theme.south : Theme.north,
                             footnote: nowcast.bzMean30.map { "30m avg \($0.f())" })
                    StatTile(title: "Bt", value: snapshot.latestMag?.bt.f() ?? "--", unit: "nT")
                    StatTile(title: "Speed", value: nowcast.speed.f(0), unit: "km/s",
                             color: (nowcast.speed ?? 0) >= 500 ? .orange : .primary)
                    StatTile(title: "Density", value: nowcast.density.f(), unit: "p/cm³")
                    StatTile(title: "Temp", value: snapshot.latestPlasma?.temperature.map { "\(Int($0 / 1000))k" } ?? "--", unit: "K")
                    StatTile(title: "Ey", value: nowcast.electricField.f(), unit: "mV/m",
                             color: (nowcast.electricField ?? 0) >= 3 ? Theme.aurora : .primary)
                }
                Group {
                    StatTile(title: "Hemi power", value: nowcast.hemiPower.f(0), unit: "GW",
                             color: (nowcast.hemiPower ?? 0) >= 50 ? Theme.aurora : .primary)
                    StatTile(title: "X-ray", value: snapshot.latestXray.map { FlareClass.label(flux: $0.flux) } ?? "--")
                    StatTile(title: "OVATION", value: nowcast.ovation.map { "\($0.maxInView)" } ?? "--", unit: "%",
                             footnote: nowcast.ovation.map { "overhead \($0.overhead)%" })
                    StatTile(title: "Pressure",
                             value: (nowcast.speed.flatMap { v in nowcast.density.map { SolarWind.dynamicPressure(speed: v, density: $0) } }).f(),
                             unit: "nPa")
                    StatTile(title: "Bz south", value: nowcast.streak.map { $0.isSouth ? TimeText.duration($0.duration) : "0 min" } ?? "--",
                             color: (nowcast.streak?.isSouth ?? false) ? Theme.south : .primary)
                }
            }
        }
    }
}

struct BzStreakCard: View {
    var snapshot: SpaceWeatherSnapshot
    var threshold: Double
    var tz: TimeZone

    var body: some View {
        Card(title: "Bz — how long and how far south", systemImage: "arrow.down.to.line") {
            if let s = SolarWind.bzStreak(snapshot.mag, threshold: threshold, now: Date()) {
                let lt = LocalTime(tz: tz)
                if s.isSouth {
                    Text("Southward for **\(TimeText.duration(s.duration))** (since \(lt.time(s.since)))")
                    HStack {
                        StatTile(title: "Lowest", value: s.minimum.f(), unit: "nT", color: Theme.south)
                        StatTile(title: "Average", value: s.mean.f(), unit: "nT", color: Theme.south)
                        StatTile(title: "Total", value: "\(Int(s.integral))", unit: "nT·min")
                    }
                } else {
                    Text("Northward for **\(TimeText.duration(s.duration))** (since \(lt.time(s.since))) — the door is closed for now.")
                }
                HStack {
                    StatTile(title: "≤ \(threshold.f(0)) nT for", value: TimeText.duration(s.belowThresholdDuration),
                             color: s.belowThresholdDuration > 0 ? Theme.south : .primary)
                    StatTile(title: "South last 3 h", value: "\(Int(s.southFractionLast3h * 100))", unit: "%")
                    StatTile(title: "30-min avg", value: s.mean30.f(), unit: "nT")
                }
                Text("Aurora usually needs Bz to stay south (negative) for 15–30+ minutes. The deeper and longer, the better — and fast wind makes it hit harder.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No magnetometer data").foregroundStyle(.secondary)
            }
        }
    }
}

struct ArrivalCard: View {
    var snapshot: SpaceWeatherSnapshot
    var nowcast: Nowcast
    var tz: TimeZone

    var body: some View {
        let lt = LocalTime(tz: tz)
        Card(title: "Time to Earth", systemImage: "timer") {
            if let tt = nowcast.travelTime {
                Text("What the L1 spacecraft measure right now reaches Earth in **~\(TimeText.duration(tt))** (around \(lt.time(Date().addingTimeInterval(tt)))).")
                Text("L1 is ~1.5 million km sunward. At 400 km/s that's ~1 h; at 800 km/s ~30 min.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let shock = nowcast.shock {
                Divider().overlay(Color.white.opacity(0.1))
                Label("Shock detected at \(lt.time(shock.time)): \(Int(shock.speedBefore)) → \(Int(shock.speedAfter)) km/s", systemImage: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("Impact at Earth \(shock.earthArrival > Date() ? lt.relative(shock.earthArrival) : "has happened") (\(lt.time(shock.earthArrival))).")
                    .font(.caption)
            }
            ForEach(snapshot.cmeArrivals.filter { $0.arrival > Date().addingTimeInterval(-12 * 3600) }) { cme in
                Divider().overlay(Color.white.opacity(0.1))
                CMERow(cme: cme, tz: tz)
            }
            if snapshot.cmeArrivals.isEmpty {
                Text("No Earth-directed CMEs in NASA's model runs right now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct CMERow: View {
    var cme: CMEArrival
    var tz: TimeZone

    var body: some View {
        let lt = LocalTime(tz: tz)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(cme.isGlancingBlow ? "CME glancing blow" : "CME impact", systemImage: "sun.max.trianglebadge.exclamationmark")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Spacer()
                Text(lt.relative(cme.arrival)).font(.caption.monospacedDigit())
            }
            Text("ENLIL arrival: \(lt.dayTime(cme.arrival)) ± 7 h")
                .font(.caption)
            if let drag = cme.dragModelArrival {
                Text("Drag-model estimate from launch speed: \(lt.dayTime(drag))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let lo = cme.kpLow, let hi = cme.kpHigh { Text("Kp \(Int(lo))–\(Int(hi))") }
                if let v = cme.cmeSpeed { Text("\(Int(v)) km/s") }
                if let start = cme.cmeStart { Text("left Sun \(lt.dayTime(start))") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

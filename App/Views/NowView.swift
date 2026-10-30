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
                            if let sky = model.tonightSky {
                                TonightSkyCard(sky: sky, location: model.location).id("sky")
                            }
                            TilesGrid(snapshot: snapshot, nowcast: nowcast, location: model.location).id("tiles")
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
                ToolbarItem(placement: .navigationBarLeading) {
                    if model.isRefreshing { ProgressView() }
                }
                ToolbarItem(placement: .navigationBarTrailing) { GlossaryButton(location: model.location) }
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
        let threshold = model.settings.bzThreshold
        let bxby = snapshot.mag.flatMap { s -> [TimePoint] in
            [s.bx.map { TimePoint(time: s.time, value: $0, series: "Bx") },
             s.by.map { TimePoint(time: s.time, value: $0, series: "By") }].compactMap { $0 }
        }
        let speed = snapshot.plasma.compactMap { s in s.speed.map { TimePoint(time: s.time, value: $0) } }
        let density = snapshot.plasma.compactMap { s in s.density.map { TimePoint(time: s.time, value: $0) } }
        let temperature = snapshot.plasma.compactMap { s in s.temperature.map { TimePoint(time: s.time, value: $0) } }
        let ey = electricField(snapshot)
        Card(title: "Solar wind — real time", systemImage: "wind") {
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Tap any chart to open it full screen and read exact values.")
                .font(.caption2).foregroundStyle(.secondary)

            ExpandableChart(info: .bz, range: range) { r, big in
                BzChart(samples: snapshot.mag, range: r, threshold: threshold, tz: tz,
                        height: big ? 300 : 180, info: .bz, interactive: big)
            }
            ExpandableChart(info: .bxby, range: range) { r, big in
                MultiSeriesChart(title: "Bx / By", unit: "nT", points: bxby, colors: ["Bx": .orange, "By": .teal],
                                 range: r, tz: tz, height: big ? 300 : 110, info: .bxby, interactive: big)
            }
            ExpandableChart(info: .speed, range: range) { r, big in
                SeriesChart(title: "Speed", unit: "km/s", points: speed, color: Theme.violet, range: r,
                            rules: [(500, "fast"), (700, "very fast")], height: big ? 300 : 140, tz: tz,
                            info: .speed, interactive: big)
            }
            ExpandableChart(info: .density, range: range) { r, big in
                SeriesChart(title: "Density", unit: "p/cm³", points: density, color: .cyan, range: r,
                            height: big ? 300 : 110, tz: tz, info: .density, interactive: big)
            }
            ExpandableChart(info: .temperature, range: range) { r, big in
                SeriesChart(title: "Temperature", unit: "K", points: temperature, color: .yellow, range: r,
                            height: big ? 300 : 100, tz: tz, info: .temperature, interactive: big)
            }
            ExpandableChart(info: .ey, range: range) { r, big in
                SeriesChart(title: "Ey = V × Bs (coupling)", unit: "mV/m", points: ey, color: .pink, range: r,
                            rules: [(3, "substorms"), (6, "storm")], height: big ? 300 : 110, tz: tz,
                            info: .ey, interactive: big)
            }
        }
    }

    @ViewBuilder
    func indicesCharts(_ snapshot: SpaceWeatherSnapshot) -> some View {
        let tz = model.location.timeZone
        let kpInfo = ChartInfo.kp(model.location)
        let thresholds = model.location.visibility
        let kp = kpSeries(snapshot)
        let hemi = snapshot.hemiPower.map { TimePoint(time: $0.observed, value: $0.north) }
        let kp1m = snapshot.kp1m.map { TimePoint(time: $0.time, value: $0.kp) }
        let goes = snapshot.goesPrimary.map { TimePoint(time: $0.time, value: $0.hp, series: "GOES-\($0.satellite)") }
            + snapshot.goesSecondary.map { TimePoint(time: $0.time, value: $0.hp, series: "GOES-\($0.satellite)") }
        let goesPalette = goesColors(snapshot)
        Card(title: "Planetary Kp — 7 days + forecast", systemImage: "chart.bar.fill", info: kpInfo) {
            ExpandableChart(info: kpInfo, range: nil) { _, big in
                KpBarChart(points: kp, thresholds: thresholds, tz: tz, height: big ? 300 : 170, interactive: big)
            }
        }
        Card(title: "Auroral activity", systemImage: "sparkles") {
            ExpandableChart(info: .hemiPower, range: .h24) { r, big in
                SeriesChart(title: "Hemispheric power (north)", unit: "GW", points: hemi, color: Theme.aurora, range: r,
                            rules: [(50, "active"), (100, "strong")], height: big ? 300 : 140, tz: tz,
                            info: .hemiPower, interactive: big)
            }
            ExpandableChart(info: .kp1m, range: .h6) { r, big in
                SeriesChart(title: "Estimated Kp (1-min)", unit: "", points: kp1m, color: .orange, range: r,
                            height: big ? 300 : 100, tz: tz, info: .kp1m, interactive: big)
            }
        }
        Card(title: "GOES magnetometers", systemImage: "dot.radiowaves.left.and.right") {
            ExpandableChart(info: .goes, range: .h24) { r, big in
                MultiSeriesChart(title: "Hp", unit: "nT", points: goes, colors: goesPalette, range: r, tz: tz,
                                 height: big ? 300 : 140, info: .goes, interactive: big)
            }
        }
        Card(title: "Sun — X-ray flux", systemImage: "sun.max.fill") {
            ExpandableChart(info: .xray, range: .h24) { r, big in
                XrayChart(samples: snapshot.xray, tz: tz, range: r, height: big ? 300 : 130, info: .xray, interactive: big)
            }
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
                    HStack(spacing: 2) {
                        Text("Aurora chance now").font(.caption).foregroundStyle(.secondary)
                        InfoButton(info: .score)
                    }
                    Text(nowcast.headline).font(.headline)
                    Text(nowcast.visibility.description).font(.subheadline).foregroundStyle(Theme.aurora)
                    HStack(spacing: 10) {
                        Label(nowcast.isDark ? "Dark" : "Sun \(nowcast.sunAltitude.f(0))°",
                              systemImage: nowcast.isDark ? "moon.stars.fill" : "sun.horizon.fill")
                        Label("\(Int((nowcast.moonIllumination * 100).rounded()))%", systemImage: Sky.moonPhaseSymbol(at: Date()))
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
    var location: ObserverLocation

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        let kp = nowcast.estimatedKp ?? snapshot.latestKp?.kp
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("NOAA scales").font(.caption).foregroundStyle(.secondary)
                InfoButton(info: .scales)
                Spacer()
                ScaleBadge(letter: "R", value: snapshot.scales?.current?.r)
                ScaleBadge(letter: "S", value: snapshot.scales?.current?.s)
                ScaleBadge(letter: "G", value: snapshot.scales?.current?.g)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                Group {
                    StatTile(title: "Kp", value: kp.map { KpFormat.label($0) } ?? "--",
                             color: kp.map(Theme.kpColor) ?? .primary,
                             footnote: kp.map { "est. \($0.f(2))" }, info: .kp(location))
                    StatTile(title: "Bz", value: nowcast.bz.f(), unit: "nT",
                             color: (nowcast.bz ?? 0) < 0 ? Theme.south : Theme.north,
                             footnote: nowcast.bzMean30.map { "30m avg \($0.f())" }, info: .bz)
                    StatTile(title: "Bt", value: snapshot.latestMag?.bt.f() ?? "--", unit: "nT", info: .bt)
                    StatTile(title: "Speed", value: nowcast.speed.f(0), unit: "km/s",
                             color: (nowcast.speed ?? 0) >= 500 ? .orange : .primary, info: .speed)
                    StatTile(title: "Density", value: nowcast.density.f(), unit: "p/cm³", info: .density)
                    StatTile(title: "Temp", value: snapshot.latestPlasma?.temperature.map { "\(Int($0 / 1000))k" } ?? "--", unit: "K", info: .temperature)
                    StatTile(title: "Ey", value: nowcast.electricField.f(), unit: "mV/m",
                             color: (nowcast.electricField ?? 0) >= 3 ? Theme.aurora : .primary, info: .ey)
                }
                Group {
                    StatTile(title: "Hemi power", value: nowcast.hemiPower.f(0), unit: "GW",
                             color: (nowcast.hemiPower ?? 0) >= 50 ? Theme.aurora : .primary, info: .hemiPower)
                    StatTile(title: "X-ray", value: snapshot.latestXray.map { FlareClass.label(flux: $0.flux) } ?? "--", info: .xray)
                    StatTile(title: "OVATION", value: nowcast.ovation.map { "\($0.maxInView)" } ?? "--", unit: "%",
                             footnote: nowcast.ovation.map { "overhead \($0.overhead)%" }, info: .ovation)
                    StatTile(title: "Pressure",
                             value: (nowcast.speed.flatMap { v in nowcast.density.map { SolarWind.dynamicPressure(speed: v, density: $0) } }).f(),
                             unit: "nPa", info: .pressure)
                    StatTile(title: "Bz south", value: nowcast.streak.map { $0.isSouth ? TimeText.duration($0.duration) : "0 min" } ?? "--",
                             color: (nowcast.streak?.isSouth ?? false) ? Theme.south : .primary, info: .bzStreak)
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
        Card(title: "Bz — how long and how far south", systemImage: "arrow.down.to.line", info: .bzStreak) {
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
        Card(title: "Time to Earth", systemImage: "timer", info: .travelTime) {
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

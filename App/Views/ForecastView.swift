import AuroraKit
import Charts
import SwiftUI

struct ForecastView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if let snapshot = model.snapshot {
                            let tz = model.location.timeZone
                            nightsCard
                            Card(title: "3-day Kp forecast (3-hour blocks)", systemImage: "chart.bar.xaxis") {
                                KpBarChart(points: snapshot.kpForecast.filter { $0.end > Date().addingTimeInterval(-24 * 3600) },
                                           thresholds: model.location.visibility, tz: tz)
                                if let max = snapshot.upcomingKp(now: Date()).max(by: { $0.kp < $1.kp }) {
                                    Text("Highest expected: Kp \(KpFormat.label(max.kp))\(KpFormat.gLabel(max.kp).map { " (\($0))" } ?? "") at \(LocalTime(tz: tz).dayTime(max.time))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let probs = snapshot.geomagProbabilities, !probs.rows.isEmpty {
                                ProbabilityCard(probs: probs).id("probs")
                            }
                            if let scales = snapshot.scales { ScalesForecastCard(scales: scales) }
                            cmeCard(snapshot).id("cme")
                            TransitCalculator(windSpeed: snapshot.latestPlasma?.speed ?? 400)
                            if !snapshot.outlook27.isEmpty { OutlookCard(days: snapshot.outlook27, thresholds: model.location.visibility, tz: tz) }
                            if let product = snapshot.threeDayForecast { TextProductCard(product: product, icon: "doc.text") }
                            if let product = snapshot.geomagForecast { TextProductCard(product: product, icon: "globe.americas") }
                            if let raw = snapshot.outlook27Raw {
                                TextProductCard(product: FeedParser.textProduct(raw), icon: "calendar")
                            }
                        } else {
                            ProgressView().padding(.top, 80)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    // `-scrollTo probs|cme` launch argument for the UI smoke test.
                    if let anchor = UserDefaults.standard.string(forKey: "scrollTo") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { proxy.scrollTo(anchor, anchor: .top) }
                    }
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Forecast")
            .screenBackground()
        }
    }

    var nightsCard: some View {
        let lt = LocalTime(tz: model.location.timeZone)
        return Card(title: "Next nights in \(model.location.name)", systemImage: "moon.stars") {
            if model.nights.isEmpty {
                Text("No forecast available").foregroundStyle(.secondary)
            }
            ForEach(model.nights) { night in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title(night)).font(.headline)
                        Spacer()
                        Text("Kp \(KpFormat.label(night.maxKp))")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.kpColor(night.maxKp))
                        if night.gScale > 0 { ScaleBadge(letter: "G", value: night.gScale) }
                    }
                    Text(night.visibility.description)
                        .font(.subheadline)
                        .foregroundStyle(night.visibility >= .horizon ? Theme.aurora : .secondary)
                    HStack(spacing: 12) {
                        if let dark = night.dark { Label("\(lt.time(dark.start))–\(lt.time(dark.end))", systemImage: "moon.fill") }
                        if let t = night.maxKpTime { Label("peak \(lt.time(t))", systemImage: "arrow.up") }
                        if let c = night.cloudCover { Label("\(Int(c))%", systemImage: "cloud") }
                        Label("\(Int(night.moonIllumination * 100))%", systemImage: "moonphase.full.moon")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if night.source == .outlook27 {
                        Text("From the 27-day outlook (daily max) — low confidence this far out.")
                            .font(.caption2).foregroundStyle(.yellow.opacity(0.8))
                    }
                    ForEach(night.cmeArrivals) { cme in
                        Label("CME expected \(lt.dayTime(cme.arrival))", systemImage: "sun.max.trianglebadge.exclamationmark")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
                if night.id != model.nights.last?.id { Divider().overlay(Color.white.opacity(0.1)) }
            }
        }
    }

    func title(_ night: NightOutlook) -> String {
        switch night.daysAhead {
        case 0: return "Tonight"
        case 1: return "Tomorrow night"
        default: return TimeText.format(night.nightOf, model.location.timeZone, "EEEE, MMM d")
        }
    }

    func cmeCard(_ snapshot: SpaceWeatherSnapshot) -> some View {
        Card(title: "CMEs heading our way", systemImage: "sun.max.trianglebadge.exclamationmark") {
            let upcoming = snapshot.cmeArrivals.filter { $0.arrival > Date().addingTimeInterval(-12 * 3600) }
            if upcoming.isEmpty {
                Text(snapshot.errors["enlil"] != nil && snapshot.cmeFetchedAt == nil
                     ? "Couldn't reach NASA DONKI (\(snapshot.errors["enlil"]!))."
                     : "No Earth-directed CMEs predicted by NASA's WSA-ENLIL model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(upcoming) { cme in
                CMERow(cme: cme, tz: model.location.timeZone)
                Divider().overlay(Color.white.opacity(0.1))
            }
            Link(destination: URL(string: "https://www.swpc.noaa.gov/products/wsa-enlil-solar-wind-prediction")!) {
                Label("WSA-ENLIL model on SWPC", systemImage: "arrow.up.right.square")
            }
            .font(.caption)
        }
    }
}

struct ProbabilityCard: View {
    var probs: GeomagProbabilities

    var body: some View {
        Card(title: "3-day geomagnetic probabilities", systemImage: "percent") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, day in
                        Text(day).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                ForEach(probs.rows) { row in
                    GridRow {
                        Text(row.label).font(.caption)
                        ForEach(Array(row.values.enumerated()), id: \.offset) { _, v in
                            Text("\(v)%")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(v >= 50 ? Theme.aurora : (v >= 20 ? .yellow : .secondary))
                        }
                    }
                }
            }
            ForEach(probs.apLines, id: \.self) { Text($0).font(.caption2.monospaced()).foregroundStyle(.secondary) }
            Text("Active ≈ Kp 4 · Minor storm = G1 (Kp 5) · Moderate = G2 (Kp 6) · Strong+ = G3 or higher")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    var dayLabels: [String] {
        let count = probs.rows.first?.values.count ?? 3
        return probs.days.count == count ? probs.days : (1...count).map { "Day \($0)" }
    }
}

struct ScalesForecastCard: View {
    var scales: NOAAScales

    var body: some View {
        Card(title: "NOAA scales outlook", systemImage: "gauge.with.dots.needle.67percent") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("").font(.caption)
                    Text("Today").font(.caption.weight(.semibold))
                    ForEach(scales.forecast, id: \.date) { Text(shortDate($0.date)).font(.caption.weight(.semibold)) }
                }
                .foregroundStyle(.secondary)
                GridRow {
                    Text("Geomagnetic").font(.caption)
                    ScaleBadge(letter: "G", value: scales.current?.g)
                    ForEach(scales.forecast, id: \.date) { ScaleBadge(letter: "G", value: $0.g) }
                }
                GridRow {
                    Text("R1–R2 / R3+").font(.caption)
                    Text("—").font(.caption)
                    ForEach(scales.forecast, id: \.date) { d in
                        Text("\(d.rMinorProb ?? 0)% / \(d.rMajorProb ?? 0)%").font(.caption.monospacedDigit())
                    }
                }
                GridRow {
                    Text("S1+ radiation").font(.caption)
                    ScaleBadge(letter: "S", value: scales.current?.s)
                    ForEach(scales.forecast, id: \.date) { d in Text("\(d.sProb ?? 0)%").font(.caption.monospacedDigit()) }
                }
            }
        }
    }

    func shortDate(_ iso: String) -> String {
        guard let d = SWDate.parse(iso) else { return iso }
        return TimeText.format(d, TimeZone(identifier: "UTC")!, "MMM d")
    }
}

struct OutlookCard: View {
    var days: [OutlookDay]
    var thresholds: VisibilityThresholds
    var tz: TimeZone

    var body: some View {
        Card(title: "27-day outlook (largest daily Kp)", systemImage: "calendar") {
            Chart {
                ForEach(days, id: \.date) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Kp", d.kp))
                        .foregroundStyle(Theme.kpColor(Double(d.kp)))
                }
                RuleMark(y: .value("Horizon", thresholds.horizon))
                    .foregroundStyle(Theme.aurora.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: 0...9)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let d = value.as(Date.self) { Text(TimeText.format(d, TimeZone(identifier: "UTC")!, "MMM d")) } }
                }
            }
            .frame(height: 150)
            Text("The Sun rotates every ~27 days, so active coronal holes tend to come back around. Good for spotting likely-active periods weeks ahead.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct TextProductCard: View {
    var product: TextProduct
    var icon: String
    @State private var expanded = false

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(product.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).font(.subheadline.weight(.semibold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(section.body).font(.system(size: 11, design: .monospaced))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(product.title, systemImage: icon).font(.headline)
                    if let issued = product.issued {
                        Text("Issued \(issued.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// "If a CME left the Sun at X km/s, when would it get here?"
struct TransitCalculator: View {
    var windSpeed: Double
    @State private var speed: Double = 1000

    var body: some View {
        let estimate = CMETransit.dragBasedArrival(speed: speed, launchedAt: Date(), windSpeed: max(windSpeed, 300))
        Card(title: "CME travel-time calculator", systemImage: "hare") {
            HStack {
                Text("Launch speed")
                Spacer()
                Text("\(Int(speed)) km/s").monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: $speed, in: 300...3000, step: 50)
            if let e = estimate {
                Text("Reaches Earth in about **\(TimeText.duration(e.travelTime))**, arriving at ~\(Int(e.arrivalSpeed)) km/s.")
            }
            Text("Drag-based model (Vršnak et al.) using today's solar wind (\(Int(windSpeed)) km/s). Typical error ±10 h. A CME reported in NOAA's \"CME analysis\" with its speed can be plugged in here.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

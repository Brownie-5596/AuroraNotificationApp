import AuroraKit
import Charts
import SwiftUI

struct TimePoint: Identifiable {
    var time: Date
    var value: Double
    var series: String = ""
    var id: String { "\(series)-\(time.timeIntervalSince1970)" }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case m30 = "30M", h1 = "1H", h3 = "3H", h6 = "6H", h12 = "12H", h24 = "24H"
    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .m30: return 1800
        case .h1: return 3600
        case .h3: return 3 * 3600
        case .h6: return 6 * 3600
        case .h12: return 12 * 3600
        case .h24: return 24 * 3600
        }
    }
}

/// Averages points into at most `maxPoints` buckets so long ranges stay smooth and fast.
func downsample(_ points: [TimePoint], maxPoints: Int = 360) -> [TimePoint] {
    guard points.count > maxPoints else { return points }
    let size = Int(ceil(Double(points.count) / Double(maxPoints)))
    return stride(from: 0, to: points.count, by: size).map { start in
        let chunk = points[start..<min(start + size, points.count)]
        let mean = chunk.reduce(0) { $0 + $1.value } / Double(chunk.count)
        return TimePoint(time: chunk[chunk.startIndex + chunk.count / 2].time, value: mean, series: chunk.first!.series)
    }
}

struct SeriesChart: View {
    var title: String
    var unit: String
    var points: [TimePoint]
    var color: Color = Theme.aurora
    var range: ChartRange
    var rules: [(Double, String)] = []
    var height: CGFloat = 140
    var tz: TimeZone
    var info: ChartInfo?
    var interactive = false
    @State private var selected: Date?

    var body: some View {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let data = downsample(points.filter { $0.time >= cutoff })
        let picked = selected.flatMap { nearest(data, to: $0) }
        let digits = unit == "K" ? 0 : (unit == "GW" || unit == "km/s" ? 0 : 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                if let info, !interactive { InfoButton(info: info) }
                Spacer()
                if let picked {
                    ScrubReadout(time: TimeText.time(picked.time, tz), values: "\(picked.value.f(digits)) \(unit)")
                } else if let last = data.last {
                    Text("\(last.value.f(digits)) \(unit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if data.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary).frame(height: height)
            } else {
                Chart {
                    ForEach(data) { p in
                        LineMark(x: .value("Time", p.time), y: .value(title, p.value), series: .value("S", p.series))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 1.4))
                    }
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        RuleMark(y: .value("Threshold", rule.0))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text(rule.1).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                    }
                    if let picked {
                        scrubRule(picked.time)
                        PointMark(x: .value("Time", picked.time), y: .value(title, picked.value))
                            .foregroundStyle(color)
                            .symbolSize(40)
                    }
                }
                .chartXAxis { timeAxis(range: range, tz: tz) }
                .chartScrub($selected, enabled: interactive)
                .frame(height: height)
            }
        }
    }
}

/// Bz with the southward (negative) part filled red, like the classic space-weather plots.
struct BzChart: View {
    var samples: [MagSample]
    var range: ChartRange
    var threshold: Double
    var tz: TimeZone
    var showComponents = false
    var height: CGFloat = 180
    var info: ChartInfo?
    var interactive = false
    @State private var selected: Date?

    var body: some View {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let bz = downsample(samples.filter { $0.time >= cutoff }.compactMap { s in s.bz.map { TimePoint(time: s.time, value: $0, series: "Bz") } })
        let bt = downsample(samples.filter { $0.time >= cutoff }.compactMap { s in s.bt.map { TimePoint(time: s.time, value: $0, series: "Bt") } })
        let pickedBz = selected.flatMap { nearest(bz, to: $0) }
        let pickedBt = selected.flatMap { nearest(bt, to: $0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Bz / Bt (GSM)").font(.subheadline.weight(.semibold))
                if let info, !interactive { InfoButton(info: info) }
                Spacer()
                if let pickedBz {
                    ScrubReadout(
                        time: TimeText.time(pickedBz.time, tz),
                        values: "Bz \(String(format: "%+.1f", pickedBz.value))" + (pickedBt.map { " · Bt \($0.value.f())" } ?? "") + " nT"
                    )
                } else {
                    HStack(spacing: 8) {
                        legend("Bz south", Theme.south)
                        legend("Bz north", Theme.north)
                        legend("Bt", .white.opacity(0.7))
                    }
                }
            }
            if bz.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary).frame(height: height)
            } else {
                Chart {
                    ForEach(bz) { p in
                        AreaMark(x: .value("Time", p.time), yStart: .value("Zero", 0), yEnd: .value("Bz", min(p.value, 0)))
                            .foregroundStyle(by: .value("Series", "Bz south"))
                        AreaMark(x: .value("Time", p.time), yStart: .value("Zero", 0), yEnd: .value("Bz", max(p.value, 0)))
                            .foregroundStyle(by: .value("Series", "Bz north"))
                    }
                    ForEach(bt) { p in
                        LineMark(x: .value("Time", p.time), y: .value("Bt", p.value), series: .value("Series", "Bt"))
                            .foregroundStyle(by: .value("Series", "Bt"))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        LineMark(x: .value("Time", p.time), y: .value("Bt", -p.value), series: .value("Series", "-Bt"))
                            .foregroundStyle(by: .value("Series", "-Bt"))
                            .lineStyle(StrokeStyle(lineWidth: 0.8))
                    }
                    RuleMark(y: .value("Threshold", threshold))
                        .foregroundStyle(Theme.south.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .bottom, alignment: .leading) {
                            Text("alert \(threshold.f(0)) nT").font(.system(size: 9)).foregroundStyle(Theme.south)
                        }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(.white.opacity(0.3))
                    if let pickedBz {
                        scrubRule(pickedBz.time)
                        PointMark(x: .value("Time", pickedBz.time), y: .value("Bz", pickedBz.value))
                            .foregroundStyle(pickedBz.value < 0 ? Theme.south : Theme.north)
                            .symbolSize(40)
                    }
                }
                .chartForegroundStyleScale(
                    domain: ["Bz south", "Bz north", "Bt", "-Bt"],
                    range: [Theme.south.opacity(0.6), Theme.north.opacity(0.5), Color.white.opacity(0.75), Color.white.opacity(0.25)]
                )
                .chartLegend(.hidden)
                .chartXAxis { timeAxis(range: range, tz: tz) }
                .chartScrub($selected, enabled: interactive)
                .frame(height: height)
            }
        }
    }

    func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

struct MultiSeriesChart: View {
    var title: String
    var unit: String
    var points: [TimePoint]
    var colors: KeyValuePairs<String, Color>
    var range: ChartRange
    var tz: TimeZone
    var height: CGFloat = 140
    var info: ChartInfo?
    var interactive = false
    @State private var selected: Date?

    var body: some View {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let grouped = Dictionary(grouping: points.filter { $0.time >= cutoff }, by: \.series)
        let series = grouped.mapValues { downsample($0.sorted { $0.time < $1.time }) }
        let data = series.values.flatMap { $0 }
        let picked: [TimePoint] = selected.map { date in
            colors.compactMap { pair in series[pair.key].flatMap { nearest($0, to: date) } }
        } ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) (\(unit))").font(.subheadline.weight(.semibold))
                if let info, !interactive { InfoButton(info: info) }
                Spacer()
                if let first = picked.first {
                    ScrubReadout(
                        time: TimeText.time(first.time, tz),
                        values: picked.map { "\($0.series) \($0.value.f())" }.joined(separator: " · ")
                    )
                }
            }
            if data.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary).frame(height: height)
            } else {
                Chart {
                    ForEach(data) { p in
                        LineMark(x: .value("Time", p.time), y: .value(title, p.value), series: .value("Series", p.series))
                            .foregroundStyle(by: .value("Series", p.series))
                            .lineStyle(StrokeStyle(lineWidth: 1.3))
                    }
                    if let first = picked.first {
                        scrubRule(first.time)
                        ForEach(picked) { p in
                            PointMark(x: .value("Time", p.time), y: .value(title, p.value))
                                .foregroundStyle(by: .value("Series", p.series))
                                .symbolSize(40)
                        }
                    }
                }
                .chartForegroundStyleScale(domain: colors.map { $0.key }, range: colors.map { $0.value })
                .chartLegend(position: .top, alignment: .trailing)
                .chartXAxis { timeAxis(range: range, tz: tz) }
                .chartScrub($selected, enabled: interactive)
                .frame(height: height)
            }
        }
    }
}

/// GOES X-ray flux on a log scale labelled with flare classes.
struct XrayChart: View {
    var samples: [XraySample]
    var tz: TimeZone
    var range: ChartRange = .h24
    var height: CGFloat = 130
    var info: ChartInfo?
    var interactive = false
    private let classLevels: [(Double, String)] = [(-7, "B"), (-6, "C"), (-5, "M"), (-4, "X")]
    @State private var selected: Date?

    var body: some View {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let points = downsample(samples.filter { $0.time >= cutoff }.map { TimePoint(time: $0.time, value: log10($0.flux), series: "x") })
        let picked = selected.flatMap { nearest(points, to: $0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GOES X-ray (0.1–0.8 nm)").font(.subheadline.weight(.semibold))
                if let info, !interactive { InfoButton(info: info) }
                Spacer()
                if let picked {
                    ScrubReadout(time: TimeText.time(picked.time, tz), values: FlareClass.label(flux: pow(10, picked.value)))
                } else if let last = samples.last {
                    Text(FlareClass.label(flux: last.flux)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("Time", p.time), y: .value("log flux", p.value))
                        .foregroundStyle(.orange)
                }
                ForEach(Array(classLevels.enumerated()), id: \.offset) { _, level in
                    RuleMark(y: .value("Class", level.0))
                        .foregroundStyle(.white.opacity(0.15))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(level.1).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        }
                }
                if let picked {
                    scrubRule(picked.time)
                    PointMark(x: .value("Time", picked.time), y: .value("log flux", picked.value))
                        .foregroundStyle(.orange)
                        .symbolSize(40)
                }
            }
            .chartYScale(domain: -8.5 ... -3)
            .chartYAxis(.hidden)
            .chartXAxis { timeAxis(range: range, tz: tz) }
            .chartScrub($selected, enabled: interactive)
            .frame(height: height)
        }
    }
}

/// Observed + forecast Kp bars with this location's visibility thresholds.
struct KpBarChart: View {
    var points: [KpPoint]
    var thresholds: VisibilityThresholds
    var tz: TimeZone
    var height: CGFloat = 170
    var interactive = false
    @State private var selected: Date?

    var body: some View {
        let now = Date()
        let picked = selected.flatMap { date in points.first { $0.time <= date && date < $0.end } }
        VStack(alignment: .leading, spacing: 4) {
            if let picked {
                ScrubReadout(
                    time: "\(TimeText.format(picked.time, tz, "EEE h a"))–\(TimeText.format(picked.end, tz, "h a"))",
                    values: "Kp \(KpFormat.label(picked.kp))" + (KpFormat.gLabel(picked.kp).map { " (\($0))" } ?? "") + " · \(picked.kind.rawValue)"
                )
            } else if interactive {
                Text("Drag across the bars for details").font(.caption).foregroundStyle(.secondary)
            }
            chart(now: now, picked: picked)
        }
    }

    func chart(now: Date, picked: KpPoint?) -> some View {
        Chart {
            ForEach(points, id: \.time) { p in
                RectangleMark(
                    xStart: .value("Start", p.time.addingTimeInterval(900)),
                    xEnd: .value("End", p.end.addingTimeInterval(-900)),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Kp", max(p.kp, 0.15))
                )
                .foregroundStyle(Theme.kpColor(p.kp).opacity(picked.map { $0.time == p.time ? 1 : 0.35 } ?? (p.kind == .predicted ? 0.55 : 1)))
            }
            RuleMark(x: .value("Now", now)).foregroundStyle(.white.opacity(0.6))
            RuleMark(y: .value("Overhead", thresholds.overhead))
                .foregroundStyle(Theme.violet.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) { Text("overhead").font(.system(size: 9)).foregroundStyle(Theme.violet) }
            RuleMark(y: .value("Horizon", thresholds.horizon))
                .foregroundStyle(Theme.aurora.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) { Text("horizon").font(.system(size: 9)).foregroundStyle(Theme.aurora) }
        }
        .chartYScale(domain: 0...9)
        .chartYAxis { AxisMarks(values: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(TimeText.format(date, tz, "EEE")) }
                }
            }
        }
        .chartScrub($selected, enabled: interactive)
        .frame(height: height)
    }
}

func timeAxis(range: ChartRange, tz: TimeZone) -> some AxisContent {
    let stride: Calendar.Component = .minute
    let count: Int
    switch range {
    case .m30: count = 10
    case .h1: count = 15
    case .h3: count = 30
    case .h6: count = 60
    case .h12: count = 180
    case .h24: count = 240
    }
    return AxisMarks(values: .stride(by: stride, count: count)) { value in
        AxisGridLine()
        AxisValueLabel {
            if let date = value.as(Date.self) { Text(TimeText.format(date, tz, "h:mm")) }
        }
    }
}

// MARK: - Press-and-hold readout

/// Drag (or tap) on a chart to pick a time; the selection stays until you pick another point.
/// Only used in the full-screen chart view — on the main page charts don't take touches, so
/// scrolling isn't affected.
struct ChartScrub: ViewModifier {
    @Binding var selection: Date?
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let plot = geo[proxy.plotAreaFrame]
                                    let x = min(max(drag.location.x - plot.minX, 0), plot.width)
                                    guard let date: Date = proxy.value(atX: x) else { return }
                                    if selection == nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                                    selection = date
                                }
                        )
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func chartScrub(_ selection: Binding<Date?>, enabled: Bool) -> some View {
        modifier(ChartScrub(selection: selection, enabled: enabled))
    }
}

/// The point closest in time to `date`.
func nearest(_ points: [TimePoint], to date: Date) -> TimePoint? {
    points.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
}

/// Header text shown while scrubbing: the time, then the values.
struct ScrubReadout: View {
    var time: String
    var values: String

    var body: some View {
        HStack(spacing: 6) {
            Text(time).foregroundStyle(.secondary)
            Text(values).fontWeight(.semibold).foregroundStyle(.primary)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Vertical line marking the selected time.
func scrubRule(_ date: Date) -> some ChartContent {
    RuleMark(x: .value("Selected", date))
        .foregroundStyle(.white.opacity(0.7))
        .lineStyle(StrokeStyle(lineWidth: 1))
}

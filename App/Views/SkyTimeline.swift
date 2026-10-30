import AuroraKit
import SwiftUI

/// A bar from mid-afternoon to mid-morning showing how dark the sky is, when the Moon is up,
/// and where "now" falls.
struct SkyTimeline: View {
    var nightOf: Date
    var location: ObserverLocation
    var illumination: Double

    private struct Slice {
        var start: Date
        var twilight: Sky.Twilight
        var moonUp: Bool
    }

    var body: some View {
        let cal = location.calendar
        let start = cal.date(bySettingHour: 15, minute: 0, second: 0, of: nightOf) ?? nightOf
        let span: TimeInterval = 19 * 3600 // 3 PM → 10 AM
        let step: TimeInterval = 10 * 60
        let slices = stride(from: 0, to: span, by: step).map { offset -> Slice in
            let t = start.addingTimeInterval(offset + step / 2)
            return Slice(start: start.addingTimeInterval(offset),
                         twilight: Sky.Twilight(sunAltitude: Sky.sunAltitude(at: t, for: location)),
                         moonUp: Sky.isMoonUp(at: t, for: location))
        }
        let hours = stride(from: 0, through: span, by: 3 * 3600).map { start.addingTimeInterval($0) }
        let now = Date()
        let tz = location.timeZone

        VStack(spacing: 4) {
            Canvas { ctx, size in
                let w = size.width
                let sliceWidth = w * CGFloat(step / span)
                for (i, slice) in slices.enumerated() {
                    let x = w * CGFloat(Double(i) * step / span)
                    // Sky darkness
                    ctx.fill(Path(CGRect(x: x, y: 0, width: sliceWidth + 0.5, height: 22)),
                             with: .color(Self.color(slice.twilight)))
                    // Moon up
                    if slice.moonUp {
                        ctx.fill(Path(CGRect(x: x, y: 25, width: sliceWidth + 0.5, height: 5)),
                                 with: .color(Color.yellow.opacity(0.35 + 0.55 * illumination)))
                    }
                }
                // Now
                if now > start && now < start.addingTimeInterval(span) {
                    let x = w * CGFloat(now.timeIntervalSince(start) / span)
                    ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: 30)), with: .color(.white))
                }
            }
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            GeometryReader { geo in
                ForEach(hours, id: \.self) { h in
                    Text(TimeText.format(h, tz, "h a"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        // Line up with the bar, but keep the end labels on screen.
                        .position(x: min(max(geo.size.width * h.timeIntervalSince(start) / span, 14), geo.size.width - 14), y: 6)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sky darkness timeline for tonight")
    }

    static func color(_ twilight: Sky.Twilight) -> Color {
        switch twilight {
        case .day: return Color(red: 0.36, green: 0.58, blue: 0.86)
        case .civil: return Color(red: 0.24, green: 0.34, blue: 0.62)
        case .nautical: return Color(red: 0.13, green: 0.19, blue: 0.42)
        case .astronomical: return Color(red: 0.07, green: 0.10, blue: 0.26)
        case .night: return Color(red: 0.02, green: 0.03, blue: 0.10)
        }
    }
}

/// Sunrise/sunset, twilights and moonrise/moonset for tonight.
struct TonightSkyCard: View {
    var sky: NightSky
    var location: ObserverLocation

    var body: some View {
        let lt = LocalTime(tz: location.timeZone)
        Card(title: "Sun & Moon tonight", systemImage: "sunset.fill", info: .twilight) {
            SkyTimeline(nightOf: sky.nightOf, location: location, illumination: sky.moonIllumination)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EVENING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    row("Sunset", sky.sunset, .day, lt)
                    row("Civil dusk", sky.civilDusk, .civil, lt)
                    row("Nautical dusk", sky.nauticalDusk, .nautical, lt)
                    row("Astronomical dusk", sky.astronomicalDusk, .astronomical, lt)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text("MORNING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    row("Astronomical dawn", sky.astronomicalDawn, .astronomical, lt)
                    row("Nautical dawn", sky.nauticalDawn, .nautical, lt)
                    row("Civil dawn", sky.civilDawn, .civil, lt)
                    row("Sunrise", sky.sunrise, .day, lt)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Color.white.opacity(0.1))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: sky.moonSymbol)
                    .font(.title)
                    .foregroundStyle(.yellow.opacity(0.85))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(sky.moonPhase) · \(Int((sky.moonIllumination * 100).rounded()))% lit")
                        .font(.subheadline.weight(.semibold))
                    Text(moonTimes(lt)).font(.subheadline.monospacedDigit())
                    Text(moonNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    func row(_ name: String, _ date: Date?, _ tone: Sky.Twilight, _ lt: LocalTime) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(SkyTimeline.color(tone)).frame(width: 8, height: 8)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            Text(name).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(date.map { lt.time($0) } ?? "—").font(.caption.monospacedDigit().weight(.medium))
        }
    }

    /// Moonrise/moonset between noon and the next noon, in time order.
    func moonTimes(_ lt: LocalTime) -> String {
        let events = (sky.moonrises.map { ($0, "Rises") } + sky.moonsets.map { ($0, "Sets") })
            .sorted { $0.0 < $1.0 }
        guard !events.isEmpty else { return "No moonrise or moonset tonight" }
        return events.map { "\($0.1) \(lt.time($0.0))" }.joined(separator: " · ")
    }

    var moonNote: String {
        guard sky.darkMinutes > 0 else { return "" }
        if sky.moonIllumination < 0.15 { return "Thin or new Moon — it won't brighten the sky much." }
        if sky.moonUpMinutesInDark == 0 { return "The Moon is down for all of the dark hours — darkest skies." }
        let hours = TimeText.duration(TimeInterval(sky.moonUpMinutesInDark * 60))
        if sky.moonUpMinutesInDark >= sky.darkMinutes - 10 {
            return "The Moon is up all night while it's dark\(sky.moonIllumination > 0.5 ? " — faint aurora will be harder to see" : "")."
        }
        return "The Moon is up for \(hours) of the dark hours — look for darker skies when it's down."
    }
}

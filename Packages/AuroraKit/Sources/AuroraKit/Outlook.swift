import Foundation

public enum ActivityLevel: Int, Codable, Comparable, CaseIterable {
    case quiet = 0, possible, likely, strong

    public static func < (a: ActivityLevel, b: ActivityLevel) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .quiet: return "Quiet"
        case .possible: return "Possible"
        case .likely: return "Likely"
        case .strong: return "Strong"
        }
    }
}

/// One reason the aurora chance is what it is.
public struct OutlookFactor: Codable, Hashable, Identifiable {
    public enum Effect: String, Codable { case positive, neutral, negative }
    public var name: String
    public var detail: String
    public var effect: Effect
    public var points: Int
    public var id: String { name }
}

/// "Right now" aurora chance for the observer, built from live solar wind and geomagnetic data.
public struct Nowcast: Codable, Hashable {
    public var time: Date
    public var score: Int
    public var level: ActivityLevel
    public var factors: [OutlookFactor]
    public var visibility: Visibility
    public var estimatedKp: Double?
    public var bz: Double?
    public var bzMean30: Double?
    public var speed: Double?
    public var density: Double?
    public var electricField: Double?
    public var hemiPower: Double?
    public var ovation: OvationLocal?
    public var sunAltitude: Double
    public var isDark: Bool
    public var streak: BzStreak?
    public var shock: ShockEvent?
    public var travelTime: TimeInterval?
    public var cloudCover: Double?
    public var moonIllumination: Double
    public var dataIsFresh: Bool

    public var headline: String {
        switch level {
        case .quiet: return "Quiet — aurora unlikely right now"
        case .possible: return "Heads up — activity could build"
        case .likely: return "Aurora likely — get somewhere dark"
        case .strong: return "Strong storm — aurora could be overhead"
        }
    }
}

public enum Outlook {
    /// Combines the live data into a 0–100 score.
    ///
    /// * Estimated Kp vs. what this location needs — up to 40 points
    /// * Merging electric field (speed × southward Bz, 30-min mean) — up to 25
    /// * OVATION hemispheric power — up to 20
    /// * OVATION probability in the northern sky — up to 15
    public static func nowcast(snapshot: SpaceWeatherSnapshot, location: ObserverLocation, darkness: Double = -12, now: Date) -> Nowcast {
        let thresholds = location.visibility
        var factors: [OutlookFactor] = []
        var score = 0.0

        let magFresh = SolarWind.isFresh(snapshot.latestMag?.time, now: now)
        let plasmaFresh = SolarWind.isFresh(snapshot.latestPlasma?.time, now: now)

        // Kp
        let kpNow = currentKp(snapshot, now: now)
        if let kp = kpNow {
            let part = clamp((kp - (thresholds.overhead - 2.5)) / 2.5) * 40
            score += part
            let vis = thresholds.visibility(kp: kp)
            factors.append(.init(
                name: "Kp \(String(format: "%.1f", kp))",
                detail: vis == .unlikely
                    ? "Grand Forks-type latitudes need about Kp \(String(format: "%.1f", thresholds.horizon)) to see it by eye"
                        .replacingOccurrences(of: "Grand Forks-type latitudes", with: location.name)
                    : vis.description,
                effect: part >= 16 ? .positive : (part > 0 ? .neutral : .negative),
                points: Int(part.rounded())
            ))
        }

        // Bz / electric field
        let bz = magFresh ? snapshot.latestMag?.bz : nil
        let bzMean30 = magFresh ? SolarWind.recentMeanBz(snapshot.mag, minutes: 30, now: now) : nil
        let speed = plasmaFresh ? SolarWind.recentMean(snapshot.plasma, \.speed, minutes: 10, now: now) : nil
        let density = plasmaFresh ? SolarWind.recentMean(snapshot.plasma, \.density, minutes: 10, now: now) : nil
        var ey: Double?
        if let mean = bzMean30 {
            let v = speed ?? 400
            let field = SolarWind.electricField(speed: v, bz: mean)
            ey = field
            let part = clamp(field / 6) * 25
            score += part
            let direction = mean < 0 ? "southward" : "northward"
            factors.append(.init(
                name: "Bz \(String(format: "%+.1f", mean)) nT (30-min avg)",
                detail: mean < 0
                    ? "Field is \(direction) — energy is getting in (Ey \(String(format: "%.1f", field)) mV/m)"
                    : "Field is \(direction) — the door is mostly closed",
                effect: field >= 2 ? .positive : (mean < 0 ? .neutral : .negative),
                points: Int(part.rounded())
            ))
        } else {
            factors.append(.init(name: "Solar wind data", detail: "No recent data from L1", effect: .neutral, points: 0))
        }
        if let v = speed {
            factors.append(.init(
                name: "Speed \(Int(v)) km/s",
                detail: v >= 600 ? "Fast wind amplifies any southward Bz" : (v >= 450 ? "Moderately fast wind" : "Slow, background wind"),
                effect: v >= 500 ? .positive : .neutral, points: 0
            ))
        }

        // Hemispheric power
        var hp: Double?
        if let p = snapshot.latestHemiPower, now.timeIntervalSince(p.observed) < 60 * 60 {
            hp = p.north
            let part = clamp((p.north - 20) / 80) * 20
            score += part
            factors.append(.init(
                name: "Hemispheric power \(Int(p.north)) GW",
                detail: p.north >= 100 ? "Very bright, widespread aurora" : (p.north >= 50 ? "Active aurora" : "Low auroral energy"),
                effect: p.north >= 50 ? .positive : .neutral, points: Int(part.rounded())
            ))
        }

        // OVATION
        if let ov = snapshot.ovation {
            let part = clamp(Double(ov.maxInView) / 40) * 15
            score += part
            factors.append(.init(
                name: "OVATION \(ov.maxInView)% in your northern sky",
                detail: "\(ov.overhead)% chance directly overhead",
                effect: ov.maxInView >= 20 ? .positive : .neutral, points: Int(part.rounded())
            ))
        }

        // Shock
        let shock = (magFresh || plasmaFresh) ? SolarWind.detectShock(plasma: snapshot.plasma, mag: snapshot.mag, now: now) : nil
        if let shock {
            factors.append(.init(
                name: "Shock at L1 (+\(Int(shock.speedJump)) km/s)",
                detail: "Impact at Earth around \(TimeText.time(shock.earthArrival, location.timeZone))",
                effect: .positive, points: 0
            ))
        }

        let total = Int(min(score, 100).rounded())
        var level: ActivityLevel = total >= 75 ? .strong : (total >= 50 ? .likely : (total >= 30 ? .possible : .quiet))
        if let kp = kpNow {
            if kp >= thresholds.overhead + 1 { level = max(level, .strong) }
            else if kp >= thresholds.horizon { level = max(level, .likely) }
        }
        if shock != nil { level = max(level, .possible) }

        let sunAlt = Sky.sunAltitude(at: now, for: location)
        let cloud = cloudCover(at: now, clouds: snapshot.clouds)
        if let cloud {
            factors.append(.init(
                name: "Clouds \(Int(cloud))%",
                detail: cloud >= 80 ? "Mostly cloudy — sky may be blocked" : (cloud >= 40 ? "Partly cloudy" : "Mostly clear"),
                effect: cloud >= 70 ? .negative : (cloud <= 30 ? .positive : .neutral), points: 0
            ))
        }
        let moon = Sky.moonIllumination(at: now)

        return Nowcast(
            time: now, score: total, level: level, factors: factors,
            visibility: thresholds.visibility(kp: kpNow ?? 0),
            estimatedKp: kpNow, bz: bz, bzMean30: bzMean30, speed: speed, density: density,
            electricField: ey, hemiPower: hp, ovation: snapshot.ovation,
            sunAltitude: sunAlt, isDark: sunAlt < darkness,
            streak: magFresh ? SolarWind.bzStreak(snapshot.mag, threshold: -5, now: now) : nil,
            shock: shock,
            travelTime: SolarWind.currentTravelTime(snapshot: snapshot, now: now),
            cloudCover: cloud, moonIllumination: moon,
            dataIsFresh: magFresh && plasmaFresh
        )
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// Best current Kp. NOAA's 1-minute estimate restarts from 0 at the top of every 3-hour block
    /// (00, 03, … UTC) and takes 20+ minutes to climb back, so use the highest estimate of the last
    /// 45 minutes; fall back to the latest 3-hour value.
    public static func currentKp(_ snapshot: SpaceWeatherSnapshot, now: Date) -> Double? {
        let recent = snapshot.kp1m.filter { now.timeIntervalSince($0.time) < 45 * 60 && $0.time <= now.addingTimeInterval(60) }
        if let best = recent.map(\.kp).max(), let latest = recent.last, now.timeIntervalSince(latest.time) < 30 * 60 {
            return best
        }
        if let k = snapshot.latestKp, now.timeIntervalSince(k.time) < 6 * 3600 { return k.kp }
        return nil
    }

    public static func cloudCover(at date: Date, clouds: [CloudPoint]) -> Double? {
        clouds.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) })
            .flatMap { abs($0.time.timeIntervalSince(date)) <= 90 * 60 ? $0.total : nil }
    }

    public static func meanCloudCover(in window: DateInterval, clouds: [CloudPoint]) -> Double? {
        let values = clouds.filter { window.contains($0.time) }.map(\.total)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Night-by-night forecast

public struct NightOutlook: Codable, Hashable, Identifiable {
    public enum Source: String, Codable {
        /// NOAA 3-day Kp forecast (3-hour blocks).
        case kpForecast
        /// NOAA 27-day outlook (daily largest Kp; low confidence).
        case outlook27
    }

    /// Local date of the evening this night begins.
    public var nightOf: Date
    public var daysAhead: Int
    public var dark: DateInterval?
    public var maxKp: Double
    public var maxKpTime: Date?
    public var source: Source
    public var visibility: Visibility
    public var cloudCover: Double?
    public var moonIllumination: Double
    public var cmeArrivals: [CMEArrival]
    public var id: Date { nightOf }

    public var gScale: Int { KpFormat.gScale(maxKp) }
}

extension Outlook {
    /// Tonight and the following nights (up to `count`), with the highest Kp expected while it's dark.
    public static func nights(snapshot: SpaceWeatherSnapshot, location: ObserverLocation, count: Int = 4, darkness: Double = -12, now: Date) -> [NightOutlook] {
        let cal = location.calendar
        let firstNight = Sky.currentNightOf(now: now, location: location)
        let thresholds = location.visibility
        var result: [NightOutlook] = []

        for offset in 0..<count {
            guard let nightOf = cal.date(byAdding: .day, value: offset, to: firstNight) else { continue }
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: nightOf) ?? nightOf
            let dark = Sky.darkWindow(nightOf: nightOf, location: location, sunAltitude: darkness)
                ?? DateInterval(start: noon.addingTimeInterval(9 * 3600), duration: 6 * 3600)

            // Only the part of the night that hasn't happened yet matters for tonight.
            let remaining = DateInterval(start: max(dark.start, min(now, dark.end)), end: dark.end)
            let blocks = snapshot.kpForecast.filter { $0.end > remaining.start && $0.time < remaining.end }
            let forecastBest = blocks.max(by: { $0.kp < $1.kp })
            let outlookBest = snapshot.outlook27.filter {
                $0.date < dark.end && $0.date.addingTimeInterval(86400) > dark.start
            }.max(by: { $0.kp < $1.kp })

            // Use the 3-hour forecast when it covers the night; otherwise fall back to the 27-day outlook.
            let covered = blocks.last.map { $0.end >= remaining.end.addingTimeInterval(-3 * 3600) } ?? false
            var maxKp: Double
            var maxTime: Date?
            var source: NightOutlook.Source
            if let fc = forecastBest, covered || offset == 0 || outlookBest == nil {
                maxKp = fc.kp
                maxTime = fc.time
                source = .kpForecast
            } else if let day = outlookBest {
                maxKp = Double(day.kp)
                source = .outlook27
                if let fc = forecastBest, fc.kp > maxKp {
                    maxKp = fc.kp
                    maxTime = fc.time
                    source = .kpForecast
                }
            } else {
                continue
            }
            result.append(night(nightOf, offset, dark, maxKp, maxTime, source, thresholds, snapshot))
        }
        return result
    }

    private static func night(
        _ nightOf: Date, _ offset: Int, _ dark: DateInterval, _ maxKp: Double, _ maxTime: Date?,
        _ source: NightOutlook.Source, _ thresholds: VisibilityThresholds, _ snapshot: SpaceWeatherSnapshot
    ) -> NightOutlook {
        let windowForCME = DateInterval(start: dark.start.addingTimeInterval(-12 * 3600), end: dark.end)
        return NightOutlook(
            nightOf: nightOf, daysAhead: offset, dark: dark,
            maxKp: maxKp, maxKpTime: maxTime, source: source,
            visibility: thresholds.visibility(kp: maxKp),
            cloudCover: meanCloudCover(in: dark, clouds: snapshot.clouds),
            moonIllumination: Sky.moonIllumination(at: dark.start.addingTimeInterval(dark.duration / 2)),
            cmeArrivals: snapshot.cmeArrivals.filter { windowForCME.contains($0.arrival) }
        )
    }
}

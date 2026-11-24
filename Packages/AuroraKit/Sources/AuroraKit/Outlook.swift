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
    /// Newell coupling, 30-min mean ((km/s)^(4/3)·nT^(2/3)).
    public var coupling: Double?
    /// Highest NOAA Geospace predicted Kp in the next hour.
    public var predictedKp: EstimatedKp?
    public var hemiPower: Double?
    public var ovation: OvationLocal?
    public var sunAltitude: Double
    public var isDark: Bool
    public var streak: BzStreak?
    public var shock: ShockEvent?
    /// A sudden rise in the field at a GOES satellite in the last hour (substorm or compression).
    public var goesJump: GoesJump?
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
    /// * Solar wind coupling (Newell, 30-min mean; uses speed, Bz and By) — up to 25
    /// * OVATION hemispheric power — up to 20
    /// * OVATION probability in the northern sky — up to 15
    public static func nowcast(snapshot: SpaceWeatherSnapshot, location: ObserverLocation, darkness: Double = -12, goesThreshold: Double = 20, now: Date) -> Nowcast {
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
        let coupling = magFresh ? SolarWind.recentNewell(mag: snapshot.mag, plasma: snapshot.plasma, minutes: 30, now: now) : nil
        if let mean = bzMean30 {
            let v = speed ?? 400
            let field = SolarWind.electricField(speed: v, bz: mean)
            ey = field
            // Newell coupling also counts By, so a strong sideways field with Bz near zero still
            // drives some aurora; fall back to Ey if plasma data is missing.
            let strength = coupling.map { $0 / 24000 } ?? field / 6
            let part = clamp(strength) * 25
            score += part
            let word = strength >= 0.75 ? "storm-level" : (strength >= 0.4 ? "strong" : (strength >= 0.15 ? "modest" : "weak"))
            factors.append(.init(
                name: "Bz \(String(format: "%+.1f", mean)) nT (30-min avg)",
                detail: mean < 0
                    ? "Field is southward — \(word) coupling, energy is getting in (Ey \(String(format: "%.1f", field)) mV/m)"
                    : (strength >= 0.15 ? "Field is mostly sideways — \(word) coupling" : "Field is northward — the door is mostly closed"),
                effect: strength >= 0.3 ? .positive : (strength >= 0.1 ? .neutral : .negative),
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

        // OVATION (ignore it if it's more than 2 hours old)
        let ovation = snapshot.ovation.flatMap { ov in
            (ov.forecastTime ?? ov.observationTime).map { abs(now.timeIntervalSince($0)) < 2 * 3600 } == false ? nil : ov
        }
        var ovationVisibility = Visibility.unlikely
        if let ov = ovation {
            let part = clamp(Double(ov.maxInView) / 40) * 15
            score += part
            var detail = "\(ov.overhead)% chance directly overhead"
            if let d = ov.edgeDistanceKm, let elevation = ov.edgeElevation {
                if d <= 0 {
                    detail += "; the oval's edge is at or south of you"
                } else if elevation > 0 {
                    detail += "; oval edge ~\(Int(d.rounded() / 10) * 10) km north, ~\(Int(elevation.rounded()))° above the horizon"
                } else {
                    detail += "; oval edge ~\(Int(d.rounded() / 10) * 10) km north, below your horizon"
                }
                ovationVisibility = d <= 0 ? .overhead : (elevation >= 5 ? .horizon : (elevation >= 2 ? .cameraOnly : .unlikely))
            }
            factors.append(.init(
                name: "OVATION \(ov.maxInView)% in your northern sky",
                detail: detail,
                effect: ov.maxInView >= 20 || ovationVisibility >= .horizon ? .positive : .neutral, points: Int(part.rounded())
            ))
        }

        // NOAA Geospace model: Kp predicted for the next hour.
        let predicted = snapshot.predictedKp.filter { $0.time > now && $0.time <= now.addingTimeInterval(75 * 60) }
        let predictedKp = predicted.max(by: { $0.kp < $1.kp })
        if let p = predictedKp {
            factors.append(.init(
                name: "Predicted Kp \(String(format: "%.1f", p.kp)) by \(TimeText.time(p.time, location.timeZone))",
                detail: p.kp >= thresholds.horizon
                    ? "NOAA's Geospace model expects activity to reach aurora level within the hour"
                    : "NOAA's Geospace model forecast for the next hour (it tends to run a bit low)",
                effect: p.kp >= thresholds.horizon ? .positive : .neutral, points: 0
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
        if let p = predictedKp {
            if p.kp >= thresholds.overhead { level = max(level, .likely) }
            else if p.kp >= thresholds.horizon { level = max(level, .possible) }
        }

        // GOES: a sudden rise in the field = substorm (night side) or compression (day side).
        let goesJump = GoesWatch.detectJump(snapshot.goesPrimary + snapshot.goesSecondary, threshold: goesThreshold, now: now, lookback: 60)
        if let jump = goesJump {
            let when = TimeText.time(jump.time, location.timeZone)
            factors.append(.init(
                name: "GOES-\(jump.satellite) +\(Int(jump.rise)) nT jump",
                detail: jump.nightSide
                    ? "Substorm signature at \(when) — aurora often brightens right away"
                    : "Compression at \(when) — a solar wind pulse hit Earth's field",
                effect: .positive, points: 0
            ))
            if jump.nightSide && now.timeIntervalSince(jump.time) < 30 * 60 { level = max(level, .possible) }
        }

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
            visibility: max(thresholds.visibility(kp: kpNow ?? 0), ovationVisibility),
            estimatedKp: kpNow, bz: bz, bzMean30: bzMean30, speed: speed, density: density,
            electricField: ey, coupling: coupling, predictedKp: predictedKp, hemiPower: hp, ovation: ovation,
            sunAltitude: sunAlt, isDark: sunAlt < darkness,
            streak: magFresh ? SolarWind.bzStreak(snapshot.mag, threshold: -5, now: now) : nil,
            shock: shock,
            goesJump: goesJump,
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
    /// Sunset/sunrise, twilights and moonrise/moonset for this night.
    public var sky: NightSky?
    public var id: Date { nightOf }

    public var gScale: Int { KpFormat.gScale(maxKp) }
}

extension Outlook {
    /// Tonight and the following nights (up to `count`), with the highest Kp expected while it's dark.
    public static func nights(snapshot: SpaceWeatherSnapshot, location: ObserverLocation, count: Int = 4, darkness: Double = -12, now: Date) -> [NightOutlook] {
        let cal = location.calendar
        let firstNight = Sky.currentNightOf(now: now, location: location)
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
            result.append(night(nightOf, offset, dark, maxKp, maxTime, source, location, snapshot))
        }
        return result
    }

    private static func night(
        _ nightOf: Date, _ offset: Int, _ dark: DateInterval, _ maxKp: Double, _ maxTime: Date?,
        _ source: NightOutlook.Source, _ location: ObserverLocation, _ snapshot: SpaceWeatherSnapshot
    ) -> NightOutlook {
        let thresholds = location.visibility
        let windowForCME = DateInterval(start: dark.start.addingTimeInterval(-12 * 3600), end: dark.end)
        let sky = Sky.nightSky(nightOf: nightOf, location: location)
        return NightOutlook(
            nightOf: nightOf, daysAhead: offset, dark: dark,
            maxKp: maxKp, maxKpTime: maxTime, source: source,
            visibility: thresholds.visibility(kp: maxKp),
            cloudCover: meanCloudCover(in: dark, clouds: snapshot.clouds),
            moonIllumination: Sky.moonIllumination(at: dark.start.addingTimeInterval(dark.duration / 2)),
            cmeArrivals: snapshot.cmeArrivals.filter { windowForCME.contains($0.arrival) },
            sky: sky
        )
    }
}

// MARK: - Hour by hour

/// One hour of a night: how dark, Kp expected, clouds and Moon, and how good it is for aurora.
public struct ViewingHour: Codable, Hashable, Identifiable {
    public var start: Date
    public var twilight: Int        // Sky.Twilight raw value (0 = day … 4 = full darkness)
    public var kp: Double?
    public var cloudCover: Double?
    public var moonUp: Bool
    /// 0…100: darkness × clearness × moon × aurora potential.
    public var score: Int
    public var id: Date { start }
}

public struct ViewingPlan: Codable, Hashable {
    public var hours: [ViewingHour]
    /// The best stretch of the night (consecutive hours within 85% of the best score).
    public var best: DateInterval?
}

extension Outlook {
    /// Hour-by-hour viewing conditions from sunset to sunrise for the night of `nightOf`.
    public static func viewingPlan(snapshot: SpaceWeatherSnapshot, location: ObserverLocation, nightOf: Date, now: Date) -> ViewingPlan {
        let sky = Sky.nightSky(nightOf: nightOf, location: location)
        let cal = location.calendar
        guard let sunset = sky.sunset, let sunrise = sky.sunrise else { return ViewingPlan(hours: [], best: nil) }
        let thresholds = location.visibility
        let illumination = sky.moonIllumination
        // Whole hours from the hour of sunset to the hour of sunrise.
        var t = cal.dateInterval(of: .hour, for: sunset)?.start ?? sunset
        var hours: [ViewingHour] = []
        while t < sunrise {
            let mid = t.addingTimeInterval(1800)
            let twilight = Sky.Twilight(sunAltitude: Sky.sunAltitude(at: mid, for: location))
            let kp = snapshot.kpForecast.first { $0.time <= mid && mid < $0.end }?.kp
                ?? snapshot.outlook27.first { $0.date <= mid && mid < $0.date.addingTimeInterval(86400) }.map { Double($0.kp) }
            let cloud = cloudCover(at: mid, clouds: snapshot.clouds)
            let moonUp = Sky.isMoonUp(at: mid, for: location)

            let dark: Double
            switch twilight {
            case .day, .civil: dark = 0
            case .nautical: dark = 0.6
            case .astronomical: dark = 0.85
            case .night: dark = 1
            }
            let clear = 1 - (cloud ?? 30) / 100
            let moon = moonUp ? 1 - 0.5 * illumination : 1
            // Aurora potential: 0 at the camera threshold, 1 at "overhead"; a floor keeps the
            // darkest, clearest hours ranked even on quiet nights.
            let potential = kp.map { clamp(($0 - thresholds.camera) / max(thresholds.overhead - thresholds.camera, 0.5)) } ?? 0
            let score = 100 * dark * clear * moon * (0.3 + 0.7 * potential)
            hours.append(ViewingHour(start: t, twilight: twilight.rawValue, kp: kp, cloudCover: cloud, moonUp: moonUp, score: Int(score.rounded())))
            t = t.addingTimeInterval(3600)
        }

        // Best stretch: the run of hours around the top score that stay within 85% of it.
        var best: DateInterval?
        let upcoming = hours.filter { $0.start.addingTimeInterval(3600) > now }
        if let top = upcoming.max(by: { $0.score < $1.score }), top.score > 0,
           let i = hours.firstIndex(where: { $0.start == top.start }) {
            var lo = i, hi = i
            let floor = Double(top.score) * 0.85
            while lo > 0, Double(hours[lo - 1].score) >= floor, hours[lo - 1].start.addingTimeInterval(3600) > now { lo -= 1 }
            while hi < hours.count - 1, Double(hours[hi + 1].score) >= floor { hi += 1 }
            best = DateInterval(start: max(hours[lo].start, now), end: hours[hi].start.addingTimeInterval(3600))
        }
        return ViewingPlan(hours: hours, best: best)
    }
}

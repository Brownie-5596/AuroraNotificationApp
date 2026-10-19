import Foundation

/// How long, and how strongly, the IMF Bz has been pointing south (negative).
/// Southward Bz is the main "door opener" that lets solar wind energy into Earth's magnetosphere.
public struct BzStreak: Codable, Hashable {
    /// Latest Bz value (nT).
    public var current: Double
    public var time: Date
    public var isSouth: Bool
    /// When the current southward (or northward) run started.
    public var since: Date
    /// Length of the current run.
    public var duration: TimeInterval
    /// Lowest Bz during the current southward run (nT).
    public var minimum: Double
    /// Mean Bz during the current southward run (nT).
    public var mean: Double
    /// Accumulated southward field, nT·minutes ("how much" it has been negative).
    public var integral: Double
    /// How long Bz has continuously been at or below the user's threshold.
    public var belowThresholdDuration: TimeInterval
    /// Share of the last 3 hours with Bz < 0 (0...1).
    public var southFractionLast3h: Double
    /// Mean Bz over the last 30 minutes.
    public var mean30: Double?
}

/// A sudden jump in solar wind speed/density/field at L1 — the signature of a CME shock or stream interface.
public struct ShockEvent: Codable, Hashable {
    public var time: Date
    public var speedBefore: Double
    public var speedAfter: Double
    public var densityRatio: Double?
    public var btRatio: Double?
    /// Estimated time the shock reaches Earth.
    public var earthArrival: Date

    public var speedJump: Double { speedAfter - speedBefore }
}

public enum SolarWind {
    /// Mean distance from the L1 monitors to Earth (km).
    public static let l1Distance = 1.5e6

    /// Seconds for solar wind at `speed` km/s to travel from L1 to Earth.
    public static func travelTime(speed: Double) -> TimeInterval {
        l1Distance / max(speed, 200)
    }

    /// Travel time from L1 to Earth, preferring NOAA's propagated product (accounts for real spacecraft position).
    public static func currentTravelTime(snapshot: SpaceWeatherSnapshot, now: Date) -> TimeInterval? {
        if let p = snapshot.propagated.last, now.timeIntervalSince(p.time) < 30 * 60, p.travelTime > 5 * 60, p.travelTime < 3 * 3600 {
            return p.travelTime
        }
        if let speed = recentMean(snapshot.plasma, \.speed, minutes: 10, now: now) {
            return travelTime(speed: speed)
        }
        return nil
    }

    /// Dawn–dusk (merging) electric field in mV/m: Ey = V · Bs. Values above ~3 mV/m drive substorms.
    public static func electricField(speed: Double, bz: Double) -> Double {
        speed * max(-bz, 0) / 1000
    }

    /// Solar wind dynamic pressure (nPa).
    public static func dynamicPressure(speed: Double, density: Double) -> Double {
        1.6726e-6 * density * speed * speed
    }

    static func recent<T>(_ samples: [T], time: KeyPath<T, Date>, minutes: Double, now: Date) -> ArraySlice<T> {
        let cutoff = now.addingTimeInterval(-minutes * 60)
        var lo = samples.count
        while lo > 0 && samples[lo - 1][keyPath: time] >= cutoff { lo -= 1 }
        return samples[lo...]
    }

    public static func recentMean(_ samples: [PlasmaSample], _ key: KeyPath<PlasmaSample, Double?>, minutes: Double, now: Date) -> Double? {
        let values = recent(samples, time: \.time, minutes: minutes, now: now).compactMap { $0[keyPath: key] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public static func recentMeanBz(_ samples: [MagSample], minutes: Double, now: Date) -> Double? {
        let values = recent(samples, time: \.time, minutes: minutes, now: now).compactMap(\.bz)
        guard values.count >= max(3, Int(minutes * 0.5)) else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Is the newest sample recent enough to be trusted for real-time alerts?
    public static func isFresh(_ date: Date?, now: Date, maxAge: TimeInterval = 20 * 60) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < maxAge
    }

    /// Finds the run of samples (ending at the newest sample) that satisfy `matches`, walking backwards.
    /// Excursions shorter than `tolerance` don't break the run; data gaps over 10 minutes do.
    static func run(_ points: [(Date, Double)], tolerance: TimeInterval, _ matches: (Double) -> Bool) -> (start: Date, end: Date, values: [Double])? {
        var start: Date?
        var end: Date?
        var values: [Double] = []
        var excursionLatest: Date?
        var previous = points.last?.0
        for point in points.reversed() {
            if let prev = previous, prev.timeIntervalSince(point.0) > 10 * 60 { break }
            previous = point.0
            if matches(point.1) {
                if end == nil { end = point.0 }
                start = point.0
                values.append(point.1)
                excursionLatest = nil
            } else {
                if excursionLatest == nil { excursionLatest = point.0 }
                if excursionLatest!.timeIntervalSince(point.0) + 60 > tolerance { break }
            }
        }
        guard let s = start, let e = end else { return nil }
        return (s, e, values)
    }

    /// Builds the southward-Bz streak. Short (≤ `tolerance`) excursions to the other side don't break a run.
    public static func bzStreak(_ samples: [MagSample], threshold: Double, now: Date, tolerance: TimeInterval = 3 * 60) -> BzStreak? {
        let points = samples.compactMap { s -> (Date, Double)? in s.bz.map { (s.time, $0) } }
        guard let last = points.last else { return nil }
        let south = last.1 < 0
        let current = run(points, tolerance: tolerance) { ($0 < 0) == south }
        let below = run(points, tolerance: tolerance) { $0 <= threshold }
        let southValues = south ? (current?.values ?? []) : []
        let window3h = points.filter { last.0.timeIntervalSince($0.0) <= 3 * 3600 }
        let southCount = window3h.filter { $0.1 < 0 }.count
        let since = current?.start ?? last.0

        return BzStreak(
            current: last.1,
            time: last.0,
            isSouth: south,
            since: since,
            duration: last.0.timeIntervalSince(since) + 60,
            minimum: southValues.min() ?? last.1,
            mean: southValues.isEmpty ? last.1 : southValues.reduce(0, +) / Double(southValues.count),
            integral: southValues.reduce(0) { $0 + max(-$1, 0) },
            belowThresholdDuration: below.map { $0.end.timeIntervalSince($0.start) + 60 } ?? 0,
            southFractionLast3h: window3h.isEmpty ? 0 : Double(southCount) / Double(window3h.count),
            mean30: recentMeanBz(samples, minutes: 30, now: now)
        )
    }

    /// Bz has averaged at or below `threshold` for the last `minutes`, with most samples below it.
    public static func isSustainedSouth(_ samples: [MagSample], threshold: Double, minutes: Double, now: Date) -> (Bool, mean: Double?) {
        let window = recent(samples, time: \.time, minutes: minutes, now: now).compactMap(\.bz)
        guard window.count >= Int(minutes * 0.7) else { return (false, nil) }
        let mean = window.reduce(0, +) / Double(window.count)
        let below = window.filter { $0 <= threshold }.count
        return (mean <= threshold && Double(below) / Double(window.count) >= 0.75, mean)
    }

    /// Looks for an interplanetary shock in the last `lookback` minutes of L1 plasma data.
    public static func detectShock(plasma: [PlasmaSample], mag: [MagSample], now: Date, lookback: Double = 90) -> ShockEvent? {
        let window = Array(recent(plasma, time: \.time, minutes: lookback + 20, now: now))
        guard window.count > 20 else { return nil }

        func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        func values(_ from: Date, _ to: Date, _ key: KeyPath<PlasmaSample, Double?>) -> [Double] {
            window.filter { $0.time >= from && $0.time < to }.compactMap { $0[keyPath: key] }
        }
        func btValues(_ from: Date, _ to: Date) -> [Double] {
            recent(mag, time: \.time, minutes: lookback + 30, now: now)
                .filter { $0.time >= from && $0.time < to }.compactMap(\.bt)
        }

        var best: ShockEvent?
        let cutoff = now.addingTimeInterval(-lookback * 60)
        for sample in window where sample.time >= cutoff {
            let t = sample.time
            let before = values(t.addingTimeInterval(-15 * 60), t.addingTimeInterval(-2 * 60), \.speed)
            let after = values(t, t.addingTimeInterval(8 * 60), \.speed)
            guard before.count >= 5, after.count >= 4,
                  let v0 = median(before), let v1 = median(after), v1 - v0 >= 60,
                  (sample.speed ?? 0) >= (v0 + v1) / 2 else { continue }

            let n0 = median(values(t.addingTimeInterval(-15 * 60), t.addingTimeInterval(-2 * 60), \.density))
            let n1 = median(values(t, t.addingTimeInterval(8 * 60), \.density))
            let b0 = median(btValues(t.addingTimeInterval(-15 * 60), t.addingTimeInterval(-2 * 60)))
            let b1 = median(btValues(t, t.addingTimeInterval(8 * 60)))
            let densityRatio = (n0 ?? 0) > 0 ? n1.map { $0 / n0! } : nil
            let btRatio = (b0 ?? 0) > 0 ? b1.map { $0 / b0! } : nil
            // A shock compresses plasma and field together with the speed jump.
            let compressed = (densityRatio ?? 0) >= 1.5 || (btRatio ?? 0) >= 1.5
            guard compressed || v1 - v0 >= 120 else { continue }

            let event = ShockEvent(
                time: t, speedBefore: v0, speedAfter: v1,
                densityRatio: densityRatio, btRatio: btRatio,
                earthArrival: t.addingTimeInterval(travelTime(speed: v1))
            )
            if best == nil || event.speedJump > best!.speedJump + 20 { best = event }
        }
        return best
    }
}

import Foundation

/// A sudden rise in the magnetic field measured by a GOES satellite (36,000 km up).
///
/// On the night side (satellite local time 18–06) this is usually a **substorm dipolarization**:
/// the stretched night-side field snaps back and the aurora suddenly brightens. On the day side
/// it's usually a **compression** — a shock or pressure pulse in the solar wind hitting Earth.
public struct GoesJump: Codable, Hashable {
    public var satellite: Int
    /// When the rise began (lowest point) and ended.
    public var start: Date
    public var time: Date
    /// Size of the rise, nT.
    public var rise: Double
    /// Satellite local solar time (hours) at `time`.
    public var localHour: Double

    public var nightSide: Bool { localHour >= 18 || localHour < 6 }
    public var minutes: Int { Int((time.timeIntervalSince(start) / 60).rounded()) }
}

public enum GoesWatch {
    /// Geostationary longitude (°E) of each GOES satellite slot.
    static func longitude(satellite: Int) -> Double {
        switch satellite {
        case 16, 19: return -75.2   // GOES-East
        case 17, 18: return -137.2  // GOES-West
        default: return -105
        }
    }

    public static func localHour(_ date: Date, satellite: Int) -> Double {
        let utcHours = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 3600
        let h = (utcHours + longitude(satellite: satellite) / 15).truncatingRemainder(dividingBy: 24)
        return h < 0 ? h + 24 : h
    }

    /// The biggest rise of at least `threshold` nT within 10 minutes that ended in the last
    /// `lookback` minutes, across all satellites. The normal daily wave changes Hp by well under
    /// 1 nT a minute, so a 20 nT rise in 10 minutes stands out. A 3-point median filter keeps
    /// single-sample glitches from counting.
    public static func detectJump(_ samples: [GoesMagSample], threshold: Double, now: Date, lookback: Double = 30) -> GoesJump? {
        let recent = samples.filter { now.timeIntervalSince($0.time) <= (lookback + 15) * 60 && $0.time <= now }
        var best: GoesJump?
        for (satellite, series) in Dictionary(grouping: recent, by: \.satellite) {
            let points = series.sorted { $0.time < $1.time }
            guard points.count >= 8 else { continue }
            let smooth: [Double] = points.indices.map { i in
                let window = points[max(0, i - 1)...min(points.count - 1, i + 1)].map(\.hp).sorted()
                return window[window.count / 2]
            }
            var lo = 0
            for i in points.indices {
                let t = points[i].time
                while points[lo].time < t.addingTimeInterval(-10 * 60) { lo += 1 }
                guard i - lo >= 5, now.timeIntervalSince(t) <= lookback * 60 else { continue }
                let window = lo..<i
                guard let minIndex = window.min(by: { smooth[$0] < smooth[$1] }) else { continue }
                let rise = smooth[i] - smooth[minIndex]
                guard rise >= threshold, rise > (best?.rise ?? 0) else { continue }
                best = GoesJump(satellite: satellite, start: points[minIndex].time, time: t, rise: rise,
                                localHour: localHour(t, satellite: satellite))
            }
        }
        return best
    }
}

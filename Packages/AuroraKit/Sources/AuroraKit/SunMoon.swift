import Foundation

// Low-precision solar and lunar positions (Astronomical Almanac formulas). Good to about a minute
// for sunrise/sunset and a few minutes for moonrise/moonset — plenty for planning a night out.

extension Sky {
    struct Equatorial {
        var ra: Double      // radians
        var dec: Double     // radians
        var longitude: Double // ecliptic longitude, degrees
    }

    static func sunPosition(_ date: Date) -> Equatorial {
        let d = daysSinceJ2000(date)
        let g = (357.529 + 0.98560028 * d) * rad
        let q = 280.459 + 0.98564736 * d
        let lambdaDeg = q + 1.915 * sin(g) + 0.020 * sin(2 * g)
        let lambda = lambdaDeg * rad
        let epsilon = (23.439 - 0.00000036 * d) * rad
        return Equatorial(
            ra: atan2(cos(epsilon) * sin(lambda), cos(lambda)),
            dec: asin(sin(epsilon) * sin(lambda)),
            longitude: normalize(lambdaDeg)
        )
    }

    /// Geocentric Moon position plus its horizontal parallax (degrees).
    static func moonPosition(_ date: Date) -> (Equatorial, parallax: Double) {
        let t = daysSinceJ2000(date) / 36525
        func s(_ a: Double, _ b: Double) -> Double { sin((a + b * t) * rad) }
        func c(_ a: Double, _ b: Double) -> Double { cos((a + b * t) * rad) }
        let lambdaDeg = 218.32 + 481267.881 * t
            + 6.29 * s(135.0, 477198.87) - 1.27 * s(259.3, -413335.36)
            + 0.66 * s(235.7, 890534.22) + 0.21 * s(269.9, 954397.74)
            - 0.19 * s(357.5, 35999.05) - 0.11 * s(186.5, 966404.03)
        let betaDeg = 5.13 * s(93.3, 483202.02) + 0.28 * s(228.2, 960400.89)
            - 0.28 * s(318.3, 6003.15) - 0.17 * s(217.6, -407332.21)
        let parallax = 0.9508 + 0.0518 * c(135.0, 477198.87) + 0.0095 * c(259.3, -413335.36)
            + 0.0078 * c(235.7, 890534.22) + 0.0028 * c(269.9, 954397.74)
        let lambda = lambdaDeg * rad
        let beta = betaDeg * rad
        let epsilon = (23.4393 - 0.0130 * t) * rad
        let ra = atan2(sin(lambda) * cos(epsilon) - tan(beta) * sin(epsilon), cos(lambda))
        let dec = asin(sin(beta) * cos(epsilon) + cos(beta) * sin(epsilon) * sin(lambda))
        return (Equatorial(ra: ra, dec: dec, longitude: normalize(lambdaDeg)), parallax)
    }

    static func altitude(ra: Double, dec: Double, date: Date, latitude: Double, longitude: Double) -> Double {
        let d = daysSinceJ2000(date)
        let gmstHours = 18.697374558 + 24.06570982441908 * d
        let ha = (gmstHours * 15 + longitude) * rad - ra
        let lat = latitude * rad
        return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)) / rad
    }

    /// Moon altitude (degrees, geocentric).
    public static func moonAltitude(at date: Date, for location: ObserverLocation) -> Double {
        let (moon, _) = moonPosition(date)
        return altitude(ra: moon.ra, dec: moon.dec, date: date, latitude: location.latitude, longitude: location.longitude)
    }

    /// Is the Moon above the horizon (accounting for refraction and its size)?
    public static func isMoonUp(at date: Date, for location: ObserverLocation) -> Bool {
        moonAboveHorizon(date, location) > 0
    }

    /// Moon altitude relative to its rise/set threshold (positive = above the horizon).
    /// Accounts for parallax, semi-diameter and refraction: h0 = 0.7275·π − 0.5667°.
    static func moonAboveHorizon(_ date: Date, _ location: ObserverLocation) -> Double {
        let (moon, parallax) = moonPosition(date)
        let alt = altitude(ra: moon.ra, dec: moon.dec, date: date, latitude: location.latitude, longitude: location.longitude)
        return alt - (0.7275 * parallax - 0.5667)
    }

    /// Sun–Moon elongation in degrees, 0…360 (0 = new, 180 = full).
    static func moonElongation(_ date: Date) -> Double {
        normalize(moonPosition(date).0.longitude - sunPosition(date).longitude)
    }

    static func normalize(_ degrees: Double) -> Double {
        let x = degrees.truncatingRemainder(dividingBy: 360)
        return x < 0 ? x + 360 : x
    }

    /// Times when `f` crosses zero in `interval`, with the direction (true = going up).
    static func crossings(in interval: DateInterval, step: TimeInterval = 10 * 60, _ f: (Date) -> Double) -> [(date: Date, rising: Bool)] {
        var result: [(Date, Bool)] = []
        var t0 = interval.start
        var v0 = f(t0)
        while t0 < interval.end {
            let t1 = min(t0.addingTimeInterval(step), interval.end)
            let v1 = f(t1)
            if (v0 < 0) != (v1 < 0) {
                var lo = t0, hi = t1, vlo = v0
                for _ in 0..<12 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    let vm = f(mid)
                    if (vm < 0) == (vlo < 0) { lo = mid; vlo = vm } else { hi = mid }
                }
                result.append((lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2), v1 > v0))
            }
            t0 = t1
            v0 = v1
        }
        return result
    }
}

/// Sun and Moon events for one night, from noon to the next noon (local time).
public struct NightSky: Codable, Hashable {
    public var nightOf: Date
    public var sunset: Date?
    public var civilDusk: Date?
    public var nauticalDusk: Date?
    public var astronomicalDusk: Date?
    public var astronomicalDawn: Date?
    public var nauticalDawn: Date?
    public var civilDawn: Date?
    public var sunrise: Date?
    public var moonrises: [Date]
    public var moonsets: [Date]
    /// Illumination (0…1) in the middle of the night.
    public var moonIllumination: Double
    public var moonPhase: String
    public var moonSymbol: String
    /// Minutes the Moon is up while the sky is properly dark (nautical dusk → nautical dawn).
    public var moonUpMinutesInDark: Int
    public var darkMinutes: Int

    public var moonrise: Date? { moonrises.first }
    public var moonset: Date? { moonsets.first }
}

extension Sky {
    /// Sunrise/sunset, the three twilights and moonrise/moonset for the night that begins on the
    /// evening of `nightOf` (a local date).
    public static func nightSky(nightOf: Date, location: ObserverLocation) -> NightSky {
        let cal = location.calendar
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: nightOf) ?? nightOf
        let window = DateInterval(start: noon, duration: 24 * 3600)

        func sunEvents(_ altitudeLimit: Double) -> (down: Date?, up: Date?) {
            let events = crossings(in: window) { sunAltitude(at: $0, for: location) - altitudeLimit }
            return (events.first { !$0.rising }?.date, events.first { $0.rising }?.date)
        }
        let horizon = sunEvents(-0.833)
        let civil = sunEvents(-6)
        let nautical = sunEvents(-12)
        let astro = sunEvents(-18)

        let moonEvents = crossings(in: window) { moonAboveHorizon($0, location) }
        let mid = noon.addingTimeInterval(12 * 3600)

        // How much of the dark (nautical) part of the night has the Moon up?
        var moonUp = 0
        var dark = 0
        if let start = nautical.down {
            let end = nautical.up ?? window.end
            var t = start
            while t < end {
                dark += 5
                if moonAboveHorizon(t, location) > 0 { moonUp += 5 }
                t = t.addingTimeInterval(5 * 60)
            }
        }

        return NightSky(
            nightOf: nightOf,
            sunset: horizon.down, civilDusk: civil.down, nauticalDusk: nautical.down, astronomicalDusk: astro.down,
            astronomicalDawn: astro.up, nauticalDawn: nautical.up, civilDawn: civil.up, sunrise: horizon.up,
            moonrises: moonEvents.filter(\.rising).map(\.date),
            moonsets: moonEvents.filter { !$0.rising }.map(\.date),
            moonIllumination: moonIllumination(at: mid),
            moonPhase: moonPhaseName(at: mid),
            moonSymbol: moonPhaseSymbol(at: mid),
            moonUpMinutesInDark: moonUp,
            darkMinutes: dark
        )
    }

    /// Sky brightness from the Sun's altitude.
    public enum Twilight: Int, Comparable {
        case day, civil, nautical, astronomical, night

        public static func < (a: Twilight, b: Twilight) -> Bool { a.rawValue < b.rawValue }

        public init(sunAltitude alt: Double) {
            switch alt {
            case (-0.833)...: self = .day
            case (-6)...: self = .civil
            case (-12)...: self = .nautical
            case (-18)...: self = .astronomical
            default: self = .night
            }
        }

        public var name: String {
            switch self {
            case .day: return "Daylight"
            case .civil: return "Civil twilight"
            case .nautical: return "Nautical twilight"
            case .astronomical: return "Astronomical twilight"
            case .night: return "Full darkness"
            }
        }
    }
}

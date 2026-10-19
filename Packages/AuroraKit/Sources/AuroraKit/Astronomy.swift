import Foundation

public struct ObserverLocation: Codable, Hashable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneID: String

    public init(name: String, latitude: Double, longitude: Double, timeZoneID: String) {
        self.name = name; self.latitude = latitude; self.longitude = longitude; self.timeZoneID = timeZoneID
    }

    public static let grandForks = ObserverLocation(
        name: "Grand Forks, ND", latitude: 47.9253, longitude: -97.0329, timeZoneID: "America/Chicago"
    )

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    public var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    public var geomagneticLatitude: Double {
        Geomagnetic.latitude(latitude: latitude, longitude: longitude)
    }

    public var visibility: VisibilityThresholds { VisibilityThresholds(location: self) }
}

/// Low-precision solar and lunar positions — plenty for "is it dark yet?".
public enum Sky {
    static let rad = Double.pi / 180

    static func daysSinceJ2000(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
    }

    /// Sun altitude in degrees above the horizon.
    public static func sunAltitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        let d = daysSinceJ2000(date)
        let g = (357.529 + 0.98560028 * d) * rad
        let q = 280.459 + 0.98564736 * d
        let lambda = (q + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let epsilon = (23.439 - 0.00000036 * d) * rad
        let ra = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let dec = asin(sin(epsilon) * sin(lambda))
        let gmstHours = 18.697374558 + 24.06570982441908 * d
        let lst = (gmstHours * 15 + longitude) * rad
        let ha = lst - ra
        let lat = latitude * rad
        return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)) / rad
    }

    public static func sunAltitude(at date: Date, for location: ObserverLocation) -> Double {
        sunAltitude(at: date, latitude: location.latitude, longitude: location.longitude)
    }

    /// Fraction of the Moon's disc that is lit (0 = new, 1 = full).
    public static func moonIllumination(at date: Date) -> Double {
        let age = moonAge(at: date)
        return (1 - cos(2 * Double.pi * age / synodicMonth)) / 2
    }

    static let synodicMonth = 29.530588853

    /// Days since new moon.
    public static func moonAge(at date: Date) -> Double {
        // Reference new moon: 2000-01-06 18:14 UTC.
        let reference = 947182440.0
        let days = (date.timeIntervalSince1970 - reference) / 86400
        let age = days.truncatingRemainder(dividingBy: synodicMonth)
        return age < 0 ? age + synodicMonth : age
    }

    public static func moonPhaseName(at date: Date) -> String {
        let age = moonAge(at: date)
        switch age / synodicMonth {
        case ..<0.033, 0.967...: return "New Moon"
        case ..<0.216: return "Waxing Crescent"
        case ..<0.283: return "First Quarter"
        case ..<0.466: return "Waxing Gibbous"
        case ..<0.533: return "Full Moon"
        case ..<0.716: return "Waning Gibbous"
        case ..<0.783: return "Last Quarter"
        default: return "Waning Crescent"
        }
    }

    /// The dark window of the night that begins on the evening of `nightOf` (local date).
    /// Dark means the sun is below `sunAltitude` degrees (default −12°, nautical twilight).
    public static func darkWindow(nightOf: Date, location: ObserverLocation, sunAltitude limit: Double = -12) -> DateInterval? {
        let cal = location.calendar
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: nightOf) ?? nightOf
        let step: TimeInterval = 5 * 60
        var start: Date?
        var end: Date?
        var t = noon
        let stop = noon.addingTimeInterval(24 * 3600)
        while t < stop {
            let dark = sunAltitude(at: t, for: location) < limit
            if dark && start == nil { start = t }
            if !dark && start != nil { end = t; break }
            t = t.addingTimeInterval(step)
        }
        guard let s = start else { return nil }
        return DateInterval(start: s, end: end ?? stop)
    }

    /// Local calendar day whose evening began the night currently in progress (or the coming night, in daytime).
    public static func currentNightOf(now: Date, location: ObserverLocation) -> Date {
        let cal = location.calendar
        let today = cal.startOfDay(for: now)
        if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
           let previous = darkWindow(nightOf: yesterday, location: location, sunAltitude: -6),
           now < previous.end {
            return yesterday
        }
        return today
    }
}

/// Geomagnetic latitude and the Kp needed to see aurora from a location.
public enum Geomagnetic {
    /// Geomagnetic north pole (IGRF dipole, epoch 2025).
    static let poleLatitude = 80.8
    static let poleLongitude = -72.6

    public static func latitude(latitude: Double, longitude: Double) -> Double {
        let r = Double.pi / 180
        let s = sin(latitude * r) * sin(poleLatitude * r)
            + cos(latitude * r) * cos(poleLatitude * r) * cos((longitude - poleLongitude) * r)
        return asin(s) / r
    }

    /// Approximate geomagnetic latitude of the oval's equatorward edge (aurora overhead) for a Kp.
    public static func ovalEdge(kp: Double) -> Double { 66.5 - 2.05 * kp }

    /// Kp at which the oval's edge reaches a geomagnetic latitude.
    public static func kpForOverhead(geomagneticLatitude: Double) -> Double {
        (66.5 - geomagneticLatitude) / 2.05
    }
}

public enum Visibility: Int, Codable, Comparable {
    case unlikely = 0, cameraOnly, horizon, overhead

    public static func < (a: Visibility, b: Visibility) -> Bool { a.rawValue < b.rawValue }

    public var description: String {
        switch self {
        case .unlikely: return "Not expected to be visible"
        case .cameraOnly: return "Possible on camera, low on the northern horizon"
        case .horizon: return "Visible to the eye on the northern horizon"
        case .overhead: return "Could be overhead — look in every direction"
        }
    }

    public var short: String {
        switch self {
        case .unlikely: return "Unlikely"
        case .cameraOnly: return "Camera"
        case .horizon: return "Horizon"
        case .overhead: return "Overhead"
        }
    }
}

public struct VisibilityThresholds: Codable, Hashable {
    /// Kp at which aurora may be overhead.
    public var overhead: Double
    /// Kp at which it is usually visible to the eye low in the north.
    public var horizon: Double
    /// Kp at which a phone/camera long exposure may pick it up on the horizon.
    public var camera: Double

    public init(location: ObserverLocation) {
        let kp = Geomagnetic.kpForOverhead(geomagneticLatitude: location.geomagneticLatitude)
        overhead = min(max(kp, 0), 9)
        horizon = min(max(kp - 1, 0), 9)
        camera = min(max(kp - 1.5, 0), 9)
    }

    public func visibility(kp: Double) -> Visibility {
        if kp >= overhead { return .overhead }
        if kp >= horizon { return .horizon }
        if kp >= camera { return .cameraOnly }
        return .unlikely
    }
}

public enum KpFormat {
    /// SWPC-style label: 4.67 → "5-", 5.00 → "5", 5.33 → "5+".
    public static func label(_ kp: Double) -> String {
        let thirds = Int((kp * 3).rounded())
        let whole = thirds / 3
        switch thirds % 3 {
        case 1: return "\(whole)+"
        case 2: return "\(whole + 1)-"
        default: return "\(whole)"
        }
    }

    /// NOAA G-scale for a Kp value (SWPC labels 5- and above as G1).
    public static func gScale(_ kp: Double) -> Int {
        switch kp {
        case 8.66...: return 5
        case 7.66...: return 4
        case 6.66...: return 3
        case 5.66...: return 2
        case 4.66...: return 1
        default: return 0
        }
    }

    public static func gLabel(_ kp: Double) -> String? {
        let g = gScale(kp)
        return g > 0 ? "G\(g)" : nil
    }

    public static func gName(_ g: Int) -> String {
        ["None", "Minor", "Moderate", "Strong", "Severe", "Extreme"][min(max(g, 0), 5)]
    }
}

public enum FlareClass {
    /// Long-channel X-ray flux (W/m²) → class string like "M2.4".
    public static func label(flux: Double) -> String {
        let classes: [(String, Double)] = [("X", 1e-4), ("M", 1e-5), ("C", 1e-6), ("B", 1e-7), ("A", 1e-8)]
        for (letter, base) in classes where flux >= base {
            return letter + String(format: "%.1f", flux / base)
        }
        return "A" + String(format: "%.1f", flux / 1e-8)
    }

    /// "M2.4" → 2.4e-5.
    public static func flux(_ label: String) -> Double? {
        guard let letter = label.first else { return nil }
        let bases: [Character: Double] = ["A": 1e-8, "B": 1e-7, "C": 1e-6, "M": 1e-5, "X": 1e-4]
        guard let base = bases[Character(letter.uppercased())] else { return nil }
        let magnitude = Double(label.dropFirst()) ?? 1
        return base * magnitude
    }
}

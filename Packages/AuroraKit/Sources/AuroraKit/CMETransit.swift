import Foundation

/// Sun-to-Earth travel time for a coronal mass ejection, using the drag-based model (DBM, Vršnak et al. 2013).
/// The CME is slowed (or sped up) by the ambient solar wind until it matches the wind's speed.
public enum CMETransit {
    public static let au = 1.495978707e8 // km
    public static let solarRadius = 695_700.0 // km

    public struct Estimate: Hashable {
        public var travelTime: TimeInterval
        public var arrival: Date
        /// CME speed on arrival at Earth (km/s).
        public var arrivalSpeed: Double
    }

    /// - Parameters:
    ///   - speed: CME speed (km/s) at `startDistance` (coronagraph speeds are usually quoted at ~21.5 solar radii).
    ///   - windSpeed: background solar wind speed (km/s).
    ///   - gamma: drag parameter (km⁻¹); 0.2e-7 is typical, larger for wide/light CMEs.
    public static func dragBasedArrival(
        speed: Double,
        launchedAt: Date,
        windSpeed: Double = 400,
        gamma: Double = 0.2e-7,
        startDistance: Double = 21.5 * solarRadius
    ) -> Estimate? {
        guard speed > 0, windSpeed > 0 else { return nil }
        let dv = speed - windSpeed
        let sign: Double = dv >= 0 ? 1 : -1

        func distance(_ t: Double) -> Double {
            let x = 1 + sign * gamma * dv * t
            guard x > 0 else { return .infinity }
            return sign / gamma * log(x) + windSpeed * t + startDistance
        }
        func velocity(_ t: Double) -> Double {
            dv / (1 + sign * gamma * dv * t) + windSpeed
        }

        var lo = 0.0
        var hi = 10 * 86400.0
        guard distance(hi) >= au else { return nil }
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if distance(mid) < au { lo = mid } else { hi = mid }
        }
        return Estimate(travelTime: hi, arrival: launchedAt.addingTimeInterval(hi), arrivalSpeed: velocity(hi))
    }
}

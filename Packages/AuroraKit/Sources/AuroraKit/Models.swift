import Foundation

// MARK: - Solar wind (measured at the L1 point, ~1.5 million km sunward of Earth)

/// One minute of interplanetary magnetic field (IMF) data. GSM coordinates.
public struct MagSample: Codable, Hashable {
    public var time: Date
    public var bt: Double?
    public var bx: Double?
    public var by: Double?
    public var bz: Double?

    public init(time: Date, bt: Double?, bx: Double?, by: Double?, bz: Double?) {
        self.time = time; self.bt = bt; self.bx = bx; self.by = by; self.bz = bz
    }
}

/// One minute of solar wind plasma data.
public struct PlasmaSample: Codable, Hashable {
    public var time: Date
    public var speed: Double?
    public var density: Double?
    public var temperature: Double?

    public init(time: Date, speed: Double?, density: Double?, temperature: Double?) {
        self.time = time; self.speed = speed; self.density = density; self.temperature = temperature
    }
}

/// NOAA's solar wind propagated from L1 to Earth (gives the real per-sample travel time).
public struct PropagatedSample: Codable, Hashable {
    public var time: Date
    public var arrival: Date
    public var speed: Double?
    public var density: Double?
    public var bz: Double?
    public var bt: Double?

    public var travelTime: TimeInterval { arrival.timeIntervalSince(time) }
}

// MARK: - Geomagnetic indices

public enum KpKind: String, Codable, Hashable {
    case observed, estimated, predicted
}

/// A 3-hour planetary Kp value (observed, estimated or predicted). `time` is the block start.
public struct KpPoint: Codable, Hashable {
    public var time: Date
    public var kp: Double
    public var kind: KpKind

    public init(time: Date, kp: Double, kind: KpKind) {
        self.time = time; self.kp = kp; self.kind = kind
    }

    public var end: Date { time.addingTimeInterval(3 * 3600) }
}

/// The 1-minute estimated planetary Kp.
public struct EstimatedKp: Codable, Hashable {
    public var time: Date
    public var kp: Double
}

/// OVATION hemispheric power (GW). Higher = brighter, more widespread aurora.
public struct HemiPowerPoint: Codable, Hashable {
    public var observed: Date
    public var forecast: Date
    public var north: Double
}

/// GOES magnetometer Hp component (nT). Sharp jumps/drops are signs of substorms and shocks.
public struct GoesMagSample: Codable, Hashable {
    public var time: Date
    public var hp: Double
    public var satellite: Int
}

public struct XraySample: Codable, Hashable {
    public var time: Date
    public var flux: Double
    public var satellite: Int
}

public struct XrayFlare: Codable, Hashable {
    public var begin: Date?
    public var peak: Date?
    public var end: Date?
    public var maxClass: String?
    public var currentClass: String?
    public var satellite: Int?
}

// MARK: - NOAA products

public enum SWPCAlertKind: String, Codable, Hashable {
    case watch, warning, alert, summary, cancel, other

    public var title: String {
        switch self {
        case .watch: return "Watch"
        case .warning: return "Warning"
        case .alert: return "Alert"
        case .summary: return "Summary"
        case .cancel: return "Cancellation"
        case .other: return "Message"
        }
    }
}

public struct SWPCAlert: Codable, Hashable, Identifiable {
    public var id: String
    public var serial: String
    public var productID: String
    public var issued: Date
    public var message: String
    public var headline: String
    public var kind: SWPCAlertKind

    /// K-index mentioned in "Geomagnetic K-index of N" headlines.
    public var kIndex: Int? {
        guard let r = headline.range(of: "K-index of ") else { return nil }
        let digit = headline[r.upperBound...].prefix(while: { $0.isNumber })
        return Int(digit)
    }

    /// G level mentioned in "Geomagnetic Storm Category G2 Predicted" style headlines.
    public var gLevel: Int? {
        guard let r = headline.range(of: "Category G") else { return nil }
        return Int(headline[r.upperBound...].prefix(while: { $0.isNumber }))
    }

    /// NOAA occasionally re-sends the same message; product + serial identifies it.
    public var dedupeKey: String { "\(productID)-\(serial)" }

    public var isGeomagnetic: Bool { headline.localizedCaseInsensitiveContains("geomagnetic") }
}

/// NOAA space weather scales for one day (R = radio blackouts, S = radiation storms, G = geomagnetic storms).
public struct ScaleDay: Codable, Hashable {
    public var date: String
    public var r: Int?
    public var s: Int?
    public var g: Int?
    public var rMinorProb: Int?
    public var rMajorProb: Int?
    public var sProb: Int?
}

public struct NOAAScales: Codable, Hashable {
    public var yesterday: ScaleDay?
    public var current: ScaleDay?
    /// Forecast days 1...3.
    public var forecast: [ScaleDay]
}

/// The OVATION aurora model evaluated around the observer.
public struct OvationLocal: Codable, Hashable {
    public var observationTime: Date?
    public var forecastTime: Date?
    /// Probability (%) of aurora directly overhead.
    public var overhead: Int
    /// Highest probability (%) in the part of the sky visible from the observer (looking north).
    public var maxInView: Int
}

/// A free-text NOAA product (3-day forecast etc.) split into titled sections.
public struct TextProduct: Codable, Hashable {
    public struct Section: Codable, Hashable, Identifiable {
        public var title: String
        public var body: String
        public var id: String { title }
    }

    public var title: String
    public var issued: Date?
    public var raw: String
    public var sections: [Section]
}

/// "NOAA Geomagnetic Activity Probabilities" from the 3-day geomagnetic forecast.
public struct GeomagProbabilities: Codable, Hashable {
    public struct Row: Codable, Hashable, Identifiable {
        public var label: String
        public var values: [Int]
        public var id: String { label }
    }

    public var days: [String]
    public var rows: [Row]
    public var apLines: [String]
}

/// One day of the 27-day outlook.
public struct OutlookDay: Codable, Hashable {
    public var date: Date
    public var radioFlux: Int
    public var ap: Int
    public var kp: Int
}

/// A predicted CME arrival from NASA's WSA-ENLIL runs (DONKI).
public struct CMEArrival: Codable, Hashable, Identifiable {
    public var id: String
    public var cmeStart: Date?
    public var cmeSpeed: Double?
    public var time21_5: Date?
    public var modelCompletion: Date?
    public var arrival: Date
    public var isGlancingBlow: Bool
    public var kpLow: Double?
    public var kpHigh: Double?
    public var durationHours: Double?
    public var link: String?

    /// Drag-based-model estimate using the CME's coronagraph speed, for comparison with ENLIL.
    public var dragModelArrival: Date? {
        guard let speed = cmeSpeed, let t0 = time21_5 ?? cmeStart else { return nil }
        return CMETransit.dragBasedArrival(speed: speed, launchedAt: t0)?.arrival
    }
}

public struct CloudPoint: Codable, Hashable {
    public var time: Date
    public var total: Double
    public var low: Double?
    public var mid: Double?
    public var high: Double?
}

// MARK: - Snapshot

/// Everything fetched in one refresh.
public struct SpaceWeatherSnapshot: Codable {
    public var fetchedAt: Date
    public var mag: [MagSample] = []
    public var magSource: String?
    public var plasma: [PlasmaSample] = []
    public var plasmaSource: String?
    public var propagated: [PropagatedSample] = []
    public var kpObserved: [KpPoint] = []
    public var kpForecast: [KpPoint] = []
    public var kp1m: [EstimatedKp] = []
    public var hemiPower: [HemiPowerPoint] = []
    public var goesPrimary: [GoesMagSample] = []
    public var goesSecondary: [GoesMagSample] = []
    public var xray: [XraySample] = []
    public var latestFlare: XrayFlare?
    public var alerts: [SWPCAlert] = []
    public var scales: NOAAScales?
    public var ovation: OvationLocal?
    public var threeDayForecast: TextProduct?
    public var geomagForecast: TextProduct?
    public var geomagProbabilities: GeomagProbabilities?
    public var outlook27: [OutlookDay] = []
    public var outlook27Raw: String?
    public var cmeArrivals: [CMEArrival] = []
    public var cmeFetchedAt: Date?
    public var clouds: [CloudPoint] = []
    public var cloudsFetchedAt: Date?
    public var outlookFetchedAt: Date?
    /// Feed name -> error message for feeds that failed this refresh.
    public var errors: [String: String] = [:]

    public init(fetchedAt: Date) {
        self.fetchedAt = fetchedAt
    }

    public var latestMag: MagSample? { mag.last(where: { $0.bz != nil }) }
    public var latestPlasma: PlasmaSample? { plasma.last(where: { $0.speed != nil }) }
    public var latestEstimatedKp: EstimatedKp? { kp1m.last }
    public var latestHemiPower: HemiPowerPoint? { hemiPower.last }
    public var latestXray: XraySample? { xray.last }

    /// Most recent observed/estimated 3-hour Kp.
    public var latestKp: KpPoint? {
        (kpObserved + kpForecast.filter { $0.kind != .predicted }).max(by: { $0.time < $1.time })
    }

    /// Kp predictions (future blocks only, and the current one).
    public func upcomingKp(now: Date) -> [KpPoint] {
        kpForecast.filter { $0.end > now }
    }
}

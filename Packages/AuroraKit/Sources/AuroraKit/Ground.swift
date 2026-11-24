import Foundation

/// A ground magnetometer observatory with real-time one-minute data.
///
/// The aurora is driven by huge electric currents ~110 km up (the auroral electrojets). When they
/// strengthen or move over a magnetometer, the horizontal field there swings by hundreds of nT
/// within minutes — the most direct sign that aurora is active *near you*, rather than somewhere
/// over the Arctic.
public struct GroundStation: Codable, Hashable, Identifiable {
    public enum Source: String, Codable {
        /// Natural Resources Canada (FDSN web service, network C2, miniSEED).
        case nrcan
        /// USGS Geomagnetism Program (JSON web service).
        case usgs
    }

    /// IAGA code, e.g. "BRD".
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var source: Source

    public init(id: String, name: String, latitude: Double, longitude: Double, source: Source) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude; self.source = source
    }

    /// Observatories with live data (a few minutes behind). Polar-cap stations are left out: the
    /// currents there say little about aurora at mid-latitudes.
    public static let all: [GroundStation] = [
        .init(id: "BRD", name: "Brandon, MB", latitude: 49.870, longitude: -99.974, source: .nrcan),
        .init(id: "OTT", name: "Ottawa, ON", latitude: 45.403, longitude: -75.552, source: .nrcan),
        .init(id: "MEA", name: "Meanook, AB", latitude: 54.616, longitude: -113.347, source: .nrcan),
        .init(id: "VIC", name: "Victoria, BC", latitude: 48.520, longitude: -123.420, source: .nrcan),
        .init(id: "STJ", name: "St. John's, NL", latitude: 47.595, longitude: -52.677, source: .nrcan),
        .init(id: "ARF", name: "Acadia, NB", latitude: 46.028, longitude: -66.354, source: .nrcan),
        .init(id: "FCC", name: "Churchill, MB", latitude: 58.759, longitude: -94.088, source: .nrcan),
        .init(id: "SNK", name: "Sanikiluaq, NU", latitude: 56.500, longitude: -79.200, source: .nrcan),
        .init(id: "YKC", name: "Yellowknife, NT", latitude: 62.480, longitude: -114.482, source: .nrcan),
        .init(id: "BLC", name: "Baker Lake, NU", latitude: 64.318, longitude: -96.012, source: .nrcan),
        .init(id: "IQA", name: "Iqaluit, NU", latitude: 63.753, longitude: -68.518, source: .nrcan),
        .init(id: "BOU", name: "Boulder, CO", latitude: 40.137, longitude: -105.237, source: .usgs),
        .init(id: "NEW", name: "Newport, WA", latitude: 48.265, longitude: -117.122, source: .usgs),
        .init(id: "FRD", name: "Fredericksburg, VA", latitude: 38.205, longitude: -77.373, source: .usgs),
        .init(id: "FRN", name: "Fresno, CA", latitude: 37.091, longitude: -119.718, source: .usgs),
        .init(id: "TUC", name: "Tucson, AZ", latitude: 32.174, longitude: -110.733, source: .usgs),
        .init(id: "BSL", name: "Stennis, MS", latitude: 30.350, longitude: -89.635, source: .usgs),
        .init(id: "SIT", name: "Sitka, AK", latitude: 57.058, longitude: -135.325, source: .usgs),
        .init(id: "CMO", name: "Fairbanks, AK", latitude: 64.874, longitude: -147.860, source: .usgs),
        .init(id: "DED", name: "Deadhorse, AK", latitude: 70.355, longitude: -148.793, source: .usgs),
        .init(id: "BRW", name: "Utqiaġvik, AK", latitude: 71.322, longitude: -156.622, source: .usgs),
        .init(id: "SHU", name: "Shumagin, AK", latitude: 55.348, longitude: -160.462, source: .usgs),
    ]

    /// Great-circle distance to `location`, km.
    public func distanceKm(to location: ObserverLocation) -> Double {
        let r = Double.pi / 180
        let a = sin((location.latitude - latitude) * r / 2)
        let b = sin((location.longitude - longitude) * r / 2)
        let h = a * a + cos(latitude * r) * cos(location.latitude * r) * b * b
        return 2 * 6371 * asin(min(1, h.squareRoot()))
    }

    /// The closest observatory within `maxKm`, or nil if none is near enough to say anything local.
    public static func nearest(to location: ObserverLocation, maxKm: Double = 1000) -> GroundStation? {
        all.min { $0.distanceKm(to: location) < $1.distanceKm(to: location) }
            .flatMap { $0.distanceKm(to: location) <= maxKm ? $0 : nil }
    }
}

/// One minute of the northward (X) magnetic field at a ground station, nT.
public struct GroundMagSample: Codable, Hashable {
    public var time: Date
    public var x: Double

    public init(time: Date, x: Double) {
        self.time = time; self.x = x
    }
}

/// A sudden change in the ground field: the electrojet surging or moving overhead (a substorm).
public struct GroundSurge: Codable, Hashable {
    /// When the change began and ended.
    public var start: Date
    public var time: Date
    /// Signed change, nT (negative = the field dropped, the usual substorm signature).
    public var change: Double

    public var minutes: Int { Int((time.timeIntervalSince(start) / 60).rounded()) }
}

public enum GroundActivity: Int, Codable, Comparable, CaseIterable {
    case quiet = 0, unsettled, active, storm

    public static func < (a: GroundActivity, b: GroundActivity) -> Bool { a.rawValue < b.rawValue }

    /// From the size of the disturbance (nT). Quiet-day swings stay under ~50 nT; the auroral
    /// electrojet overhead gives hundreds.
    public init(disturbance: Double) {
        switch disturbance {
        case ..<50: self = .quiet
        case ..<150: self = .unsettled
        case ..<300: self = .active
        default: self = .storm
        }
    }

    public var title: String {
        switch self {
        case .quiet: return "Quiet"
        case .unsettled: return "Unsettled"
        case .active: return "Active"
        case .storm: return "Storm"
        }
    }
}

/// What the nearest ground magnetometer says right now.
public struct GroundReading: Codable, Hashable {
    public var station: GroundStation
    /// Newest sample.
    public var time: Date
    /// Normal level: median of the last 24 hours.
    public var baseline: Double
    /// Field now minus normal, nT.
    public var deviation: Double
    /// Highest minus lowest over the last hour, nT.
    public var range60: Double
    /// The biggest change within 15 minutes, ending in the last 30 minutes.
    public var surge: GroundSurge?

    /// Size of the disturbance: the larger of the departure from normal and the last hour's swing.
    public var disturbance: Double { max(abs(deviation), range60) }
    public var level: GroundActivity { GroundActivity(disturbance: disturbance) }

    public func isFresh(now: Date) -> Bool { now.timeIntervalSince(time) < 20 * 60 }
}

public enum GroundWatch {
    /// Summarizes the station's recent data, or nil without at least two hours of it.
    public static func reading(_ samples: [GroundMagSample], station: GroundStation, now: Date,
                               surgeWindow: Double = 15, lookback: Double = 30) -> GroundReading? {
        let points = samples.filter { $0.time <= now }
        guard let last = points.last else { return nil }
        let day = points.filter { last.time.timeIntervalSince($0.time) <= 24 * 3600 }
        guard let first = day.first, last.time.timeIntervalSince(first.time) >= 2 * 3600 else { return nil }
        let baseline = median(day.map(\.x))

        // The last 90 minutes, 3-point median filtered so a single bad sample can't count.
        let recent = day.filter { last.time.timeIntervalSince($0.time) <= 90 * 60 }
        let smooth: [Double] = recent.indices.map { i in
            median(recent[max(0, i - 1)...min(recent.count - 1, i + 1)].map(\.x))
        }
        let now60 = recent.indices.filter { last.time.timeIntervalSince(recent[$0].time) <= 60 * 60 }.map { smooth[$0] }
        let range60 = (now60.max() ?? 0) - (now60.min() ?? 0)

        var surge: GroundSurge?
        var lo = 0
        for i in recent.indices {
            let t = recent[i].time
            while recent[lo].time < t.addingTimeInterval(-surgeWindow * 60) { lo += 1 }
            guard i > lo, last.time.timeIntervalSince(t) <= lookback * 60 else { continue }
            for j in lo..<i {
                let change = smooth[i] - smooth[j]
                if abs(change) > abs(surge?.change ?? 0) {
                    surge = GroundSurge(start: recent[j].time, time: t, change: change)
                }
            }
        }

        return GroundReading(
            station: station, time: last.time, baseline: baseline,
            deviation: (smooth.last ?? last.x) - baseline, range60: range60, surge: surge
        )
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}

extension FeedParser {
    /// Natural Resources Canada data from the FDSN dataselect service: miniSEED (SEED 2.4) records.
    /// Keeps the X component (channel `UFX`, or any channel ending in X). Handles the uncompressed
    /// encodings NRCan uses (32/64-bit float, 16/32-bit integer); Steim-compressed records are skipped.
    public static func groundMiniSEED(_ data: Data) -> [GroundMagSample] {
        let b = [UInt8](data)
        var samples: [GroundMagSample] = []
        var off = 0
        while off + 48 <= b.count {
            // Fixed header: 6-char sequence number, quality indicator (D/R/Q/M), reserved byte.
            guard "DRQM".utf8.contains(b[off + 6]) else { break }
            let little = BinaryReader.u16(b, off + 20, little: false) > 3000 // year looks wrong big-endian
            func u16(_ at: Int) -> Int { Int(BinaryReader.u16(b, off + at, little: little)) }
            func i16(_ at: Int) -> Int { Int(Int16(bitPattern: BinaryReader.u16(b, off + at, little: little))) }
            let channel = String(decoding: b[(off + 15)..<(off + 18)], as: UTF8.self)
            let year = u16(20), doy = u16(22)
            let hour = Int(b[off + 24]), minute = Int(b[off + 25]), second = Int(b[off + 26])
            let tenThousandths = u16(28)
            let count = u16(30)
            let factor = i16(32), multiplier = i16(34)
            let dataOffset = u16(44)
            var blockette = u16(46)

            var encoding = -1
            var recordLength = 512
            var guardCount = 0
            while blockette > 0, off + blockette + 8 <= b.count, guardCount < 10 {
                let type = u16(blockette)
                if type == 1000 {
                    encoding = Int(b[off + blockette + 4])
                    let exponent = Int(b[off + blockette + 6])
                    if (7...16).contains(exponent) { recordLength = 1 << exponent }
                }
                blockette = u16(blockette + 2)
                guardCount += 1
            }
            defer { off += recordLength }

            guard channel.hasSuffix("X"), count > 0, (1...366).contains(doy), (1900...2200).contains(year) else { continue }
            let start = SWDate.utc(year: year, month: 1, day: 1)
                .addingTimeInterval(Double(doy - 1) * 86400 + Double(hour * 3600 + minute * 60 + second) + Double(tenThousandths) / 10000)

            var rate = factor > 0 ? Double(factor) : (factor < 0 ? -1 / Double(factor) : 0)
            if multiplier > 0 { rate *= Double(multiplier) } else if multiplier < 0 { rate /= -Double(multiplier) }
            let period = rate > 0 ? 1 / rate : 60

            let width: Int
            switch encoding {
            case 1: width = 2
            case 3, 4: width = 4
            case 5: width = 8
            default: continue // compressed or unknown
            }
            let base = off + dataOffset
            guard dataOffset >= 48, base + count * width <= min(b.count, off + recordLength) else { continue }
            for i in 0..<count {
                let p = base + i * width
                let value: Double
                switch encoding {
                case 1: value = Double(Int16(bitPattern: BinaryReader.u16(b, p, little: little)))
                case 3: value = Double(Int32(bitPattern: BinaryReader.u32(b, p, little: little)))
                case 4: value = Double(Float(bitPattern: BinaryReader.u32(b, p, little: little)))
                default: value = Double(bitPattern: BinaryReader.u64(b, p, little: little))
                }
                guard value.isFinite, abs(value) < 99_999 else { continue }
                samples.append(GroundMagSample(time: start.addingTimeInterval(Double(i) * period), x: value))
            }
        }
        return dedupe(samples.sorted { $0.time < $1.time }, by: \.time)
    }

    /// USGS geomagnetism web service JSON (`format=json`, `elements=X`).
    public static func groundUSGS(_ data: Data) throws -> [GroundMagSample] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let times = root["times"] as? [Any],
              let series = (root["values"] as? [[String: Any]])?.first(where: { ($0["id"] as? String) == "X" })
                ?? (root["values"] as? [[String: Any]])?.first,
              let values = series["values"] as? [Any] else {
            throw URLError(.cannotParseResponse)
        }
        var samples: [GroundMagSample] = []
        for (t, v) in zip(times, values) {
            guard let time = SWDate.parse(JSONValue.string(t)), let x = JSONValue.double(v),
                  x.isFinite, abs(x) < 99_999 else { continue }
            samples.append(GroundMagSample(time: time, x: x))
        }
        return samples.sorted { $0.time < $1.time }
    }
}

extension Double {
    /// Whole number with a sign: "+12", "-40", or "0" (never "-0").
    public var signedWhole: String {
        let v = rounded()
        return v == 0 ? "0" : String(format: "%+.0f", v)
    }
}

enum BinaryReader {
    static func u16(_ b: [UInt8], _ at: Int, little: Bool) -> UInt16 {
        let x = UInt16(b[at]) << 8 | UInt16(b[at + 1])
        return little ? x.byteSwapped : x
    }

    static func u32(_ b: [UInt8], _ at: Int, little: Bool) -> UInt32 {
        let x = (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(b[at + $1]) }
        return little ? x.byteSwapped : x
    }

    static func u64(_ b: [UInt8], _ at: Int, little: Bool) -> UInt64 {
        let x = (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(b[at + $1]) }
        return little ? x.byteSwapped : x
    }
}

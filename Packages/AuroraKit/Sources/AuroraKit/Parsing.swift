import Foundation

/// Lenient helpers for NOAA/NASA JSON, whose shapes vary between products (and change over time).
enum JSONValue {
    static func object(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Rows as dictionaries. Handles both `[{...}]` and the older `[[header...], [values...]]` layout.
    static func rows(_ data: Data) throws -> [[String: Any]] {
        let root = try object(data)
        guard let array = root as? [Any] else { throw ParseError.unexpectedShape }
        if let dicts = array as? [[String: Any]] { return dicts }
        guard let header = array.first as? [Any] else { return [] }
        let keys = header.map { "\($0)" }
        return array.dropFirst().compactMap { row in
            guard let values = row as? [Any] else { return nil }
            var dict: [String: Any] = [:]
            for (key, value) in zip(keys, values) { dict[key] = value }
            return dict
        }
    }

    /// Case-insensitive key lookup.
    static func value(_ row: [String: Any], _ key: String) -> Any? {
        if let v = row[key] { return v }
        let lower = key.lowercased()
        return row.first(where: { $0.key.lowercased() == lower })?.value
    }

    static func double(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d.isFinite ? d : nil
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func int(_ any: Any?) -> Int? {
        double(any).map { Int($0.rounded()) }
    }

    static func string(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func bool(_ any: Any?) -> Bool? {
        switch any {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }
}

public enum ParseError: Error, CustomStringConvertible {
    case unexpectedShape
    case empty

    public var description: String {
        switch self {
        case .unexpectedShape: return "Unexpected data format"
        case .empty: return "No data"
        }
    }
}

/// Fast, allocation-light UTC timestamp parsing for the formats used by SWPC, DONKI and Open-Meteo:
/// `2026-10-19T03:09:01`, `2026-10-19T03:09:01Z`, `2026-10-18 17:24:58.920`, `2026-10-20T12:00Z`,
/// `2026-10-19_00:05`, `2026-10-19`.
public enum SWDate {
    public static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        var parts: [Int] = []
        parts.reserveCapacity(6)
        var current = 0
        var inNumber = false
        for scalar in string.unicodeScalars {
            if scalar.value >= 48 && scalar.value <= 57 {
                current = current * 10 + Int(scalar.value - 48)
                inNumber = true
            } else if inNumber {
                parts.append(current)
                current = 0
                inNumber = false
                if parts.count == 6 { break }
            }
        }
        if inNumber && parts.count < 6 { parts.append(current) }
        guard parts.count >= 3 else { return nil }
        let year = parts[0], month = parts[1], day = parts[2]
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let hour = parts.count > 3 ? parts[3] : 0
        let minute = parts.count > 4 ? parts[4] : 0
        let second = parts.count > 5 ? parts[5] : 0
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days) * 86400 + Double(hour * 3600 + minute * 60 + second)
        return Date(timeIntervalSince1970: seconds)
    }

    /// Howard Hinnant's days-from-civil algorithm (proleptic Gregorian, UTC).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    static func month(_ abbreviation: Substring) -> Int? {
        monthNumbers[abbreviation.prefix(3).lowercased()]
    }

    static func utc(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let days = daysFromCivil(year: year, month: month, day: day)
        return Date(timeIntervalSince1970: Double(days) * 86400 + Double(hour * 3600 + minute * 60))
    }
}

// MARK: - Feed parsers

public enum FeedParser {
    /// RTSW 1-minute magnetometer feed. Keeps only rows from the spacecraft NOAA marks as active.
    public static func rtswMag(_ data: Data) throws -> (samples: [MagSample], source: String?) {
        let rows = try JSONValue.rows(data)
        var samples: [MagSample] = []
        var source: String?
        samples.reserveCapacity(rows.count / 2)
        for row in rows {
            if let active = JSONValue.bool(row["active"]), !active { continue }
            guard let time = SWDate.parse(JSONValue.string(row["time_tag"])) else { continue }
            if source == nil { source = JSONValue.string(row["source"]) }
            samples.append(MagSample(
                time: time,
                bt: JSONValue.double(row["bt"]),
                bx: JSONValue.double(row["bx_gsm"]),
                by: JSONValue.double(row["by_gsm"]),
                bz: JSONValue.double(row["bz_gsm"])
            ))
        }
        return (dedupe(samples.sorted { $0.time < $1.time }, by: \.time), source)
    }

    /// RTSW 1-minute plasma (wind) feed, active spacecraft only.
    public static func rtswWind(_ data: Data) throws -> (samples: [PlasmaSample], source: String?) {
        let rows = try JSONValue.rows(data)
        var samples: [PlasmaSample] = []
        var source: String?
        for row in rows {
            if let active = JSONValue.bool(row["active"]), !active { continue }
            guard let time = SWDate.parse(JSONValue.string(row["time_tag"])) else { continue }
            if source == nil { source = JSONValue.string(row["source"]) }
            samples.append(PlasmaSample(
                time: time,
                speed: JSONValue.double(row["proton_speed"]),
                density: JSONValue.double(row["proton_density"]),
                temperature: JSONValue.double(row["proton_temperature"])
            ))
        }
        return (dedupe(samples.sorted { $0.time < $1.time }, by: \.time), source)
    }

    public static func propagated(_ data: Data) throws -> [PropagatedSample] {
        try JSONValue.rows(data).compactMap { row in
            guard let time = SWDate.parse(JSONValue.string(row["time_tag"])),
                  let arrival = SWDate.parse(JSONValue.string(row["propagated_time_tag"])) else { return nil }
            return PropagatedSample(
                time: time, arrival: arrival,
                speed: JSONValue.double(row["speed"]),
                density: JSONValue.double(row["density"]),
                bz: JSONValue.double(row["bz"]),
                bt: JSONValue.double(row["bt"])
            )
        }.sorted { $0.time < $1.time }
    }

    /// `noaa-planetary-k-index.json` (observed 3-hour Kp, last 7 days).
    public static func kpObserved(_ data: Data) throws -> [KpPoint] {
        try JSONValue.rows(data).compactMap { row in
            guard let time = SWDate.parse(JSONValue.string(row["time_tag"])),
                  let kp = JSONValue.double(JSONValue.value(row, "Kp")) else { return nil }
            return KpPoint(time: time, kp: kp, kind: .observed)
        }.sorted { $0.time < $1.time }
    }

    /// `noaa-planetary-k-index-forecast.json` (observed + estimated + predicted 3-hour Kp).
    public static func kpForecast(_ data: Data) throws -> [KpPoint] {
        try JSONValue.rows(data).compactMap { row in
            guard let time = SWDate.parse(JSONValue.string(row["time_tag"])),
                  let kp = JSONValue.double(JSONValue.value(row, "kp")) else { return nil }
            let kind = KpKind(rawValue: (JSONValue.string(row["observed"]) ?? "predicted").lowercased()) ?? .predicted
            return KpPoint(time: time, kp: kp, kind: kind)
        }.sorted { $0.time < $1.time }
    }

    public static func kp1m(_ data: Data) throws -> [EstimatedKp] {
        try JSONValue.rows(data).compactMap { row in
            guard let time = SWDate.parse(JSONValue.string(row["time_tag"])),
                  let kp = JSONValue.double(row["estimated_kp"]) ?? JSONValue.double(row["kp_index"]) else { return nil }
            return EstimatedKp(time: time, kp: kp)
        }.sorted { $0.time < $1.time }
    }

    public static func goesMag(_ data: Data) throws -> [GoesMagSample] {
        try JSONValue.rows(data).compactMap { row in
            guard let time = SWDate.parse(JSONValue.string(row["time_tag"])),
                  let hp = JSONValue.double(JSONValue.value(row, "Hp")) else { return nil }
            if JSONValue.bool(row["arcjet_flag"]) == true { return nil }
            return GoesMagSample(time: time, hp: hp, satellite: JSONValue.int(row["satellite"]) ?? 0)
        }.sorted { $0.time < $1.time }
    }

    /// GOES X-ray flux, long channel (0.1-0.8 nm) only — the one flare classes are based on.
    public static func xray(_ data: Data) throws -> [XraySample] {
        try JSONValue.rows(data).compactMap { row in
            guard (JSONValue.string(row["energy"]) ?? "").contains("0.1-0.8"),
                  let time = SWDate.parse(JSONValue.string(row["time_tag"])),
                  let flux = JSONValue.double(row["flux"]), flux > 0 else { return nil }
            return XraySample(time: time, flux: flux, satellite: JSONValue.int(row["satellite"]) ?? 0)
        }.sorted { $0.time < $1.time }
    }

    public static func latestFlare(_ data: Data) throws -> XrayFlare? {
        guard let row = try JSONValue.rows(data).last else { return nil }
        return XrayFlare(
            begin: SWDate.parse(JSONValue.string(row["begin_time"])),
            peak: SWDate.parse(JSONValue.string(row["max_time"])),
            end: SWDate.parse(JSONValue.string(row["end_time"])),
            maxClass: JSONValue.string(row["max_class"]),
            currentClass: JSONValue.string(row["current_class"]),
            satellite: JSONValue.int(row["satellite"])
        )
    }

    public static func alerts(_ data: Data) throws -> [SWPCAlert] {
        try JSONValue.rows(data).compactMap { row in
            guard let message = JSONValue.string(row["message"]),
                  let issued = SWDate.parse(JSONValue.string(row["issue_datetime"])) else { return nil }
            let productID = JSONValue.string(row["product_id"]) ?? "?"
            let (headline, kind) = alertHeadline(message)
            let serial = message.components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("Serial Number:") })?
                .replacingOccurrences(of: "Serial Number:", with: "")
                .trimmingCharacters(in: .whitespaces) ?? "\(Int(issued.timeIntervalSince1970))"
            return SWPCAlert(
                id: "\(productID)-\(serial)-\(Int(issued.timeIntervalSince1970))", serial: serial, productID: productID, issued: issued,
                message: message.replacingOccurrences(of: "\r\n", with: "\n"),
                headline: headline, kind: kind
            )
        }.sorted { $0.issued > $1.issued }
    }

    static func alertHeadline(_ message: String) -> (String, SWPCAlertKind) {
        let prefixes: [(String, SWPCAlertKind)] = [
            ("CANCEL", .cancel), ("EXTENDED WARNING:", .warning), ("WATCH:", .watch),
            ("WARNING:", .warning), ("ALERT:", .alert), ("SUMMARY:", .summary), ("CONTINUED ALERT:", .alert),
        ]
        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for (prefix, kind) in prefixes where trimmed.hasPrefix(prefix) {
                return (trimmed, kind)
            }
        }
        let fallback = message.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("Space Weather Message Code") && !$0.hasPrefix("Serial") && !$0.hasPrefix("Issue Time") })
        return (fallback ?? "Space weather message", .other)
    }

    public static func scales(_ data: Data) throws -> NOAAScales {
        guard let root = try JSONValue.object(data) as? [String: Any] else { throw ParseError.unexpectedShape }
        func day(_ key: String) -> ScaleDay? {
            guard let d = root[key] as? [String: Any] else { return nil }
            let r = d["R"] as? [String: Any] ?? [:]
            let s = d["S"] as? [String: Any] ?? [:]
            let g = d["G"] as? [String: Any] ?? [:]
            return ScaleDay(
                date: JSONValue.string(d["DateStamp"]) ?? "",
                r: JSONValue.int(r["Scale"]), s: JSONValue.int(s["Scale"]), g: JSONValue.int(g["Scale"]),
                rMinorProb: JSONValue.int(r["MinorProb"]), rMajorProb: JSONValue.int(r["MajorProb"]),
                sProb: JSONValue.int(s["Prob"])
            )
        }
        return NOAAScales(yesterday: day("-1"), current: day("0"), forecast: ["1", "2", "3"].compactMap(day))
    }

    /// Samples the OVATION grid near the observer. The grid is 1°×1°, longitudes 0...359.
    public static func ovation(_ data: Data, latitude: Double, longitude: Double) throws -> OvationLocal {
        guard let root = try JSONValue.object(data) as? [String: Any],
              let coords = root["coordinates"] as? [Any] else { throw ParseError.unexpectedShape }
        let lat0 = Int(latitude.rounded())
        let lon0 = Int((longitude < 0 ? longitude + 360 : longitude).rounded()) % 360
        // Aurora ~100-300 km up is visible well above the northern horizon out to roughly 600 km away.
        let latRange = lat0...(lat0 + 6)
        var overhead = 0
        var maxInView = 0
        for case let point as [Any] in coords where point.count >= 3 {
            guard let lon = JSONValue.int(point[0]), let lat = JSONValue.int(point[1]) else { continue }
            guard latRange.contains(lat) else { continue }
            var dLon = abs(lon - lon0)
            if dLon > 180 { dLon = 360 - dLon }
            guard dLon <= 6 else { continue }
            let value = JSONValue.int(point[2]) ?? 0
            if lat == lat0 && lon == lon0 { overhead = value }
            maxInView = max(maxInView, value)
        }
        return OvationLocal(
            observationTime: SWDate.parse(JSONValue.string(root["Observation Time"])),
            forecastTime: SWDate.parse(JSONValue.string(root["Forecast Time"])),
            overhead: overhead, maxInView: maxInView
        )
    }

    /// `aurora-nowcast-hemi-power.txt`
    public static func hemiPower(_ text: String) -> [HemiPowerPoint] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard cols.count >= 3,
                  let obs = SWDate.parse(String(cols[0])),
                  let fc = SWDate.parse(String(cols[1])),
                  let north = Double(cols[2]) else { return nil }
            return HemiPowerPoint(observed: obs, forecast: fc, north: north)
        }
    }

    /// Splits a SWPC text product into sections ("A. NOAA Geomagnetic Activity ...").
    public static func textProduct(_ text: String) -> TextProduct {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var title = "NOAA product"
        var issued: Date?
        var sections: [TextProduct.Section] = []
        var currentTitle = "Summary"
        var body: [String] = []

        func flush() {
            let joined = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { sections.append(.init(title: currentTitle, body: joined)) }
            body = []
        }

        for line in lines {
            if line.hasPrefix(":Product:") {
                title = line.replacingOccurrences(of: ":Product:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix(":Issued:") {
                issued = parseIssued(line)
                continue
            }
            if line.hasPrefix("#") { continue }
            if isSectionHeader(line) {
                flush()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            body.append(line)
        }
        flush()
        return TextProduct(title: title, issued: issued, raw: text, sections: sections)
    }

    static func isSectionHeader(_ line: String) -> Bool {
        let chars = Array(line)
        return chars.count > 3 && chars[0].isUppercase && chars[0].isLetter && chars[1] == "." && chars[2] == " "
    }

    /// ":Issued: 2026 Oct 19 0030 UTC"
    static func parseIssued(_ line: String) -> Date? {
        let parts = line.replacingOccurrences(of: ":Issued:", with: "").split(separator: " ")
        guard parts.count >= 4, let year = Int(parts[0]), let month = SWDate.month(parts[1]),
              let day = Int(parts[2]), parts[3].count == 4, let hhmm = Int(parts[3]) else { return nil }
        return SWDate.utc(year: year, month: month, day: day, hour: hhmm / 100, minute: hhmm % 100)
    }

    public static func geomagProbabilities(_ text: String) -> GeomagProbabilities {
        let lines = text.components(separatedBy: .newlines)
        var rows: [GeomagProbabilities.Row] = []
        var apLines: [String] = []
        var days: [String] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Ap") && (trimmed.hasPrefix("Observed") || trimmed.hasPrefix("Estimated") || trimmed.hasPrefix("Predicted")) {
                apLines.append(trimmed)
            }
            if days.isEmpty, trimmed.hasPrefix("00-03UT"), index > 0 {
                days = lines[index - 1].components(separatedBy: "  ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            // "Minor storm           40/40/25"
            guard let last = trimmed.split(separator: " ").last, last.contains("/") else { continue }
            let values = last.split(separator: "/").compactMap { Int($0) }
            guard values.count >= 2 else { continue }
            let label = trimmed.dropLast(last.count).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !label.contains("Ap") else { continue }
            rows.append(.init(label: label, values: values))
        }
        return GeomagProbabilities(days: days, rows: rows, apLines: apLines)
    }

    /// `27-day-outlook.txt`
    public static func outlook27(_ text: String) -> [OutlookDay] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#"), !line.hasPrefix(":") else { return nil }
            let cols = line.split(separator: " ")
            guard cols.count >= 6, let year = Int(cols[0]), let month = SWDate.month(cols[1]), let day = Int(cols[2]),
                  let flux = Int(cols[3]), let ap = Int(cols[4]), let kp = Int(cols[5]) else { return nil }
            return OutlookDay(date: SWDate.utc(year: year, month: month, day: day), radioFlux: flux, ap: ap, kp: kp)
        }
    }

    /// DONKI `WSAEnlilSimulations`: keeps runs that predict a shock arrival at Earth.
    public static func enlilArrivals(_ data: Data) throws -> [CMEArrival] {
        // DONKI answers an empty body when there are no runs in the date range.
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard let sims = try JSONValue.object(data) as? [[String: Any]] else { return [] }
        // Several model runs can exist per CME — the most recent run wins, even if it predicts a miss.
        var latest: [String: (completion: Date, arrival: CMEArrival?)] = [:]
        for sim in sims {
            let inputs = sim["cmeInputs"] as? [[String: Any]] ?? []
            let input = inputs.first(where: { JSONValue.bool($0["isMostAccurate"]) == true }) ?? inputs.first ?? [:]
            guard let cmeID = JSONValue.string(input["cmeid"]) ?? JSONValue.string(sim["simulationID"]) else { continue }
            let completion = SWDate.parse(JSONValue.string(sim["modelCompletionTime"])) ?? .distantPast
            if let existing = latest[cmeID], existing.completion > completion { continue }
            let kps = ["kp_90", "kp_135", "kp_180"].compactMap { JSONValue.double(sim[$0]) }
            let arrival = SWDate.parse(JSONValue.string(sim["estimatedShockArrivalTime"])).map { arrival in
                CMEArrival(
                    id: cmeID,
                    cmeStart: SWDate.parse(JSONValue.string(input["cmeStartTime"])),
                    cmeSpeed: JSONValue.double(input["speed"]),
                    time21_5: SWDate.parse(JSONValue.string(input["time21_5"])),
                    modelCompletion: completion,
                    arrival: arrival,
                    isGlancingBlow: JSONValue.bool(sim["isEarthGB"]) ?? false,
                    kpLow: kps.min(), kpHigh: kps.max(),
                    durationHours: JSONValue.double(sim["estimatedDuration"]),
                    link: JSONValue.string(sim["link"])
                )
            }
            latest[cmeID] = (completion, arrival)
        }
        let byCME = latest.compactMapValues { $0.arrival }
        return byCME.values.sorted { $0.arrival < $1.arrival }
    }

    /// Open-Meteo hourly cloud cover (requested with `timezone=GMT`).
    public static func clouds(_ data: Data) throws -> [CloudPoint] {
        guard let root = try JSONValue.object(data) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let times = hourly["time"] as? [Any],
              let total = hourly["cloud_cover"] as? [Any] else { throw ParseError.unexpectedShape }
        let low = hourly["cloud_cover_low"] as? [Any] ?? []
        let mid = hourly["cloud_cover_mid"] as? [Any] ?? []
        let high = hourly["cloud_cover_high"] as? [Any] ?? []
        return times.indices.compactMap { i in
            guard let t = SWDate.parse(JSONValue.string(times[i])),
                  i < total.count, let cover = JSONValue.double(total[i]) else { return nil }
            return CloudPoint(
                time: t, total: cover,
                low: i < low.count ? JSONValue.double(low[i]) : nil,
                mid: i < mid.count ? JSONValue.double(mid[i]) : nil,
                high: i < high.count ? JSONValue.double(high[i]) : nil
            )
        }
    }

    static func dedupe<T>(_ items: [T], by key: KeyPath<T, Date>) -> [T] {
        var result: [T] = []
        result.reserveCapacity(items.count)
        for item in items {
            if let last = result.last, last[keyPath: key] == item[keyPath: key] {
                result[result.count - 1] = item
            } else {
                result.append(item)
            }
        }
        return result
    }
}

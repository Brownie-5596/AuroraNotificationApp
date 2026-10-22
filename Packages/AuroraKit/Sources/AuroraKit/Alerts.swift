import Foundation

public enum AlertKind: String, Codable, CaseIterable {
    case forecastEarly, forecastTomorrow, forecastTonight
    case cmeArrival, cmeSoon
    case bzSouth, shock, activity
    case flare, noaa, test

    public var group: String {
        switch self {
        case .forecastEarly, .forecastTomorrow, .forecastTonight: return "forecast"
        case .cmeArrival, .cmeSoon: return "cme"
        case .bzSouth, .shock, .activity: return "now"
        case .flare: return "sun"
        case .noaa: return "noaa"
        case .test: return "test"
        }
    }
}

/// A notification produced by the alert engine.
public struct AuroraAlert: Codable, Hashable, Identifiable {
    public var id: String
    public var date: Date
    public var kind: AlertKind
    public var title: String
    public var body: String
    /// 1 (min) … 5 (urgent), matches ntfy priorities.
    public var priority: Int
    public var tags: [String]

    public init(id: String, date: Date, kind: AlertKind, title: String, body: String, priority: Int, tags: [String] = []) {
        self.id = id; self.date = date; self.kind = kind; self.title = title; self.body = body
        self.priority = priority; self.tags = tags
    }
}

/// User-tunable alert rules. Every field decodes with a default so new settings never break old saves.
public struct AlertSettings: Codable, Hashable {
    public var location: ObserverLocation = .grandForks

    // Forecast (days ahead)
    public var forecastEnabled = true
    /// Kp that triggers forecast alerts. 4.67 = "5-" = G1.
    public var forecastKp = 4.67
    public var earlyEnabled = true
    public var tomorrowEnabled = true
    public var tonightEnabled = true

    // Real time
    public var nowcastEnabled = true
    /// Bz (nT) that counts as "strongly southward".
    public var bzThreshold = -7.0
    /// How long Bz must stay at/below the threshold.
    public var bzMinutes = 15.0
    public var shockEnabled = true
    public var activityEnabled = true
    public var minActivity: ActivityLevel = .possible
    /// Only send real-time alerts when the sun is below this altitude (°). −6 = end of civil twilight.
    public var darknessGate = true
    public var maxSunAltitude = -6.0

    // Other
    public var cmeEnabled = true
    public var flareEnabled = true
    /// Minimum flare class to alert on.
    public var flareClass = "X1.0"
    public var noaaEnabled = true
    /// Relay NOAA K-index warnings/alerts at or above this K.
    public var noaaMinK = 5

    // Etiquette
    public var cooldownHours = 3.0
    public var quietHoursEnabled = false
    public var quietStartHour = 0
    public var quietEndHour = 6
    public var skipWhenCloudy = false
    public var cloudLimit = 85.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        location = v(.location, d.location)
        forecastEnabled = v(.forecastEnabled, d.forecastEnabled)
        forecastKp = v(.forecastKp, d.forecastKp)
        earlyEnabled = v(.earlyEnabled, d.earlyEnabled)
        tomorrowEnabled = v(.tomorrowEnabled, d.tomorrowEnabled)
        tonightEnabled = v(.tonightEnabled, d.tonightEnabled)
        nowcastEnabled = v(.nowcastEnabled, d.nowcastEnabled)
        bzThreshold = v(.bzThreshold, d.bzThreshold)
        bzMinutes = v(.bzMinutes, d.bzMinutes)
        shockEnabled = v(.shockEnabled, d.shockEnabled)
        activityEnabled = v(.activityEnabled, d.activityEnabled)
        minActivity = v(.minActivity, d.minActivity)
        darknessGate = v(.darknessGate, d.darknessGate)
        maxSunAltitude = v(.maxSunAltitude, d.maxSunAltitude)
        cmeEnabled = v(.cmeEnabled, d.cmeEnabled)
        flareEnabled = v(.flareEnabled, d.flareEnabled)
        flareClass = v(.flareClass, d.flareClass)
        noaaEnabled = v(.noaaEnabled, d.noaaEnabled)
        noaaMinK = v(.noaaMinK, d.noaaMinK)
        cooldownHours = v(.cooldownHours, d.cooldownHours)
        quietHoursEnabled = v(.quietHoursEnabled, d.quietHoursEnabled)
        quietStartHour = v(.quietStartHour, d.quietStartHour)
        quietEndHour = v(.quietEndHour, d.quietEndHour)
        skipWhenCloudy = v(.skipWhenCloudy, d.skipWhenCloudy)
        cloudLimit = v(.cloudLimit, d.cloudLimit)
    }
}

/// What has already been sent, so alerts aren't repeated.
public struct AlertState: Codable {
    public struct Record: Codable, Hashable {
        public var date: Date
        public var value: Double
    }

    public var sent: [String: Record] = [:]
    public var seenNOAA: Set<String> = []
    public var history: [AuroraAlert] = []
    public var initialized = false
    /// Notifications handed to iOS to go off later (see `AlertEngine.plan`), by key.
    public var planned: [String: PlannedAlert] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sent = (try? c.decodeIfPresent([String: Record].self, forKey: .sent)) ?? [:]
        seenNOAA = (try? c.decodeIfPresent(Set<String>.self, forKey: .seenNOAA)) ?? []
        history = (try? c.decodeIfPresent([AuroraAlert].self, forKey: .history)) ?? []
        initialized = (try? c.decodeIfPresent(Bool.self, forKey: .initialized)) ?? false
        planned = (try? c.decodeIfPresent([String: PlannedAlert].self, forKey: .planned)) ?? [:]
    }

    /// Planned notifications whose time has passed have been shown by iOS — count them as sent.
    mutating func absorbFiredPlans(now: Date) {
        for (key, plan) in planned where plan.fireDate <= now {
            sent[key] = Record(date: plan.fireDate, value: plan.value)
            var alert = plan.alert
            alert.date = plan.fireDate
            history.append(alert)
        }
        planned = planned.filter { $0.value.fireDate > now }
    }

    mutating func prune(now: Date) {
        sent = sent.filter { now.timeIntervalSince($0.value.date) < 10 * 86400 }
        if seenNOAA.count > 400 { seenNOAA = Set(seenNOAA.sorted().suffix(200)) }
        if history.count > 150 { history = Array(history.suffix(150)) }
    }
}

/// A notification to schedule with iOS for later delivery.
public struct PlannedAlert: Codable, Hashable {
    public var key: String
    public var fireDate: Date
    public var value: Double
    public var alert: AuroraAlert

    /// Identifier for the pending iOS notification.
    public var notificationID: String { "plan-\(key)" }
}

public enum TimeText {
    public static func time(_ date: Date, _ tz: TimeZone) -> String {
        format(date, tz, "h:mm a")
    }

    public static func dayTime(_ date: Date, _ tz: TimeZone) -> String {
        format(date, tz, "EEE h:mm a")
    }

    public static func day(_ date: Date, _ tz: TimeZone) -> String {
        format(date, tz, "EEE MMM d")
    }

    public static func format(_ date: Date, _ tz: TimeZone, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: date)
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        return "\(hours / 24) d \(hours % 24) h"
    }
}

/// Turns a snapshot into notifications. Shared by the iOS app and the cloud watcher.
public enum AlertEngine {
    public static func evaluate(snapshot: SpaceWeatherSnapshot, settings: AlertSettings, state: inout AlertState, now: Date = Date()) -> [AuroraAlert] {
        let loc = settings.location
        let tz = loc.timeZone
        var alerts: [AuroraAlert] = []
        state.absorbFiredPlans(now: now)
        let firstRun = !state.initialized
        let nowcast = Outlook.nowcast(snapshot: snapshot, location: loc, now: now)
        let nights = Outlook.nights(snapshot: snapshot, location: loc, now: now)

        func cloudNote(_ cover: Double?) -> String {
            guard let cover else { return "" }
            return " Clouds ~\(Int(cover))%."
        }

        // MARK: Forecast alerts — early (2–3 days), tomorrow, tonight
        if settings.forecastEnabled {
            for night in nights where night.maxKp >= settings.forecastKp {
                let stage: AlertKind
                switch night.daysAhead {
                case 0: stage = .forecastTonight
                case 1: stage = .forecastTomorrow
                default: stage = .forecastEarly
                }
                let enabled = [AlertKind.forecastTonight: settings.tonightEnabled,
                               .forecastTomorrow: settings.tomorrowEnabled,
                               .forecastEarly: settings.earlyEnabled][stage] ?? true
                guard enabled else { continue }
                let key = "\(stage.rawValue)-\(dayKey(night.nightOf, tz))"
                // Re-alert only if the forecast is upgraded by a full Kp step.
                if let rec = state.sent[key], night.maxKp < rec.value + 1 { continue }

                alerts.append(forecastAlert(night, stage: stage, key: key, date: now, tz: tz))
                state.sent[key] = .init(date: now, value: night.maxKp)
            }
        }

        // MARK: CME arrivals
        if settings.cmeEnabled {
            for cme in snapshot.cmeArrivals where cme.arrival > now.addingTimeInterval(-6 * 3600) {
                let key = "cme-\(cme.id)"
                if state.sent[key] == nil, cme.arrival > now {
                    var body = "NASA's model predicts a CME \(cme.isGlancingBlow ? "glancing blow" : "impact") around \(TimeText.dayTime(cme.arrival, tz)) (±7 h)"
                    body += " — in about \(TimeText.duration(cme.arrival.timeIntervalSince(now)))."
                    if let lo = cme.kpLow, let hi = cme.kpHigh { body += " Estimated Kp \(Int(lo))–\(Int(hi))." }
                    if let speed = cme.cmeSpeed { body += " Launch speed \(Int(speed)) km/s." }
                    alerts.append(AuroraAlert(id: key, date: now, kind: .cmeArrival, title: "☀️ CME heading for Earth", body: body, priority: 3, tags: ["sunny"]))
                    state.sent[key] = .init(date: now, value: cme.arrival.timeIntervalSince1970)
                }
                let soonKey = "cmesoon-\(cme.id)"
                let untilArrival = cme.arrival.timeIntervalSince(now)
                if state.sent[soonKey] == nil, untilArrival > 0, untilArrival < 8 * 3600 {
                    let body = "Predicted CME arrival in ~\(TimeText.duration(untilArrival)) (\(TimeText.time(cme.arrival, tz)), ±7 h). Watch for a jump in solar wind speed and Bt — the app will alert you when it hits."
                    alerts.append(AuroraAlert(id: soonKey, date: now, kind: .cmeSoon, title: "☄️ CME arrival window opening", body: body, priority: 3, tags: ["hourglass"]))
                    state.sent[soonKey] = .init(date: now, value: 1)
                }
            }
        }

        // MARK: Real-time (heads-up / happening now)
        let quiet = settings.quietHoursEnabled && isQuietHour(now, settings)
        let darkEnough = !settings.darknessGate || nowcast.sunAltitude < settings.maxSunAltitude
        let cloudy = settings.skipWhenCloudy && (nowcast.cloudCover ?? 0) >= settings.cloudLimit
        let cooldown = settings.cooldownHours * 3600

        if settings.nowcastEnabled && !quiet && !cloudy {
            // Shock at L1: arrives within the hour — useful even at dusk.
            if settings.shockEnabled, let shock = nowcast.shock, now.timeIntervalSince(shock.time) < 60 * 60,
               nowcast.sunAltitude < 0 || !settings.darknessGate {
                let key = "shock-\(Int(shock.time.timeIntervalSince1970 / 1800))"
                if state.sent[key] == nil && !recentlySent(state, prefix: "shock-", within: 2 * 3600, now: now) {
                    var body = "Solar wind jumped \(Int(shock.speedBefore))→\(Int(shock.speedAfter)) km/s"
                    if let r = shock.densityRatio { body += ", density ×\(String(format: "%.1f", r))" }
                    if let r = shock.btRatio { body += ", field ×\(String(format: "%.1f", r))" }
                    let eta = shock.earthArrival.timeIntervalSince(now)
                    body += eta > 0
                        ? ". Reaches Earth in ~\(TimeText.duration(eta)) (\(TimeText.time(shock.earthArrival, tz)))."
                        : ". It has reached Earth — watch Bz."
                    body += " If Bz turns south, aurora can follow quickly."
                    alerts.append(AuroraAlert(id: key, date: now, kind: .shock, title: "⚡ Shock wave detected at L1", body: body, priority: 4, tags: ["zap"]))
                    state.sent[key] = .init(date: now, value: shock.speedJump)
                }
            }

            if darkEnough {
                // Sustained southward Bz.
                let sustained = SolarWind.isSustainedSouth(snapshot.mag, threshold: settings.bzThreshold, minutes: settings.bzMinutes, now: now)
                if sustained.0, let mean = sustained.mean {
                    let rec = state.sent["bz"]
                    let fresh = rec == nil || now.timeIntervalSince(rec!.date) > cooldown || mean <= rec!.value - 5
                    if fresh {
                        var body = "Bz has averaged \(String(format: "%.1f", mean)) nT for \(Int(settings.bzMinutes))+ min"
                        if let streak = nowcast.streak, streak.isSouth {
                            body += " (south for \(TimeText.duration(streak.duration)), low \(String(format: "%.1f", streak.minimum)) nT)"
                        }
                        if let v = nowcast.speed { body += " at \(Int(v)) km/s" }
                        body += "."
                        if let tt = nowcast.travelTime { body += " What L1 sees now reaches Earth in ~\(TimeText.duration(tt))." }
                        body += " Aurora may build in the next 30–60 min." + cloudNote(nowcast.cloudCover)
                        alerts.append(AuroraAlert(
                            id: "bz-\(Int(now.timeIntervalSince1970))", date: now, kind: .bzSouth,
                            title: "🧲 Heads up: Bz strongly south", body: body,
                            priority: mean <= settings.bzThreshold * 1.6 ? 4 : 3, tags: ["magnet"]
                        ))
                        state.sent["bz"] = .init(date: now, value: mean)
                    }
                }

                // Overall activity level.
                if settings.activityEnabled, nowcast.level >= settings.minActivity, nowcast.level > .quiet {
                    let rec = state.sent["activity"]
                    let level = Double(nowcast.level.rawValue)
                    let fresh = rec == nil || level > rec!.value || now.timeIntervalSince(rec!.date) > cooldown
                    if fresh {
                        var body = "Aurora chance \(nowcast.score)/100 for \(loc.name)."
                        if let kp = nowcast.estimatedKp { body += " Kp ≈ \(String(format: "%.1f", kp)) — \(nowcast.visibility.description.lowercased())." }
                        if let bz = nowcast.bz { body += " Bz \(String(format: "%+.1f", bz)) nT." }
                        if let hp = nowcast.hemiPower { body += " Power \(Int(hp)) GW." }
                        body += cloudNote(nowcast.cloudCover)
                        let title: String
                        switch nowcast.level {
                        case .strong: title = "🚨 Strong aurora storm in progress"
                        case .likely: title = "🌌 Aurora likely right now"
                        default: title = "👀 Aurora activity building"
                        }
                        alerts.append(AuroraAlert(
                            id: "activity-\(Int(now.timeIntervalSince1970))", date: now, kind: .activity,
                            title: title, body: body, priority: nowcast.level == .strong ? 5 : (nowcast.level == .likely ? 4 : 3),
                            tags: ["rotating_light"]
                        ))
                        state.sent["activity"] = .init(date: now, value: level)
                    }
                }
            }
        }

        // MARK: Big flares (possible CME launch)
        if settings.flareEnabled, let flare = snapshot.latestFlare, let cls = flare.maxClass,
           let flux = FlareClass.flux(cls), flux >= (FlareClass.flux(settings.flareClass) ?? 1e-4),
           let begin = flare.begin, now.timeIntervalSince(begin) < 12 * 3600 {
            let key = "flare-\(Int(begin.timeIntervalSince1970))"
            if state.sent[key] == nil {
                let body = "\(cls) solar flare peaked \(flare.peak.map { TimeText.time($0, tz) } ?? "recently"). Big flares often launch CMEs — if one is Earth-directed it typically arrives in 1–3 days. Watch for NOAA/NASA updates."
                alerts.append(AuroraAlert(id: key, date: now, kind: .flare, title: "☀️ \(cls) flare", body: body, priority: 3, tags: ["fire"]))
                state.sent[key] = .init(date: now, value: flux)
            }
        }

        // MARK: Relayed NOAA watches / warnings / alerts
        if settings.noaaEnabled {
            for alert in snapshot.alerts where !state.seenNOAA.contains(alert.dedupeKey) {
                state.seenNOAA.insert(alert.dedupeKey)
                // On first launch, only pass along very recent messages.
                if firstRun && now.timeIntervalSince(alert.issued) > 2 * 3600 { continue }
                if now.timeIntervalSince(alert.issued) > 24 * 3600 { continue }
                guard relevant(alert, minK: settings.noaaMinK) else { continue }
                let body = noaaBody(alert)
                alerts.append(AuroraAlert(
                    id: "noaa-\(alert.dedupeKey)", date: now, kind: .noaa,
                    title: "NOAA \(alert.kind.title): " + shortHeadline(alert),
                    body: body, priority: alert.kind == .alert ? 4 : 3, tags: ["satellite"]
                ))
            }
        }

        state.initialized = true
        state.history.append(contentsOf: alerts)
        state.prune(now: now)
        return alerts
    }

    static func forecastAlert(_ night: NightOutlook, stage: AlertKind, key: String, date: Date, tz: TimeZone) -> AuroraAlert {
        let kpText = "Kp \(KpFormat.label(night.maxKp))" + (KpFormat.gLabel(night.maxKp).map { " (\($0))" } ?? "")
        let when: String
        switch stage {
        case .forecastTonight: when = "tonight"
        case .forecastTomorrow: when = "tomorrow night"
        default: when = TimeText.format(night.nightOf, tz, "EEEE") + " night"
        }
        var body = "\(kpText) forecast \(when)"
        if let t = night.maxKpTime { body += ", peaking around \(TimeText.dayTime(t, tz))" }
        body += ". \(night.visibility.description)."
        if let dark = night.dark { body += " Dark \(TimeText.time(dark.start, tz))–\(TimeText.time(dark.end, tz))." }
        if let cover = night.cloudCover { body += " Clouds ~\(Int(cover))%." }
        if night.source == .outlook27 { body += " (Early 27-day outlook — low confidence.)" }
        if let cme = night.cmeArrivals.first { body += " CME expected \(TimeText.dayTime(cme.arrival, tz))." }

        let title: String
        switch stage {
        case .forecastTonight: title = "🌌 Aurora possible tonight"
        case .forecastTomorrow: title = "🌌 Aurora watch: tomorrow night"
        default: title = "🔭 Aurora outlook: \(TimeText.format(night.nightOf, tz, "EEEE"))"
        }
        return AuroraAlert(
            id: key + "-\(Int(night.maxKp * 3))", date: date, kind: stage, title: title, body: body,
            priority: stage == .forecastTonight ? 4 : 3, tags: ["milky_way"]
        )
    }

    /// Notifications to hand to iOS now so they go off on time even if the app doesn't get to run
    /// again: the "tonight" alert on the afternoon of a forecast night, the "tomorrow night" alert at
    /// noon the day before, and the CME arrival-window alert. Replaces `state.planned`; call after
    /// `evaluate` and replace any previously scheduled notifications with the result.
    public static func plan(snapshot: SpaceWeatherSnapshot, settings: AlertSettings, state: inout AlertState, now: Date = Date()) -> [PlannedAlert] {
        let loc = settings.location
        let tz = loc.timeZone
        let cal = loc.calendar
        var plans: [PlannedAlert] = []

        func add(_ key: String, _ fireDate: Date, _ value: Double, _ alert: AuroraAlert) {
            guard fireDate > now.addingTimeInterval(60) else { return }
            if let rec = state.sent[key], value < rec.value + 1 { return }
            plans.append(PlannedAlert(key: key, fireDate: fireDate, value: value, alert: alert))
        }

        if settings.forecastEnabled {
            let nights = Outlook.nights(snapshot: snapshot, location: loc, now: now)
            for night in nights where night.daysAhead >= 1 && night.source == .kpForecast && night.maxKp >= settings.forecastKp {
                let asOf = " (Forecast as of \(TimeText.dayTime(now, tz)) — open the app for the latest.)"
                if settings.tonightEnabled, let dark = night.dark {
                    let key = "\(AlertKind.forecastTonight.rawValue)-\(dayKey(night.nightOf, tz))"
                    var alert = forecastAlert(night, stage: .forecastTonight, key: key, date: now, tz: tz)
                    alert.body += asOf
                    add(key, dark.start.addingTimeInterval(-3 * 3600), night.maxKp, alert)
                }
                if settings.tomorrowEnabled, night.daysAhead >= 2,
                   let dayBefore = cal.date(byAdding: .day, value: -1, to: night.nightOf),
                   let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: dayBefore) {
                    let key = "\(AlertKind.forecastTomorrow.rawValue)-\(dayKey(night.nightOf, tz))"
                    var alert = forecastAlert(night, stage: .forecastTomorrow, key: key, date: now, tz: tz)
                    alert.body += asOf
                    add(key, noon, night.maxKp, alert)
                }
            }
        }

        if settings.cmeEnabled {
            for cme in snapshot.cmeArrivals {
                let key = "cmesoon-\(cme.id)"
                let body = "Predicted CME arrival in ~8 h (\(TimeText.dayTime(cme.arrival, tz)), ±7 h). Watch for a jump in solar wind speed and Bt — open the app to check."
                let alert = AuroraAlert(id: key, date: now, kind: .cmeSoon, title: "☄️ CME arrival window opening", body: body, priority: 3, tags: ["hourglass"])
                add(key, cme.arrival.addingTimeInterval(-8 * 3600), 1, alert)
            }
        }

        state.planned = Dictionary(plans.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return plans
    }

    static func dayKey(_ date: Date, _ tz: TimeZone) -> String {
        TimeText.format(date, tz, "yyyy-MM-dd")
    }

    static func isQuietHour(_ now: Date, _ settings: AlertSettings) -> Bool {
        let hour = settings.location.calendar.component(.hour, from: now)
        let s = settings.quietStartHour, e = settings.quietEndHour
        return s <= e ? (hour >= s && hour < e) : (hour >= s || hour < e)
    }

    static func recentlySent(_ state: AlertState, prefix: String, within: TimeInterval, now: Date) -> Bool {
        state.sent.contains { $0.key.hasPrefix(prefix) && now.timeIntervalSince($0.value.date) < within }
    }

    static func relevant(_ alert: SWPCAlert, minK: Int) -> Bool {
        guard alert.kind != .cancel else { return false }
        let h = alert.headline
        if let k = alert.kIndex { return k >= minK && alert.kind != .summary }
        if alert.kind == .watch, alert.isGeomagnetic, let g = alert.gLevel { return g + 4 >= minK }
        if h.localizedCaseInsensitiveContains("Sudden Impulse") { return true }
        if h.localizedCaseInsensitiveContains("Interplanetary Shock") { return true }
        return false
    }

    static func shortHeadline(_ alert: SWPCAlert) -> String {
        var h = alert.headline
        for prefix in ["EXTENDED WARNING:", "WARNING:", "WATCH:", "ALERT:", "SUMMARY:", "CONTINUED ALERT:"] where h.hasPrefix(prefix) {
            h = String(h.dropFirst(prefix.count))
        }
        return h.trimmingCharacters(in: .whitespaces)
    }

    static func noaaBody(_ alert: SWPCAlert) -> String {
        let interesting = ["Highest Storm Level", "Valid From", "Valid To", "Threshold Reached", "Observed", "Deviation",
                           "Synoptic Period", "Warning Condition", "Predicted", "Comment"]
        let lines = alert.message.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var picked: [String] = []
        for (i, line) in lines.enumerated() where interesting.contains(where: { line.hasPrefix($0) }) {
            if line.hasPrefix("Comment:") && line.count <= 9 { continue }
            picked.append(line)
            if line.hasPrefix("Highest Storm Level"), i + 1 < lines.count { picked.append(lines[i + 1]) }
        }
        return picked.isEmpty ? shortHeadline(alert) : picked.joined(separator: "\n")
    }
}

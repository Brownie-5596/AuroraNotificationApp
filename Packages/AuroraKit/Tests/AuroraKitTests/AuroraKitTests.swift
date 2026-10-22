@testable import AuroraKit
import XCTest

final class ParsingTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try Data(contentsOf: url)
    }

    func text(_ name: String) throws -> String {
        String(decoding: try fixture(name), as: UTF8.self)
    }

    func testDates() {
        let expected = SWDate.utc(year: 2026, month: 10, day: 19, hour: 3, minute: 9).addingTimeInterval(1)
        XCTAssertEqual(SWDate.parse("2026-10-19T03:09:01"), expected)
        XCTAssertEqual(SWDate.parse("2026-10-19T03:09:01Z"), expected)
        XCTAssertEqual(SWDate.parse("2026-10-19 03:09:01.920"), expected)
        XCTAssertEqual(SWDate.parse("2026-10-20T12:00Z"), SWDate.utc(year: 2026, month: 10, day: 20, hour: 12))
        XCTAssertEqual(SWDate.parse("2026-10-19_00:05"), SWDate.utc(year: 2026, month: 10, day: 19, hour: 0, minute: 5))
        XCTAssertEqual(SWDate.parse("1970-01-01T00:00:00")?.timeIntervalSince1970, 0)
        XCTAssertNil(SWDate.parse("garbage"))
    }

    func testRTSWKeepsActiveSpacecraftOnly() throws {
        let mag = try FeedParser.rtswMag(try fixture("rtsw_mag_1m.json"))
        XCTAssertFalse(mag.samples.isEmpty)
        XCTAssertNotNil(mag.source)
        XCTAssertEqual(mag.samples, mag.samples.sorted { $0.time < $1.time })
        // One row per minute after filtering out inactive spacecraft.
        XCTAssertEqual(Set(mag.samples.map(\.time)).count, mag.samples.count)

        let wind = try FeedParser.rtswWind(try fixture("rtsw_wind_1m.json"))
        XCTAssertFalse(wind.samples.isEmpty)
        XCTAssertTrue(wind.samples.allSatisfy { ($0.speed ?? 400) > 100 })
    }

    func testKp() throws {
        let observed = try FeedParser.kpObserved(try fixture("kp.json"))
        XCTAssertGreaterThan(observed.count, 40)
        let forecast = try FeedParser.kpForecast(try fixture("kp_forecast.json"))
        XCTAssertTrue(forecast.contains { $0.kind == .predicted })
        XCTAssertTrue(forecast.contains { $0.kind == .observed })
        XCTAssertEqual(forecast.map(\.kp).max() ?? 0, 4.67, accuracy: 0.01)
    }

    func testLegacyArrayOfArraysLayout() throws {
        let legacy = #"[["time_tag","Kp","a_running","station_count"],["2024-05-10 18:00:00.000","8.67","207","8"]]"#
        let kp = try FeedParser.kpObserved(Data(legacy.utf8))
        XCTAssertEqual(kp.first?.kp, 8.67)
    }

    func testAlerts() throws {
        let alerts = try FeedParser.alerts(try fixture("alerts.json"))
        XCTAssertFalse(alerts.isEmpty)
        let watch = try XCTUnwrap(alerts.first { $0.kind == .watch })
        XCTAssertTrue(watch.headline.hasPrefix("WATCH:"))
        XCTAssertEqual(watch.gLevel, 1)
        XCTAssertEqual(Set(alerts.map(\.id)).count, alerts.count)
    }

    func testScalesOvationHemiPower() throws {
        let scales = try FeedParser.scales(try fixture("scales.json"))
        XCTAssertEqual(scales.forecast.count, 3)
        XCTAssertEqual(scales.forecast.first?.g, 1)

        let gf = ObserverLocation.grandForks
        let ov = try FeedParser.ovation(try fixture("ovation.json"), latitude: gf.latitude, longitude: gf.longitude)
        XCTAssertNotNil(ov.forecastTime)
        XCTAssertGreaterThanOrEqual(ov.maxInView, ov.overhead)

        let hp = FeedParser.hemiPower(try text("hemi-power.txt"))
        XCTAssertGreaterThan(hp.count, 10)
        XCTAssertEqual(hp.first?.north, 12)
    }

    func testTextProducts() throws {
        let product = FeedParser.textProduct(try text("3-day-forecast.txt"))
        XCTAssertEqual(product.title, "3-Day Forecast")
        XCTAssertEqual(product.issued, SWDate.utc(year: 2026, month: 10, day: 19, hour: 0, minute: 30))
        XCTAssertTrue(product.sections.contains { $0.title.contains("Geomagnetic") })

        let probs = FeedParser.geomagProbabilities(try text("3-day-geomag-forecast.txt"))
        XCTAssertEqual(probs.rows.first?.label, "Active")
        XCTAssertEqual(probs.rows.first?.values, [35, 30, 40])
        XCTAssertEqual(probs.rows.count, 4)
        XCTAssertEqual(probs.days, ["Oct 19", "Oct 20", "Oct 21"])

        let outlook = FeedParser.outlook27(try text("27-day-outlook.txt"))
        XCTAssertEqual(outlook.count, 27)
        XCTAssertEqual(outlook.first?.kp, 5)
    }

    func testEnlilKeepsLatestRunPerCME() throws {
        let arrivals = try FeedParser.enlilArrivals(try fixture("enlil.json"))
        // CME-001 (latest run) arrives; the second CME's latest run predicts a miss.
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals.first?.arrival, SWDate.utc(year: 2026, month: 10, day: 19, hour: 15))
        XCTAssertEqual(arrivals.first?.isGlancingBlow, true)
        XCTAssertEqual(arrivals.first?.kpLow, 5)
        XCTAssertEqual(arrivals.first?.kpHigh, 6)
        XCTAssertTrue(try FeedParser.enlilArrivals(Data()).isEmpty)
    }

    func testClouds() throws {
        let clouds = try FeedParser.clouds(try fixture("clouds.json"))
        XCTAssertGreaterThan(clouds.count, 24)
    }
}

final class ScienceTests: XCTestCase {
    func testGrandForksThresholds() {
        let gf = ObserverLocation.grandForks
        XCTAssertEqual(gf.geomagneticLatitude, 56.1, accuracy: 0.5)
        let t = gf.visibility
        XCTAssertEqual(t.overhead, 5.1, accuracy: 0.3)
        XCTAssertEqual(t.visibility(kp: 2), .unlikely)
        XCTAssertEqual(t.visibility(kp: 3.67), .cameraOnly)
        XCTAssertEqual(t.visibility(kp: 4.33), .horizon)
        XCTAssertEqual(t.visibility(kp: 6), .overhead)
    }

    func testKpLabels() {
        XCTAssertEqual(KpFormat.label(4.67), "5-")
        XCTAssertEqual(KpFormat.label(5.0), "5")
        XCTAssertEqual(KpFormat.label(5.33), "5+")
        XCTAssertEqual(KpFormat.label(0.33), "0+")
        XCTAssertEqual(KpFormat.gScale(4.67), 1)
        XCTAssertEqual(KpFormat.gScale(4.33), 0)
        XCTAssertEqual(KpFormat.gScale(9), 5)
    }

    func testFlareClass() {
        XCTAssertEqual(FlareClass.label(flux: 2.4e-5), "M2.4")
        XCTAssertEqual(FlareClass.flux("X1.0")!, 1e-4, accuracy: 1e-9)
        XCTAssertGreaterThan(FlareClass.flux("X2.1")!, FlareClass.flux("M9.9")!)
    }

    func testSunAndDarkness() {
        let gf = ObserverLocation.grandForks
        // Local noon-ish (18 UTC) in October: sun well up. 06 UTC: deep night.
        let noon = SWDate.utc(year: 2026, month: 10, day: 19, hour: 18)
        let midnight = SWDate.utc(year: 2026, month: 10, day: 19, hour: 6)
        XCTAssertGreaterThan(Sky.sunAltitude(at: noon, for: gf), 25)
        XCTAssertLessThan(Sky.sunAltitude(at: midnight, for: gf), -30)

        let nightOf = gf.calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let dark = try! XCTUnwrap(Sky.darkWindow(nightOf: nightOf, location: gf))
        // Nautical dusk in Grand Forks in late October is about 7:40 PM CDT (00:40 UTC).
        let darkStartHourUTC = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: dark.start).hour
        XCTAssertEqual(darkStartHourUTC, 0)
        XCTAssertGreaterThan(dark.duration, 10 * 3600)
    }

    func testMoon() {
        // Full moon 2026-10-26 ~04:12 UTC; new moon 2026-10-10 ~16:50 UTC.
        XCTAssertGreaterThan(Sky.moonIllumination(at: SWDate.utc(year: 2026, month: 10, day: 26, hour: 4)), 0.95)
        XCTAssertLessThan(Sky.moonIllumination(at: SWDate.utc(year: 2026, month: 10, day: 10, hour: 17)), 0.05)
    }

    func testDragBasedTransit() throws {
        let t0 = Date(timeIntervalSince1970: 0)
        let fast = try XCTUnwrap(CMETransit.dragBasedArrival(speed: 2000, launchedAt: t0))
        let medium = try XCTUnwrap(CMETransit.dragBasedArrival(speed: 1000, launchedAt: t0))
        let slow = try XCTUnwrap(CMETransit.dragBasedArrival(speed: 500, launchedAt: t0))
        XCTAssertLessThan(fast.travelTime, medium.travelTime)
        XCTAssertLessThan(medium.travelTime, slow.travelTime)
        // A 1000 km/s CME typically takes ~2–3 days.
        XCTAssertEqual(medium.travelTime / 86400, 2.4, accuracy: 0.8)
        XCTAssertLessThan(medium.arrivalSpeed, 1000)
        XCTAssertGreaterThan(medium.arrivalSpeed, 400)
    }

    func testTravelTimeFromL1() {
        XCTAssertEqual(SolarWind.travelTime(speed: 400) / 60, 62.5, accuracy: 0.1)
        XCTAssertEqual(SolarWind.travelTime(speed: 750) / 60, 33.3, accuracy: 0.1)
    }
}

final class AnalysisTests: XCTestCase {
    let t0 = SWDate.utc(year: 2026, month: 10, day: 20, hour: 4) // 11 PM CDT

    func mag(_ values: [Double], end: Date) -> [MagSample] {
        values.enumerated().map { i, bz in
            MagSample(time: end.addingTimeInterval(Double(i - values.count + 1) * 60), bt: abs(bz) + 2, bx: 0, by: 0, bz: bz)
        }
    }

    func plasma(_ speeds: [Double], density: [Double]? = nil, end: Date) -> [PlasmaSample] {
        speeds.enumerated().map { i, v in
            PlasmaSample(time: end.addingTimeInterval(Double(i - speeds.count + 1) * 60), speed: v, density: density?[i] ?? 5, temperature: 1e5)
        }
    }

    func testBzStreak() throws {
        // 60 min north, then 40 min south with a 2-minute northward blip that shouldn't break the run.
        var values = Array(repeating: 3.0, count: 60) + Array(repeating: -8.0, count: 20) + [1, 1] + Array(repeating: -12.0, count: 18)
        values[values.count - 1] = -15
        let streak = try XCTUnwrap(SolarWind.bzStreak(mag(values, end: t0), threshold: -7, now: t0))
        XCTAssertTrue(streak.isSouth)
        XCTAssertEqual(streak.duration / 60, 40, accuracy: 1)
        XCTAssertEqual(streak.minimum, -15)
        XCTAssertEqual(streak.belowThresholdDuration / 60, 40, accuracy: 1)
        XCTAssertGreaterThan(streak.integral, 300)
        XCTAssertEqual(streak.southFractionLast3h, 38.0 / 100.0, accuracy: 0.01)
    }

    func testBzStreakBrokenByLongExcursion() throws {
        let values = Array(repeating: -9.0, count: 30) + Array(repeating: 4.0, count: 10) + Array(repeating: -6.0, count: 10)
        let streak = try XCTUnwrap(SolarWind.bzStreak(mag(values, end: t0), threshold: -7, now: t0))
        XCTAssertEqual(streak.duration / 60, 10, accuracy: 1)
        XCTAssertEqual(streak.belowThresholdDuration, 0)
    }

    func testSustainedSouth() {
        let samples = mag(Array(repeating: 2.0, count: 30) + Array(repeating: -9.0, count: 20), end: t0)
        XCTAssertTrue(SolarWind.isSustainedSouth(samples, threshold: -7, minutes: 15, now: t0).0)
        XCTAssertFalse(SolarWind.isSustainedSouth(samples, threshold: -7, minutes: 30, now: t0).0)
        XCTAssertFalse(SolarWind.isSustainedSouth(samples, threshold: -10, minutes: 15, now: t0).0)
    }

    func testShockDetection() throws {
        let speeds = Array(repeating: 380.0, count: 60) + Array(repeating: 520.0, count: 20)
        let density = Array(repeating: 4.0, count: 60) + Array(repeating: 11.0, count: 20)
        let p = plasma(speeds, density: density, end: t0)
        let m = mag(Array(repeating: -2.0, count: 60) + Array(repeating: -10.0, count: 20), end: t0)
        let shock = try XCTUnwrap(SolarWind.detectShock(plasma: p, mag: m, now: t0))
        XCTAssertEqual(shock.speedJump, 140, accuracy: 1)
        XCTAssertEqual(shock.time, t0.addingTimeInterval(-19 * 60))
        XCTAssertGreaterThan(shock.densityRatio ?? 0, 2)
        XCTAssertEqual(shock.earthArrival.timeIntervalSince(shock.time) / 60, 1.5e6 / 520 / 60, accuracy: 0.5)

        // Steady wind: nothing.
        XCTAssertNil(SolarWind.detectShock(plasma: plasma(Array(repeating: 420, count: 80), end: t0), mag: m, now: t0))
    }

    func stormSnapshot(kp: Double, bz: Double, speed: Double) -> SpaceWeatherSnapshot {
        var s = SpaceWeatherSnapshot(fetchedAt: t0)
        s.mag = mag(Array(repeating: 2, count: 60) + Array(repeating: bz, count: 40), end: t0)
        s.plasma = plasma(Array(repeating: speed, count: 100), end: t0)
        s.kp1m = [EstimatedKp(time: t0, kp: kp)]
        s.hemiPower = [HemiPowerPoint(observed: t0, forecast: t0.addingTimeInterval(1800), north: kp * 15)]
        return s
    }

    func testNowcastLevels() {
        let gf = ObserverLocation.grandForks
        let quiet = Outlook.nowcast(snapshot: stormSnapshot(kp: 1, bz: 3, speed: 350), location: gf, now: t0)
        XCTAssertEqual(quiet.level, .quiet)
        let likely = Outlook.nowcast(snapshot: stormSnapshot(kp: 4.33, bz: -10, speed: 500), location: gf, now: t0)
        XCTAssertGreaterThanOrEqual(likely.level, .likely)
        let strong = Outlook.nowcast(snapshot: stormSnapshot(kp: 7, bz: -20, speed: 750), location: gf, now: t0)
        XCTAssertEqual(strong.level, .strong)
        XCTAssertTrue(strong.isDark)
        XCTAssertGreaterThan(strong.score, likely.score)
    }

    func testAlertEngineRealtimeAndCooldown() {
        var settings = AlertSettings()
        settings.noaaEnabled = false
        settings.forecastEnabled = false
        var state = AlertState()
        let snap = stormSnapshot(kp: 5, bz: -12, speed: 550)
        let first = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: t0)
        XCTAssertTrue(first.contains { $0.kind == .bzSouth })
        XCTAssertTrue(first.contains { $0.kind == .activity })

        // Ten minutes later, same conditions: no repeats.
        let second = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: t0.addingTimeInterval(600))
        XCTAssertTrue(second.isEmpty, "\(second.map(\.title))")
    }

    func testDaylightGate() {
        var settings = AlertSettings()
        settings.noaaEnabled = false
        settings.forecastEnabled = false
        var state = AlertState()
        let noon = SWDate.utc(year: 2026, month: 10, day: 20, hour: 18)
        var snap = stormSnapshot(kp: 5, bz: -12, speed: 550)
        snap.mag = mag(Array(repeating: -12, count: 40), end: noon)
        snap.plasma = plasma(Array(repeating: 550, count: 40), end: noon)
        snap.kp1m = [EstimatedKp(time: noon, kp: 5)]
        XCTAssertTrue(AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: noon).isEmpty)
        settings.darknessGate = false
        XCTAssertFalse(AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: noon).isEmpty)
    }

    func testForecastStagesAndUpgrade() {
        var settings = AlertSettings()
        settings.nowcastEnabled = false
        settings.noaaEnabled = false
        // Midday Oct 19 CDT. Forecast: tomorrow night (Oct 20 evening → Oct 21 UTC) Kp 5.
        let now = SWDate.utc(year: 2026, month: 10, day: 19, hour: 17)
        var snap = SpaceWeatherSnapshot(fetchedAt: now)
        var blocks: [KpPoint] = []
        for h in stride(from: 0, to: 96, by: 3) {
            let t = SWDate.utc(year: 2026, month: 10, day: 19).addingTimeInterval(Double(h) * 3600)
            let isTarget = (h == 51) // Oct 21 03 UTC = Oct 20 10 PM CDT
            blocks.append(KpPoint(time: t, kp: isTarget ? 5.0 : 2.0, kind: .predicted))
        }
        snap.kpForecast = blocks
        var state = AlertState()
        let alerts = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: now)
        XCTAssertEqual(alerts.map(\.kind), [.forecastTomorrow])
        XCTAssertTrue(alerts[0].body.contains("Kp 5 "))

        // Same forecast later: nothing. Upgraded by a full step: alert again.
        XCTAssertTrue(AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: now.addingTimeInterval(3600)).isEmpty)
        snap.kpForecast[17].kp = 6.33
        let upgraded = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: now.addingTimeInterval(7200))
        XCTAssertEqual(upgraded.map(\.kind), [.forecastTomorrow])

        // The next day it becomes a "tonight" alert.
        let tonight = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: now.addingTimeInterval(86400))
        XCTAssertEqual(tonight.map(\.kind), [.forecastTonight])
    }

    func testNOAARelayAndFirstRun() throws {
        var settings = AlertSettings()
        settings.nowcastEnabled = false
        settings.forecastEnabled = false
        let msg = "Space Weather Message Code: WARK05\r\nSerial Number: 99\r\nIssue Time: 2026 Oct 20 0300 UTC\r\n\r\nWARNING: Geomagnetic K-index of 5 expected\r\nValid From: 2026 Oct 20 0300 UTC\r\nValid To: 2026 Oct 20 0900 UTC\r\nWarning Condition: Onset"
        let json = try JSONSerialization.data(withJSONObject: [["product_id": "K05W", "issue_datetime": "2026-10-20 03:00:00.000", "message": msg]])
        var snap = SpaceWeatherSnapshot(fetchedAt: t0)
        snap.alerts = try FeedParser.alerts(json)
        XCTAssertEqual(snap.alerts.first?.kIndex, 5)
        var state = AlertState()
        let alerts = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: t0)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertTrue(alerts[0].body.contains("Valid From"))
        XCTAssertTrue(AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: t0).isEmpty)
    }

    func testSettingsDecodeWithMissingKeys() throws {
        let settings = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"bzThreshold": -10}"#.utf8))
        XCTAssertEqual(settings.bzThreshold, -10)
        XCTAssertEqual(settings.forecastKp, 4.67)
        XCTAssertEqual(settings.location, .grandForks)
    }

    func forecastSnapshot(now: Date, targetBlockHour: Int, kp: Double) -> SpaceWeatherSnapshot {
        var snap = SpaceWeatherSnapshot(fetchedAt: now)
        snap.kpForecast = stride(from: 0, to: 120, by: 3).map { h in
            KpPoint(time: SWDate.utc(year: 2026, month: 10, day: 19).addingTimeInterval(Double(h) * 3600),
                    kp: h == targetBlockHour ? kp : 2, kind: .predicted)
        }
        return snap
    }

    func testPlanSchedulesTonightAndTomorrowReminders() throws {
        var settings = AlertSettings()
        settings.nowcastEnabled = false
        settings.noaaEnabled = false
        // Monday Oct 19, noon CDT. Kp 5 forecast for Wednesday night (Oct 21 evening = Oct 22 03 UTC).
        let now = SWDate.utc(year: 2026, month: 10, day: 19, hour: 17)
        let snap = forecastSnapshot(now: now, targetBlockHour: 75, kp: 5)
        var state = AlertState()
        let live = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: now)
        XCTAssertEqual(live.map(\.kind), [.forecastEarly])

        let plans = AlertEngine.plan(snapshot: snap, settings: settings, state: &state, now: now)
        XCTAssertEqual(Set(plans.map(\.alert.kind)), [.forecastTomorrow, .forecastTonight])
        let tz = settings.location.timeZone
        let tomorrow = try XCTUnwrap(plans.first { $0.alert.kind == .forecastTomorrow })
        XCTAssertEqual(TimeText.format(tomorrow.fireDate, tz, "EEE HH:mm"), "Tue 12:00")
        let tonight = try XCTUnwrap(plans.first { $0.alert.kind == .forecastTonight })
        XCTAssertEqual(TimeText.format(tonight.fireDate, tz, "EEE"), "Wed")
        XCTAssertTrue(tonight.alert.body.contains("Forecast as of"))
        XCTAssertEqual(state.planned.count, 2)

        // Wednesday afternoon, after both reminders went off: the engine must not repeat them.
        let wednesday = tonight.fireDate.addingTimeInterval(1800)
        let later = AlertEngine.evaluate(snapshot: snap, settings: settings, state: &state, now: wednesday)
        XCTAssertTrue(later.isEmpty, "\(later.map(\.title))")
        XCTAssertTrue(state.history.contains { $0.kind == .forecastTonight })
        XCTAssertTrue(AlertEngine.plan(snapshot: snap, settings: settings, state: &state, now: wednesday).isEmpty)
    }

    func testPlanSkipsWhenForecastDropsAndReplacesOldPlans() {
        var settings = AlertSettings()
        settings.nowcastEnabled = false
        settings.noaaEnabled = false
        let now = SWDate.utc(year: 2026, month: 10, day: 19, hour: 17)
        var state = AlertState()
        _ = AlertEngine.plan(snapshot: forecastSnapshot(now: now, targetBlockHour: 75, kp: 5), settings: settings, state: &state, now: now)
        XCTAssertFalse(state.planned.isEmpty)
        // Forecast downgraded an hour later: nothing should stay scheduled.
        let plans = AlertEngine.plan(snapshot: forecastSnapshot(now: now, targetBlockHour: 75, kp: 3), settings: settings, state: &state, now: now.addingTimeInterval(3600))
        XCTAssertTrue(plans.isEmpty)
        XCTAssertTrue(state.planned.isEmpty)
    }

    func testPlanCMEReminder() {
        var settings = AlertSettings()
        settings.forecastEnabled = false
        var snap = SpaceWeatherSnapshot(fetchedAt: t0)
        snap.cmeArrivals = [CMEArrival(id: "cme1", arrival: t0.addingTimeInterval(30 * 3600), isGlancingBlow: false)]
        var state = AlertState()
        let plans = AlertEngine.plan(snapshot: snap, settings: settings, state: &state, now: t0)
        XCTAssertEqual(plans.map(\.key), ["cmesoon-cme1"])
        XCTAssertEqual(plans[0].fireDate, t0.addingTimeInterval(22 * 3600))
    }

    func testOldAlertStateStillDecodes() throws {
        let old = #"{"sent": {"bz": {"date": 1, "value": -8}}, "seenNOAA": ["a"], "history": [], "initialized": true}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(AlertState.self, from: Data(old.utf8))
        XCTAssertEqual(state.sent["bz"]?.value, -8)
        XCTAssertTrue(state.initialized)
        XCTAssertTrue(state.planned.isEmpty)
    }

    func testMergeLiveSolarWind() {
        let old = mag(Array(repeating: -3.0, count: 120), end: t0.addingTimeInterval(-30 * 60))
        let new = mag(Array(repeating: -9.0, count: 60), end: t0)
        let merged = SpaceWeatherClient.merge(old, new, now: t0)
        XCTAssertEqual(merged.count, 90 + 60)
        XCTAssertEqual(merged, merged.sorted { $0.time < $1.time })
        XCTAssertEqual(merged.last?.bz, -9)
    }

    func testKpSurvivesThreeHourReset() {
        // 17:30–17:59 UTC at Kp 4.33, then NOAA's estimate restarts from 0 at 18:00.
        let block = SWDate.utc(year: 2026, month: 10, day: 22, hour: 18)
        var snap = SpaceWeatherSnapshot(fetchedAt: block)
        snap.kp1m = (0..<30).map { EstimatedKp(time: block.addingTimeInterval(Double($0 - 30) * 60), kp: 4.33) }
            + (0..<10).map { EstimatedKp(time: block.addingTimeInterval(Double($0) * 60), kp: $0 < 6 ? 0 : 0.33) }
        let now = block.addingTimeInterval(9 * 60)
        XCTAssertEqual(Outlook.currentKp(snap, now: now) ?? 0, 4.33, accuracy: 0.01)
        XCTAssertEqual(Outlook.nowcast(snapshot: snap, location: .grandForks, now: now).estimatedKp ?? 0, 4.33, accuracy: 0.01)
    }
}

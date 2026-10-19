import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads every feed the app uses. Failures of individual feeds are recorded in `snapshot.errors`
/// rather than failing the whole refresh.
public final class SpaceWeatherClient {
    public static let swpc = "https://services.swpc.noaa.gov"

    public enum Feed: String, CaseIterable {
        case mag, wind, propagated, kp, kpForecast, kp1m, hemiPower, goesPrimary, goesSecondary, xray, flare
        case alerts, scales, ovation, threeDay, geomag, outlook27, enlil, clouds
    }

    let session: URLSession
    /// Optional NASA API key used as a fallback for DONKI (falls back to DEMO_KEY).
    public var nasaAPIKey: String?

    public init(session: URLSession? = nil, nasaAPIKey: String? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 25
            config.timeoutIntervalForResource = 40
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = ["User-Agent": "AuroraWatch/1.0 (personal aurora alerts)"]
            self.session = URLSession(configuration: config)
        }
        self.nasaAPIKey = nasaAPIKey
    }

    public func data(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: url) { data, response, error in
                if let error { continuation.resume(throwing: error); return }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continuation.resume(throwing: URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) for \(url.lastPathComponent)"]))
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
            task.resume()
        }
    }

    func swpc(_ path: String) -> URL { URL(string: Self.swpc + path)! }

    /// Fetches a full snapshot. Slow-changing feeds (CMEs, clouds, 27-day outlook) are reused from
    /// `previous` when it is recent enough, to be kind to the APIs and the battery.
    public func fetchSnapshot(location: ObserverLocation, previous: SpaceWeatherSnapshot? = nil, now: Date = Date()) async -> SpaceWeatherSnapshot {
        var snap = SpaceWeatherSnapshot(fetchedAt: now)

        async let mag = attempt { try FeedParser.rtswMag(try await self.data(self.swpc("/json/rtsw/rtsw_mag_1m.json"))) }
        async let wind = attempt { try FeedParser.rtswWind(try await self.data(self.swpc("/json/rtsw/rtsw_wind_1m.json"))) }
        async let propagated = attempt { try FeedParser.propagated(try await self.data(self.swpc("/products/geospace/propagated-solar-wind-1-hour.json"))) }
        async let kp = attempt { try FeedParser.kpObserved(try await self.data(self.swpc("/products/noaa-planetary-k-index.json"))) }
        async let kpForecast = attempt { try FeedParser.kpForecast(try await self.data(self.swpc("/products/noaa-planetary-k-index-forecast.json"))) }
        async let kp1m = attempt { try FeedParser.kp1m(try await self.data(self.swpc("/json/planetary_k_index_1m.json"))) }
        async let hemi = attempt { FeedParser.hemiPower(String(decoding: try await self.data(self.swpc("/text/aurora-nowcast-hemi-power.txt")), as: UTF8.self)) }
        async let goes1 = attempt { try FeedParser.goesMag(try await self.data(self.swpc("/json/goes/primary/magnetometers-1-day.json"))) }
        async let goes2 = attempt { try FeedParser.goesMag(try await self.data(self.swpc("/json/goes/secondary/magnetometers-1-day.json"))) }
        async let xray = attempt { try FeedParser.xray(try await self.data(self.swpc("/json/goes/primary/xrays-1-day.json"))) }
        async let flare = attempt { try FeedParser.latestFlare(try await self.data(self.swpc("/json/goes/primary/xray-flares-latest.json"))) }
        async let alerts = attempt { try FeedParser.alerts(try await self.data(self.swpc("/products/alerts.json"))) }
        async let scales = attempt { try FeedParser.scales(try await self.data(self.swpc("/products/noaa-scales.json"))) }
        async let ovation = attempt { try FeedParser.ovation(try await self.data(self.swpc("/json/ovation_aurora_latest.json")), latitude: location.latitude, longitude: location.longitude) }
        async let threeDay = attempt { String(decoding: try await self.data(self.swpc("/text/3-day-forecast.txt")), as: UTF8.self) }
        async let geomag = attempt { String(decoding: try await self.data(self.swpc("/text/3-day-geomag-forecast.txt")), as: UTF8.self) }

        let reuseOutlook = previous.flatMap { p in p.outlookFetchedAt.map { now.timeIntervalSince($0) < 6 * 3600 && !p.outlook27.isEmpty } } ?? false
        let reuseCME = previous.flatMap { p in p.cmeFetchedAt.map { now.timeIntervalSince($0) < 3 * 3600 } } ?? false
        let reuseClouds = previous.flatMap { p in p.cloudsFetchedAt.map { now.timeIntervalSince($0) < 2 * 3600 && !p.clouds.isEmpty } } ?? false

        let previousOutlook = previous?.outlook27Raw ?? ""
        let previousCME = previous?.cmeArrivals ?? []
        let previousClouds = previous?.clouds ?? []
        async let outlook = attempt { () async throws -> String in
            if reuseOutlook { return previousOutlook }
            return String(decoding: try await self.data(self.swpc("/text/27-day-outlook.txt")), as: UTF8.self)
        }
        async let cme = attempt { () async throws -> [CMEArrival] in
            if reuseCME { return previousCME }
            return try await self.fetchCMEArrivals(now: now)
        }
        async let clouds = attempt { () async throws -> [CloudPoint] in
            if reuseClouds { return previousClouds }
            return try await self.fetchClouds(location: location)
        }

        func take<T>(_ result: Result<T, Error>, _ feed: Feed, _ fallback: T? = nil) -> T? {
            switch result {
            case .success(let value): return value
            case .failure(let error):
                snap.errors[feed.rawValue] = describe(error)
                return fallback
            }
        }

        if let m = take(await mag, .mag) { snap.mag = m.samples; snap.magSource = m.source }
        if let w = take(await wind, .wind) { snap.plasma = w.samples; snap.plasmaSource = w.source }
        snap.propagated = take(await propagated, .propagated) ?? []
        snap.kpObserved = take(await kp, .kp) ?? previous?.kpObserved ?? []
        snap.kpForecast = take(await kpForecast, .kpForecast) ?? previous?.kpForecast ?? []
        snap.kp1m = take(await kp1m, .kp1m) ?? []
        snap.hemiPower = take(await hemi, .hemiPower) ?? []
        snap.goesPrimary = take(await goes1, .goesPrimary) ?? []
        snap.goesSecondary = take(await goes2, .goesSecondary) ?? []
        snap.xray = take(await xray, .xray) ?? []
        snap.latestFlare = take(await flare, .flare) ?? nil
        snap.alerts = take(await alerts, .alerts) ?? previous?.alerts ?? []
        snap.scales = take(await scales, .scales) ?? previous?.scales
        snap.ovation = take(await ovation, .ovation) ?? nil
        if let text = take(await threeDay, .threeDay) {
            snap.threeDayForecast = FeedParser.textProduct(text)
        } else {
            snap.threeDayForecast = previous?.threeDayForecast
        }
        if let text = take(await geomag, .geomag) {
            snap.geomagForecast = FeedParser.textProduct(text)
            snap.geomagProbabilities = FeedParser.geomagProbabilities(text)
        } else {
            snap.geomagForecast = previous?.geomagForecast
            snap.geomagProbabilities = previous?.geomagProbabilities
        }
        if let text = take(await outlook, .outlook27), !text.isEmpty {
            snap.outlook27Raw = text
            snap.outlook27 = FeedParser.outlook27(text)
            snap.outlookFetchedAt = reuseOutlook ? previous?.outlookFetchedAt : now
        } else {
            snap.outlook27Raw = previous?.outlook27Raw
            snap.outlook27 = previous?.outlook27 ?? []
            snap.outlookFetchedAt = previous?.outlookFetchedAt
        }
        if let arrivals = take(await cme, .enlil) {
            snap.cmeArrivals = arrivals
            snap.cmeFetchedAt = reuseCME ? previous?.cmeFetchedAt : now
        } else {
            snap.cmeArrivals = previous?.cmeArrivals ?? []
            snap.cmeFetchedAt = previous?.cmeFetchedAt
        }
        if let c = take(await clouds, .clouds) {
            snap.clouds = c
            snap.cloudsFetchedAt = reuseClouds ? previous?.cloudsFetchedAt : now
        } else {
            snap.clouds = previous?.clouds ?? []
            snap.cloudsFetchedAt = previous?.cloudsFetchedAt
        }
        return snap
    }

    /// WSA-ENLIL runs from NASA DONKI over the past 10 days that predict an Earth arrival.
    public func fetchCMEArrivals(now: Date) async throws -> [CMEArrival] {
        let tz = TimeZone(identifier: "UTC")!
        let start = TimeText.format(now.addingTimeInterval(-10 * 86400), tz, "yyyy-MM-dd")
        let end = TimeText.format(now.addingTimeInterval(86400), tz, "yyyy-MM-dd")
        let primary = URL(string: "https://kauai.ccmc.gsfc.nasa.gov/DONKI/WS/get/WSAEnlilSimulations?startDate=\(start)&endDate=\(end)")!
        do {
            return try FeedParser.enlilArrivals(try await data(primary))
        } catch {
            let key = nasaAPIKey?.isEmpty == false ? nasaAPIKey! : "DEMO_KEY"
            let fallback = URL(string: "https://api.nasa.gov/DONKI/WSAEnlilSimulations?startDate=\(start)&endDate=\(end)&api_key=\(key)")!
            return try FeedParser.enlilArrivals(try await data(fallback))
        }
    }

    public func fetchClouds(location: ObserverLocation) async throws -> [CloudPoint] {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", location.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", location.longitude)),
            .init(name: "hourly", value: "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high"),
            .init(name: "timezone", value: "GMT"),
            .init(name: "forecast_days", value: "5"),
        ]
        return try FeedParser.clouds(try await data(c.url!))
    }

    func attempt<T>(_ body: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "Offline"
            case .timedOut: return "Timed out"
            default: break
            }
        }
        return (error as NSError).localizedDescription
    }
}

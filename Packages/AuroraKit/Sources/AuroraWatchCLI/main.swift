import AuroraKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// aurora-watch: runs the same alert engine as the iOS app and pushes alerts through ntfy.
//
//   aurora-watch [--state state.json] [--settings settings.json] [--dry-run] [--quick] [--test]
//
// Environment:
//   NTFY_TOPIC   topic to publish to (required unless --dry-run)
//   NTFY_SERVER  defaults to https://ntfy.sh
//   NTFY_TOKEN   optional access token for protected topics
//   NASA_API_KEY optional, used only if the keyless DONKI endpoint is down

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let env = ProcessInfo.processInfo.environment
let dryRun = CommandLine.arguments.contains("--dry-run")
let statePath = argument("--state") ?? "watcher-state/state.json"
let settingsPath = argument("--settings")

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .secondsSince1970
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .secondsSince1970
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

var settings = AlertSettings()
if let path = settingsPath, let data = FileManager.default.contents(atPath: path) {
    do {
        settings = try decoder.decode(AlertSettings.self, from: data)
    } catch {
        print("⚠️ Could not read \(path): \(error). Using defaults.")
    }
}

struct WatcherState: Codable {
    var alerts = AlertState()
    var snapshot: SpaceWeatherSnapshot?

    init() {}

    /// Read each part separately: an unreadable snapshot must never cost us the record of
    /// which alerts were already sent (that would re-send them).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alerts = (try? c.decodeIfPresent(AlertState.self, forKey: .alerts)) ?? AlertState()
        snapshot = try? c.decodeIfPresent(SpaceWeatherSnapshot.self, forKey: .snapshot)
    }
}

var stored = WatcherState()
if let data = FileManager.default.contents(atPath: statePath), let s = try? decoder.decode(WatcherState.self, from: data) {
    stored = s
}

func publish(_ alert: AuroraAlert) async throws {
    guard let topic = env["NTFY_TOPIC"], !topic.isEmpty else { throw URLError(.userAuthenticationRequired) }
    let server = env["NTFY_SERVER"].flatMap { $0.isEmpty ? nil : $0 } ?? "https://ntfy.sh"
    var request = URLRequest(url: URL(string: server)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = env["NTFY_TOKEN"], !token.isEmpty {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let payload: [String: Any] = [
        "topic": topic,
        "title": alert.title,
        "message": alert.body,
        "priority": alert.priority,
        "tags": alert.tags,
        "click": "https://www.swpc.noaa.gov/products/aurora-30-minute-forecast",
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (_, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { c in
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { c.resume(throwing: error) } else { c.resume(returning: (data ?? Data(), response!)) }
        }.resume()
    }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "ntfy returned HTTP \(http.statusCode)"])
    }
}

var exitCode: Int32 = 0

do {
    // --quick uses the same small, fast refresh the iOS app does in the background.
    let quick = CommandLine.arguments.contains("--quick")
    let client = SpaceWeatherClient(nasaAPIKey: env["NASA_API_KEY"], quick: quick)
    let now = Date()
    let snapshot = quick
        ? await client.fetchAlertSnapshot(location: settings.location, previous: stored.snapshot, now: now)
        : await client.fetchSnapshot(location: settings.location, previous: stored.snapshot, now: now, includeHistory: false)
    for (feed, error) in snapshot.errors.sorted(by: { $0.key < $1.key }) {
        print("feed \(feed): \(error)")
    }

    let nowcast = Outlook.nowcast(snapshot: snapshot, location: settings.location, goesThreshold: settings.goesJump,
                                  groundThreshold: settings.groundChange, now: now)
    if let g = snapshot.groundReading(now: now) {
        print("Ground \(g.station.id): \(snapshot.groundMag.count) min, latest \(Int(now.timeIntervalSince(g.time) / 60)) min ago, deviation \(String(format: "%+.0f", g.deviation)) nT, 1-h range \(Int(g.range60)) nT, \(g.level.title)"
              + (g.surge.map { ", biggest 15-min change \(String(format: "%+.0f", $0.change)) nT" } ?? ""))
    } else if let station = snapshot.groundStation {
        print("Ground \(station.id): \(snapshot.groundMag.count) min (not enough for a reading yet)")
    }
    print("Nowcast: \(nowcast.level.title) score=\(nowcast.score) kp=\(nowcast.estimatedKp.map { String(format: "%.2f", $0) } ?? "-") bz=\(nowcast.bz.map { String(format: "%.1f", $0) } ?? "-") sun=\(String(format: "%.1f", nowcast.sunAltitude))°")
    for night in Outlook.nights(snapshot: snapshot, location: settings.location, now: now) {
        print("Night +\(night.daysAhead): max Kp \(KpFormat.label(night.maxKp)) [\(night.source.rawValue)] \(night.visibility.short)")
    }

    var alerts = AlertEngine.evaluate(snapshot: snapshot, settings: settings, state: &stored.alerts, now: now)
    if CommandLine.arguments.contains("--test") {
        var body = "Push alerts from GitHub are working."
        body += " Right now: \(nowcast.level.title), aurora chance \(nowcast.score)/100"
        if let kp = nowcast.estimatedKp { body += ", Kp \(String(format: "%.1f", kp))" }
        body += "."
        alerts.insert(AuroraAlert(id: "test-\(Int(now.timeIntervalSince1970))", date: now, kind: .test,
                                  title: "🌌 Aurora Watch test", body: body, priority: 3, tags: ["white_check_mark"]), at: 0)
    }
    if alerts.isEmpty { print("No new alerts.") }
    for alert in alerts {
        print("→ \(alert.title)\n  \(alert.body.replacingOccurrences(of: "\n", with: "\n  "))")
        guard !dryRun else { continue }
        do {
            try await publish(alert)
        } catch {
            print("  ⚠️ publish failed: \(error)")
            exitCode = 1
        }
    }

    // Keep only the slow-changing feeds between runs; live data is always refetched.
    var keep = SpaceWeatherSnapshot(fetchedAt: snapshot.fetchedAt)
    keep.cmeArrivals = snapshot.cmeArrivals
    keep.cmeFetchedAt = snapshot.cmeFetchedAt
    keep.cmeTriedAt = snapshot.cmeTriedAt
    keep.cmeError = snapshot.cmeError
    keep.location = snapshot.location
    keep.clouds = snapshot.clouds
    keep.cloudsFetchedAt = snapshot.cloudsFetchedAt
    keep.outlook27Raw = snapshot.outlook27Raw
    keep.outlook27 = snapshot.outlook27
    keep.outlookFetchedAt = snapshot.outlookFetchedAt
    // The ground magnetometer's last day, so each run only downloads the newest minutes and the
    // "normal level" has a full day behind it.
    keep.groundStation = snapshot.groundStation
    keep.groundMag = snapshot.groundMag.filter { now.timeIntervalSince($0.time) <= 26 * 3600 }
    stored.snapshot = keep

    do {
        let url = URL(fileURLWithPath: statePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(stored).write(to: url)
    } catch {
        print("⚠️ could not save state: \(error)")
        exitCode = 1
    }
}

exit(exitCode)

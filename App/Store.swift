import AuroraKit
import Foundation

/// Settings, alert history and the last snapshot, persisted on device.
final class Store {
    static let shared = Store()

    private let defaults = UserDefaults.standard
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
    private let lock = NSLock()

    private var snapshotURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("snapshot.json")
    }

    var settings: AlertSettings {
        get { load("settings.v1") ?? AlertSettings() }
        set { save(newValue, "settings.v1") }
    }

    var alertState: AlertState {
        get { load("alertState.v1") ?? AlertState() }
        set { save(newValue, "alertState.v1") }
    }

    var nasaAPIKey: String {
        get { defaults.string(forKey: "nasaAPIKey") ?? "" }
        set { defaults.set(newValue, forKey: "nasaAPIKey") }
    }

    /// Small rolling log of background activity, shown in Settings → Diagnostics.
    var activityLog: [String] {
        defaults.stringArray(forKey: "activityLog") ?? []
    }

    func log(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        var entries = defaults.stringArray(forKey: "activityLog") ?? []
        entries.append("\(stamp) — \(message)")
        defaults.set(Array(entries.suffix(60)), forKey: "activityLog")
        // Also keep a plain-text copy (read by the UI smoke test; handy for debugging).
        if let line = "\(stamp) — \(message)\n".data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(line)
                try? handle.close()
            } else {
                try? line.write(to: logURL)
            }
        }
    }

    private var logURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("activity.log")
    }

    /// Last successful check of any kind (foreground, background, Night Watch, Shortcut).
    var lastCheck: Date? {
        get { defaults.object(forKey: "lastCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastCheck") }
    }

    var nightWatchEnabled: Bool {
        get { defaults.bool(forKey: "nightWatchEnabled") }
        set { defaults.set(newValue, forKey: "nightWatchEnabled") }
    }

    var lastBackgroundRun: Date? {
        get { defaults.object(forKey: "lastBackgroundRun") as? Date }
        set { defaults.set(newValue, forKey: "lastBackgroundRun") }
    }

    func loadSnapshot() -> SpaceWeatherSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? decoder.decode(SpaceWeatherSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: SpaceWeatherSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }
}

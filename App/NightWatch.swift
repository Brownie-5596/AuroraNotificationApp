import AVFoundation
import AuroraKit
import Foundation

/// Keeps the app alive in the background so it can check conditions every few minutes.
///
/// iOS normally suspends apps seconds after you leave them and only wakes sideloaded apps for a
/// background refresh when it feels like it (often hours apart). While Night Watch is on, the app
/// plays silent audio — mixed with anything else you're listening to — which lets it keep running,
/// so the real-time "heads up" alerts arrive within minutes. It costs extra battery.
/// It stops if you swipe the app away, restart the phone, or iOS needs the memory; opening the
/// app starts it again.
@MainActor
final class NightWatch: ObservableObject {
    static let shared = NightWatch()

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// Minutes between checks while it's dark, and during the day.
    static let nightInterval: TimeInterval = 3 * 60
    static let dayInterval: TimeInterval = 20 * 60

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            // A phone call or another app took over audio; resume when it's done.
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in self?.resumeAudio() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.player = nil
                self?.resumeAudio()
            }
        })
    }

    var enabled: Bool { Store.shared.nightWatchEnabled }

    /// Starts if enabled and not already running. Safe to call repeatedly.
    func startIfEnabled() {
        guard enabled, !isRunning else { return }
        start()
    }

    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.silentWAV())
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            guard player.play() else { throw NSError(domain: "NightWatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio didn't start"]) }
            self.player = player
        } catch {
            lastError = error.localizedDescription
            Store.shared.log("Night Watch couldn't start: \(error.localizedDescription)")
            return
        }
        lastError = nil
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in NightWatch.shared.tick() }
        }
        Store.shared.log("Night Watch started")
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if isRunning { Store.shared.log("Night Watch stopped") }
        isRunning = false
    }

    /// Current check interval: every few minutes after dark, every 20 minutes in daylight.
    var interval: TimeInterval {
        // `-nightWatchInterval 60` launch argument, used by the UI smoke test.
        let override = UserDefaults.standard.double(forKey: "nightWatchInterval")
        if override > 0 { return override }
        let location = Store.shared.settings.location
        let dark = Sky.sunAltitude(at: Date(), for: location) < -6
        return dark ? Self.nightInterval : Self.dayInterval
    }

    private func tick() {
        guard isRunning else { return }
        if player?.isPlaying != true { resumeAudio() }
        let last = Store.shared.lastCheck ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval - 5 else { return }
        Task { await AlertRunner.run(reason: "night watch", quick: true) }
    }

    private func resumeAudio() {
        guard isRunning || enabled else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if player == nil {
                let p = try AVAudioPlayer(data: Self.silentWAV())
                p.numberOfLoops = -1
                p.volume = 0
                player = p
            }
            player?.play()
        } catch {
            Store.shared.log("Night Watch audio resume failed: \(error.localizedDescription)")
        }
    }

    /// One second of 8 kHz mono 16-bit silence as a WAV file.
    static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let samples = Data(count: Int(sampleRate) * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))          // fmt chunk size
        append(UInt16(1))           // PCM
        append(UInt16(1))           // mono
        append(sampleRate)
        append(sampleRate * 2)      // byte rate
        append(UInt16(2))           // block align
        append(UInt16(16))          // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples.count))
        data.append(samples)
        return data
    }
}

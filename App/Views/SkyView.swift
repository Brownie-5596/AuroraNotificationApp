import AuroraKit
import Combine
import SwiftUI

/// OVATION aurora map, WSA-ENLIL solar wind model and live Sun / coronagraph imagery.
struct SkyView: View {
    @EnvironmentObject var model: AppModel

    private let swpc = SpaceWeatherClient.swpc

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AnimationCard(
                        title: "OVATION aurora forecast (30–90 min)",
                        icon: "globe.americas.fill",
                        listURL: URL(string: swpc + "/products/animations/ovation_north_24h.json")!,
                        latestURL: URL(string: swpc + "/images/animations/ovation/north/latest.jpg")!,
                        caption: "Green → red = increasing probability of aurora. Grand Forks is at the bottom-centre edge of the map; aurora reaching the northern US means it's worth looking."
                    )
                    AnimationCard(
                        title: "WSA-ENLIL solar wind prediction",
                        icon: "tornado",
                        listURL: URL(string: swpc + "/products/animations/enlil.json")!,
                        latestURL: nil,
                        caption: "Model of the solar wind out to Earth over the next few days. CMEs show up as bright plumes; Earth is the green dot to the right of the Sun."
                    )
                    ImageCard(title: "Sun — SUVI 195 Å (corona)", url: URL(string: swpc + "/images/animations/suvi/primary/195/latest.png")!,
                              caption: "Dark patches are coronal holes, the source of fast solar wind streams.")
                    ImageCard(title: "Sun — SUVI 304 Å", url: URL(string: swpc + "/images/animations/suvi/primary/304/latest.png")!,
                              caption: "Shows filaments and prominences that can erupt as CMEs.")
                    AnimationCard(
                        title: "LASCO C3 coronagraph",
                        icon: "circle.dashed",
                        listURL: URL(string: swpc + "/products/animations/lasco-c3.json")!,
                        latestURL: URL(string: swpc + "/images/animations/lasco-c3/latest.jpg")!,
                        caption: "Blocks the Sun to reveal CMEs. A bright ring all around the disk (a \"halo\") means it's heading toward or away from Earth."
                    )
                    ImageCard(title: "LASCO C2 coronagraph", url: URL(string: swpc + "/images/animations/lasco-c2/latest.jpg")!, caption: nil)
                    ImageCard(title: "CCOR-1 coronagraph (GOES-19)", url: URL(string: swpc + "/images/animations/ccor1/latest.jpg")!, caption: nil)
                    ImageCard(title: "SWPC space weather overview", url: URL(string: swpc + "/images/swx-overview-large.gif")!, caption: nil)
                    linksCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Sky & Sun")
            .screenBackground()
        }
    }

    var linksCard: some View {
        Card(title: "More", systemImage: "link") {
            link("SWPC aurora dashboard", "https://www.swpc.noaa.gov/communities/aurora-dashboard-experimental")
            link("Pettus Plots space weather", "https://pettusplots.com/spaceweather")
            link("NASA DONKI (CME catalog)", "https://kauai.ccmc.gsfc.nasa.gov/DONKI/")
            link("SpaceWeatherLive", "https://www.spaceweatherlive.com/en/auroral-activity.html")
        }
    }

    func link(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: "arrow.up.right.square")
        }
        .font(.subheadline)
    }
}

struct ImageCard: View {
    var title: String
    var url: URL
    var caption: String?
    @State private var reload = UUID()
    @State private var fullscreen = false

    var body: some View {
        Card(title: title, systemImage: "photo") {
            RemoteImage(url: url, id: reload)
                .onTapGesture { fullscreen = true }
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
        .onAppear { reload = UUID() }
        .fullScreenCover(isPresented: $fullscreen) { ZoomImage(url: url) }
    }
}

struct RemoteImage: View {
    var url: URL
    var id: UUID

    var body: some View {
        AsyncImage(url: url.appendingCacheBuster(id)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
            case .failure:
                Label("Image unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            default:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .id(id)
    }
}

struct ZoomImage: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture().onChanged { scale = max(1, $0) })
            } placeholder: { ProgressView() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.8))
            }
            .padding()
        }
    }
}

/// Plays a SWPC image-sequence product (list of frame URLs) with a scrubber.
struct AnimationCard: View {
    var title: String
    var icon: String
    var listURL: URL
    var latestURL: URL?
    var caption: String

    @State private var frames: [URL] = []
    @State private var frameTimes: [URL: Date] = [:]
    @State private var index: Double = 0
    @State private var playing = false
    @State private var images: [URL: UIImage] = [:]
    @State private var loadingFrames = false
    @State private var latestID = UUID()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Card(title: title, systemImage: icon) {
            Group {
                if let url = currentURL, let image = images[url] {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                } else if let latestURL, frames.isEmpty || !playing {
                    RemoteImage(url: latestURL, id: latestID)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            if frames.count > 1 {
                HStack {
                    Button {
                        playing.toggle()
                        if playing { Task { await preload() } }
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                    }
                    Slider(value: $index, in: 0...Double(frames.count - 1), step: 1, onEditingChanged: { editing in
                        if editing { playing = false }
                    })
                    .onChange(of: index) { _ in Task { await load(currentURL) } }
                    Text(frameLabel).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .task { await loadFrames() }
        .onReceive(timer) { _ in
            guard playing, frames.count > 1 else { return }
            var next = index + 1
            if next >= Double(frames.count) { next = 0 }
            if let url = frames[safe: Int(next)], images[url] != nil { index = next }
        }
    }

    var currentURL: URL? { frames[safe: Int(index)] }

    var frameLabel: String {
        guard let url = currentURL else { return "" }
        if let date = frameTimes[url] {
            return TimeText.format(date, AppModel.shared.location.timeZone, "MMM d h:mm a")
        }
        return "\(Int(index) + 1)/\(frames.count)"
    }

    /// Frame time from the product's `time_tag`, or from a `..._20261017T000000.jpg` style file name.
    static func frameTime(_ entry: [String: Any], url: URL) -> Date? {
        if let tag = entry["time_tag"] as? String, let d = SWDate.parse(tag) { return d }
        let stem = url.deletingPathExtension().lastPathComponent
        // "20261018_0342_c3_512"
        let parts = stem.split(separator: "_")
        if parts.count >= 2, parts[0].count == 8, parts[1].count == 4,
           let ymd = Int(parts[0]), let hm = Int(parts[1]) {
            return SWDate.utc(year: ymd / 10000, month: ymd / 100 % 100, day: ymd % 100, hour: hm / 100, minute: hm % 100)
        }
        guard let token = stem.split(separator: "_").last(where: { $0.count == 15 && $0.contains("T") }) else { return nil }
        let digits = token.replacingOccurrences(of: "T", with: "")
        guard digits.count == 14, digits.allSatisfy(\.isNumber) else { return nil }
        let chars = Array(digits)
        func n(_ a: Int, _ b: Int) -> Int { Int(String(chars[a..<b])) ?? 0 }
        return SWDate.utc(year: n(0, 4), month: n(4, 6), day: n(6, 8), hour: n(8, 10), minute: n(10, 12))
    }

    func loadFrames() async {
        guard frames.isEmpty, !loadingFrames else { return }
        loadingFrames = true
        defer { loadingFrames = false }
        guard let (data, _) = try? await URLSession.shared.data(from: listURL),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        var times: [URL: Date] = [:]
        let urls = list.compactMap { entry -> URL? in
            guard let path = entry["url"] as? String, let url = URL(string: SpaceWeatherClient.swpc + path) else { return nil }
            times[url] = Self.frameTime(entry, url: url)
            return url
        }
        frameTimes = times
        // Keep the animation light: at most ~100 frames.
        let step = max(1, urls.count / 100)
        frames = stride(from: 0, to: urls.count, by: step).map { urls[$0] }
        if let last = urls.last, frames.last != last { frames.append(last) }
        index = Double(max(frames.count - 1, 0))
        if latestURL == nil { await load(currentURL) }
    }

    func preload() async {
        for url in frames where images[url] == nil {
            if !playing { break }
            await load(url)
        }
    }

    func load(_ url: URL?) async {
        guard let url, images[url] == nil,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        images[url] = image
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension URL {
    func appendingCacheBuster(_ id: UUID) -> URL {
        var c = URLComponents(url: self, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "t", value: String(id.uuidString.prefix(8)))]
        return c?.url ?? self
    }
}

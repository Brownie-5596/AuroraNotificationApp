import AuroraKit
import SwiftUI

/// Plain-language explanation of one chart or number in the app.
struct ChartInfo: Identifiable, Hashable {
    struct Level: Hashable {
        enum Tone: Hashable { case quiet, some, good, great }
        var range: String
        var meaning: String
        var tone: Tone
    }

    var id: String
    var title: String
    var icon: String
    /// One line, shown under the chart.
    var summary: String
    /// What it measures.
    var what: String
    /// How to read it and what to look for.
    var read: String
    var levels: [Level] = []
    var source: String

    static func == (a: ChartInfo, b: ChartInfo) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ChartInfo {
    static let bz = ChartInfo(
        id: "bz", title: "Bz (north–south field)", icon: "arrow.down.to.line",
        summary: "Negative (south, red) Bz lets the solar wind's energy in — the single most important number for aurora.",
        what: "The north–south direction of the magnetic field carried by the solar wind, in nanotesla (nT), measured by spacecraft at L1 about 1.5 million km toward the Sun. \"GSM\" means it's measured relative to Earth's own magnetic field.",
        read: """
        Earth's field points north. When the solar wind's field points **south** (negative Bz, shaded red), the two connect and energy pours into Earth's magnetosphere — that's what lights up the aurora. Northward (green) mostly keeps the door closed.
        What matters is **how far south and for how long**. A brief dip does little; −10 nT held for 30+ minutes is a good sign. The white lines are Bt (and −Bt): Bz can never go beyond them, so a high Bt means Bz *could* swing strongly south. The dashed red line is your alert threshold.
        """,
        levels: [
            .init(range: "Above 0", meaning: "Northward — the door is mostly closed", tone: .quiet),
            .init(range: "0 to −5 nT", meaning: "Weak. Minor activity far north", tone: .some),
            .init(range: "−5 to −10 nT", meaning: "If it lasts 20+ min, aurora is possible on the northern horizon", tone: .good),
            .init(range: "−10 to −20 nT", meaning: "Strong — storm-level if it holds", tone: .great),
            .init(range: "Below −20 nT", meaning: "Major storm territory", tone: .great),
        ],
        source: "NOAA SWPC real-time solar wind (DSCOVR / ACE / SWFO-L1 at L1), 1-minute data."
    )

    static let bt = ChartInfo(
        id: "bt", title: "Bt (total field)", icon: "circle.dashed",
        summary: "Total strength of the solar wind's magnetic field — the most Bz could swing to.",
        what: "The overall strength of the interplanetary magnetic field (all three directions combined), in nT.",
        read: "Bt doesn't make aurora by itself, but it sets the ceiling: Bz can never be more negative than −Bt. When Bt is high (CMEs and fast streams), keep an eye on Bz — if it turns south, it can go strongly south.",
        levels: [
            .init(range: "Under 5 nT", meaning: "Quiet, normal solar wind", tone: .quiet),
            .init(range: "5–10 nT", meaning: "Elevated", tone: .some),
            .init(range: "10–20 nT", meaning: "Strong — typical of CMEs and stream fronts", tone: .good),
            .init(range: "Over 20 nT", meaning: "Very strong, usually a CME", tone: .great),
        ],
        source: "NOAA SWPC real-time solar wind at L1."
    )

    static let bxby = ChartInfo(
        id: "bxby", title: "Bx and By", icon: "arrow.left.and.right",
        summary: "The other two directions of the solar wind's field — much less important than Bz.",
        what: "Bx points along the Sun–Earth line and By points east–west (dawn–dusk), in nT.",
        read: "These matter far less than Bz for whether you'll see aurora. By can shift where on the oval the aurora is strongest. A sudden flip of Bx and By together often marks a boundary in the solar wind — the edge of a CME or a sector boundary — which can be followed by changes in Bz.",
        source: "NOAA SWPC real-time solar wind at L1."
    )

    static let speed = ChartInfo(
        id: "speed", title: "Solar wind speed", icon: "wind",
        summary: "How fast the solar wind is moving. Faster wind makes a southward Bz hit harder.",
        what: "The speed of the solar wind's protons, in km/s.",
        read: """
        Speed multiplies the effect of Bz: −10 nT at 700 km/s drives about twice as much as at 350 km/s. A **sudden jump** of 50–100+ km/s (with density and Bt jumping too) is a shock — usually the front of a CME — and the app sends a heads-up.
        Speed also sets how long L1 data takes to reach Earth: about 60 minutes at 400 km/s, 35 minutes at 700 km/s.
        """,
        levels: [
            .init(range: "300–400 km/s", meaning: "Normal, slow wind", tone: .quiet),
            .init(range: "400–500 km/s", meaning: "Slightly elevated", tone: .some),
            .init(range: "500–700 km/s", meaning: "Fast — coronal hole stream or CME", tone: .good),
            .init(range: "Over 700 km/s", meaning: "Very fast — big storms possible if Bz is south", tone: .great),
        ],
        source: "NOAA SWPC real-time solar wind at L1."
    )

    static let density = ChartInfo(
        id: "density", title: "Density", icon: "circle.grid.3x3.fill",
        summary: "How many particles are in the solar wind. A sudden jump often means a shock or CME arriving.",
        what: "Number of protons per cubic centimetre of solar wind (p/cm³).",
        read: "Density alone doesn't cause aurora, but more particles mean more pressure on Earth's magnetic field. A sudden jump together with speed is the classic sign of a shock. Dense, compressed plasma often sits just ahead of a fast stream or CME — and that region frequently carries strong Bz.",
        levels: [
            .init(range: "1–5 p/cm³", meaning: "Normal", tone: .quiet),
            .init(range: "5–15 p/cm³", meaning: "Elevated — compressed region ahead of a stream or CME", tone: .some),
            .init(range: "Over 20 p/cm³", meaning: "High — often a shock or CME front", tone: .good),
        ],
        source: "NOAA SWPC real-time solar wind at L1."
    )

    static let temperature = ChartInfo(
        id: "temperature", title: "Temperature", icon: "thermometer.medium",
        summary: "Solar wind temperature — a supporting clue for what kind of wind is arriving.",
        what: "Temperature of the solar wind protons, in kelvin (K).",
        read: "Fast coronal-hole streams are hot (often over 200,000 K). CMEs are often unusually cool for their speed. A jump in temperature together with speed and density is another sign of a shock. You can mostly ignore this one — it helps explain the others.",
        source: "NOAA SWPC real-time solar wind at L1."
    )

    static let ey = ChartInfo(
        id: "ey", title: "Ey — solar wind coupling", icon: "bolt.fill",
        summary: "Speed × southward Bz in one number: how hard the solar wind is driving Earth right now.",
        what: "The dawn–dusk electric field, Ey = speed × southward Bz, in millivolts per metre (mV/m). It's zero whenever Bz is north.",
        read: "This combines the two most important things — how far south Bz is and how fast the wind is — so it's a good single gauge of energy input. Sustained values above about 3 mV/m usually trigger substorms, when the aurora suddenly brightens and dances.",
        levels: [
            .init(range: "0", meaning: "Bz north — no driving", tone: .quiet),
            .init(range: "1–3 mV/m", meaning: "Some energy getting in", tone: .some),
            .init(range: "3–6 mV/m", meaning: "Substorms likely — aurora can brighten quickly", tone: .good),
            .init(range: "Over 6 mV/m", meaning: "Storm-level driving", tone: .great),
        ],
        source: "Calculated by the app from NOAA real-time solar wind."
    )

    static func kp(_ location: ObserverLocation) -> ChartInfo {
        let t = location.visibility
        return ChartInfo(
            id: "kp", title: "Kp index", icon: "chart.bar.fill",
            summary: "Global geomagnetic activity on a 0–9 scale. Higher Kp pushes the aurora further south.",
            what: "The planetary K-index: how disturbed Earth's magnetic field has been over a 3-hour block, measured by magnetometers around the world. Each bar is one 3-hour block; solid bars are observed, faded bars are NOAA's forecast, and the white line is now.",
            read: """
            NOAA writes Kp in thirds: 5- = 4.67, 5 = 5.00, 5+ = 5.33. Kp 5- and up is a G1 storm.
            For \(location.name) (geomagnetic latitude \(Int(location.geomagneticLatitude.rounded()))°), the dashed lines show the Kp needed to see aurora on the northern horizon (≈\(t.horizon.f(1))) and overhead (≈\(t.overhead.f(1))). Kp is a 3-hour average, so the real-time numbers (Bz, Ey, hemispheric power) tell you more about the next hour.
            """,
            levels: [
                .init(range: "Kp 0–\(t.camera.f(1))", meaning: "Not visible from \(location.name)", tone: .quiet),
                .init(range: "Kp \(t.camera.f(1))–\(t.horizon.f(1))", meaning: "Maybe on a phone/camera, low in the north", tone: .some),
                .init(range: "Kp \(t.horizon.f(1))–\(t.overhead.f(1))", meaning: "Usually visible by eye on the northern horizon", tone: .good),
                .init(range: "Kp \(t.overhead.f(1))+", meaning: "Can be overhead — look in every direction", tone: .great),
            ],
            source: "NOAA SWPC observed and forecast planetary Kp."
        )
    }

    static let kp1m = ChartInfo(
        id: "kp1m", title: "Estimated Kp (1-minute)", icon: "speedometer",
        summary: "A real-time estimate of Kp, updated every minute.",
        what: "NOAA's running estimate of the current 3-hour Kp, updated every minute.",
        read: "Use this to see whether activity is building right now. It restarts from 0 at the start of every 3-hour block (7 PM, 10 PM, 1 AM… in Grand Forks during daylight time), so a sudden drop to 0 at those times isn't real — the app uses the highest value of the last 45 minutes.",
        source: "NOAA SWPC planetary K-index (1-minute)."
    )

    static let hemiPower = ChartInfo(
        id: "hemiPower", title: "Hemispheric power", icon: "sparkles",
        summary: "Estimated energy going into the northern aurora. 50+ GW is active, 100+ GW is a good show.",
        what: "NOAA's OVATION model estimate of the total power deposited into the aurora over the northern hemisphere, in gigawatts (GW), about 30 minutes ahead.",
        read: "This is one of the best real-time indicators of how bright and widespread the aurora is. When it climbs past 50 GW the aurora often reaches southern Canada and the northern US.",
        levels: [
            .init(range: "Under 20 GW", meaning: "Quiet", tone: .quiet),
            .init(range: "20–50 GW", meaning: "Some activity, mostly far north", tone: .some),
            .init(range: "50–100 GW", meaning: "Active — worth looking north", tone: .good),
            .init(range: "Over 100 GW", meaning: "Strong; over 200 GW is a major storm", tone: .great),
        ],
        source: "NOAA SWPC OVATION aurora nowcast."
    )

    static let goes = ChartInfo(
        id: "goes", title: "GOES magnetometers", icon: "dot.radiowaves.left.and.right",
        summary: "Earth's magnetic field measured by weather satellites — shows shocks and substorms as they happen.",
        what: "The Hp (north–south) part of Earth's magnetic field measured by two GOES satellites in geostationary orbit, about 36,000 km up, in nT.",
        read: "There's a normal daily wave (higher around local noon). A **sudden jump up** means a shock just compressed Earth's field — usually 30–60 min after a shock is seen at L1. On the night side, a **sharp dip followed by a recovery** is the signature of a substorm, which often matches the aurora suddenly brightening.",
        source: "NOAA GOES-East and GOES-West magnetometers."
    )

    static let xray = ChartInfo(
        id: "xray", title: "Solar X-ray flux", icon: "sun.max.fill",
        summary: "Solar flares. Big ones can launch CMEs that reach Earth 1–3 days later.",
        what: "X-rays from the Sun measured by GOES. Flares are classed A, B, C, M and X, each 10× stronger than the last (M2.4 = 2.4 × M1).",
        read: "Flares themselves don't cause aurora. But big flares (M5 and especially X-class) often come with a coronal mass ejection; if it's aimed at Earth, it typically arrives in 1–3 days and can bring a geomagnetic storm. Watch for a CME prediction after a big flare.",
        levels: [
            .init(range: "A, B", meaning: "Quiet Sun", tone: .quiet),
            .init(range: "C", meaning: "Small flares — common", tone: .quiet),
            .init(range: "M", meaning: "Moderate — M5+ may launch a CME", tone: .some),
            .init(range: "X", meaning: "Major — watch for a CME", tone: .good),
        ],
        source: "NOAA GOES X-ray sensors (0.1–0.8 nm)."
    )

    static let ovation = ChartInfo(
        id: "ovation", title: "OVATION aurora probability", icon: "globe.americas.fill",
        summary: "NOAA's model chance of aurora over the next 30–90 minutes, in the sky north of you.",
        what: "NOAA's OVATION model turns live solar wind data into a map of aurora probability about 30–90 minutes ahead. The app reads the highest value in the part of the sky visible from your location (about 600 km north) and the value directly overhead.",
        read: "Treat this as a rough guide. Even low percentages near you can mean aurora is visible low on the northern horizon, especially on camera.",
        levels: [
            .init(range: "Under 10%", meaning: "Unlikely", tone: .quiet),
            .init(range: "10–30%", meaning: "Possible — look north", tone: .some),
            .init(range: "30–50%", meaning: "Likely", tone: .good),
            .init(range: "Over 50%", meaning: "Strong", tone: .great),
        ],
        source: "NOAA SWPC OVATION aurora forecast."
    )

    static let pressure = ChartInfo(
        id: "pressure", title: "Dynamic pressure", icon: "arrow.down.right.and.arrow.up.left",
        summary: "How hard the solar wind is pushing on Earth's magnetic field.",
        what: "Solar wind ram pressure (density × speed²), in nanopascals (nPa).",
        read: "A sudden jump in pressure compresses Earth's field and can trigger a burst of aurora — even more so if Bz is south at the same time.",
        levels: [
            .init(range: "1–3 nPa", meaning: "Normal", tone: .quiet),
            .init(range: "3–6 nPa", meaning: "Elevated", tone: .some),
            .init(range: "Over 6 nPa", meaning: "High — often a shock or CME", tone: .good),
        ],
        source: "Calculated by the app from NOAA real-time solar wind."
    )

    static let bzStreak = ChartInfo(
        id: "bzStreak", title: "Bz streak", icon: "timer",
        summary: "How long Bz has been south, and how much southward field has piled up.",
        what: "The app tracks the current run of southward (negative) Bz, ignoring blips of 3 minutes or less.",
        read: """
        • **Southward for** — how long the current run has lasted.
        • **Lowest / Average** — how far south it has been.
        • **Total (nT·min)** — southward field added up over every minute: a measure of how much energy has gone in. A few hundred nT·min is a decent run; over 1,000 is a lot.
        • **≤ threshold for** — how long Bz has stayed past your alert line.
        • **South last 3 h** — share of the last 3 hours that Bz was south.
        Aurora usually needs Bz south for 15–30+ minutes before it builds.
        """,
        source: "Calculated by the app from NOAA real-time solar wind."
    )

    static let travelTime = ChartInfo(
        id: "travelTime", title: "Time to Earth", icon: "timer",
        summary: "How long until what the L1 spacecraft see now reaches Earth.",
        what: "The spacecraft measuring the solar wind sit at L1, about 1.5 million km toward the Sun. The wind they measure reaches Earth later — how much later depends on its speed.",
        read: "This is your short-range warning: if Bz turns strongly south at L1, the effect arrives at Earth after this delay — usually 30–60 minutes. The app uses NOAA's propagated solar wind for the exact delay when it's available.",
        source: "NOAA SWPC propagated solar wind, or distance ÷ speed."
    )

    static let score = ChartInfo(
        id: "score", title: "Aurora chance score", icon: "gauge.with.dots.needle.67percent",
        summary: "The app's 0–100 summary of how likely aurora is right now.",
        what: "A score the app builds from live data: Kp compared with what your location needs (up to 40 points), Ey coupling (25), hemispheric power (20) and OVATION probability north of you (15).",
        read: "It's a rule of thumb, not an official forecast. A high Kp or a detected shock can raise the level even if the score is lower. Darkness, clouds and the moon aren't in the score but are shown next to it — you still need a dark, clear sky.",
        levels: [
            .init(range: "0–29", meaning: "Quiet", tone: .quiet),
            .init(range: "30–49", meaning: "Possible — activity could build", tone: .some),
            .init(range: "50–74", meaning: "Likely — get somewhere dark", tone: .good),
            .init(range: "75–100", meaning: "Strong storm", tone: .great),
        ],
        source: "Calculated by the app."
    )

    static let scales = ChartInfo(
        id: "scales", title: "NOAA scales (R, S, G)", icon: "exclamationmark.triangle",
        summary: "NOAA's 0–5 ratings for space weather. G is the one that matters for aurora.",
        what: "**R** = radio blackouts from solar flares. **S** = solar radiation storms. **G** = geomagnetic storms.",
        read: "G maps to Kp: G1 = Kp 5, G2 = Kp 6, G3 = Kp 7, G4 = Kp 8, G5 = Kp 9. From Grand Forks, G1 often means aurora on the northern horizon, and G2+ can bring it overhead. R and S don't affect aurora directly, but big R events (flares) can come with CMEs.",
        levels: [
            .init(range: "G0", meaning: "No storm", tone: .quiet),
            .init(range: "G1–G2", meaning: "Minor–moderate storm", tone: .good),
            .init(range: "G3+", meaning: "Strong to extreme", tone: .great),
        ],
        source: "NOAA SWPC space weather scales."
    )

    static let geomagProbs = ChartInfo(
        id: "geomagProbs", title: "Geomagnetic probabilities", icon: "percent",
        summary: "NOAA's chance of each level of activity on each of the next 3 days.",
        what: "From NOAA's 3-day geomagnetic forecast: the probability of active conditions or storms each day (for mid-latitudes).",
        read: "Active ≈ Kp 4. Minor storm = G1 (Kp 5). Moderate = G2 (Kp 6). Strong–Extreme = G3 or higher. A minor-storm chance of 30%+ is worth watching from Grand Forks.",
        source: "NOAA SWPC 3-day geomagnetic forecast."
    )

    static let outlook27 = ChartInfo(
        id: "outlook27", title: "27-day outlook", icon: "calendar",
        summary: "NOAA's long-range guess at each day's highest Kp, based on the Sun's 27-day rotation.",
        what: "The Sun rotates about every 27 days, so active regions and coronal holes that hit us once tend to come back around. NOAA uses this to predict the largest Kp, the Ap index and the 10.7 cm radio flux (F10.7) for each of the next 27 days.",
        read: "Low confidence — CMEs can't be predicted this far ahead — but it's good for spotting likely-active periods weeks in advance.",
        source: "NOAA SWPC 27-day outlook."
    )

    static let cme = ChartInfo(
        id: "cme", title: "CMEs and arrival times", icon: "sun.max.trianglebadge.exclamationmark",
        summary: "Coronal mass ejections heading for Earth, and when they should arrive.",
        what: "A CME is a huge cloud of solar plasma and magnetic field thrown off the Sun. NASA runs the WSA-ENLIL model on each one to predict whether and when it will reach Earth.",
        read: "Arrival times are usually good to about ±7 hours. The Kp range shows NASA's estimate for different possible magnetic orientations — the real result depends on Bz when it arrives, which can only be seen at L1 about an hour before. A \"glancing blow\" means only the edge is expected to hit. The calculator estimates travel time from launch speed using a drag-based model.",
        source: "NASA CCMC DONKI (WSA-ENLIL simulations)."
    )

    struct Group: Identifiable {
        var title: String
        var items: [ChartInfo]
        var id: String { title }
    }

    static func all(for location: ObserverLocation) -> [Group] {
        [
            Group(title: "Right now", items: [.score, kp(location), .kp1m, .ovation, .hemiPower]),
            Group(title: "Solar wind", items: [.bz, .bt, .bzStreak, .ey, .speed, .density, .pressure, .temperature, .bxby, .travelTime]),
            Group(title: "Earth & Sun", items: [.goes, .xray, .scales]),
            Group(title: "Forecasts", items: [.geomagProbs, .outlook27, .cme]),
        ]
    }
}

// MARK: - Views

/// Small ⓘ button that opens the explanation in a sheet.
struct InfoButton: View {
    var info: ChartInfo
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(info.title)")
        .sheet(isPresented: $showing) { InfoSheet(info: info) }
    }
}

struct InfoSheet: View {
    var info: ChartInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { InfoContent(info: info).padding() }
                .navigationTitle(info.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .screenBackground()
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .tint(Theme.aurora)
    }
}

struct InfoContent: View {
    var info: ChartInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(info.summary).font(.headline)
            section("What it is", info.what)
            section("How to read it", info.read)
            if !info.levels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What the numbers mean").font(.subheadline.weight(.semibold))
                    ForEach(info.levels, id: \.self) { level in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(color(level.tone)).frame(width: 8, height: 8).padding(.top, 5)
                            Text(level.range).font(.subheadline.weight(.medium).monospacedDigit())
                                .frame(width: 120, alignment: .leading)
                            Text(level.meaning).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Source: \(info.source)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(LocalizedStringKey(body)).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func color(_ tone: ChartInfo.Level.Tone) -> Color {
        switch tone {
        case .quiet: return .gray
        case .some: return .yellow
        case .good: return Theme.aurora
        case .great: return Theme.violet
        }
    }
}

/// Toolbar ⓘ that opens the glossary.
struct GlossaryButton: View {
    var location: ObserverLocation
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Image(systemName: "info.circle") }
            .accessibilityLabel("What it all means")
            .sheet(isPresented: $showing) { GlossaryView(location: location) }
    }
}

/// Every explanation in one list. Opened from the ⓘ in the Now and Forecast tabs.
struct GlossaryView: View {
    var location: ObserverLocation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap any chart to open it full screen — then drag across it to read the value and time at any point. Tap ⓘ next to a chart or number for what it means.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .listRowBackground(Theme.card)
                }
                ForEach(ChartInfo.all(for: location)) { group in
                    Section(group.title) {
                        ForEach(group.items) { info in
                            NavigationLink {
                                ScrollView { InfoContent(info: info).padding() }
                                    .navigationTitle(info.title)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .screenBackground()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(info.title, systemImage: info.icon)
                                    Text(info.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
                Section {
                    NavigationLink("How aurora forecasting works") { GuideView() }
                        .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("What it all means")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .screenBackground()
        }
        .preferredColorScheme(.dark)
        .tint(Theme.aurora)
    }
}

/// A chart on the main page: not touch-interactive (so scrolling is easy), with a one-line
/// description underneath. Tapping it opens the chart full screen, where dragging reads values.
struct ExpandableChart<Content: View>: View {
    var info: ChartInfo
    /// The page's time range, or nil for charts with a fixed range.
    var range: ChartRange?
    /// Builds the chart for a range; the Bool is true in the full-screen view.
    @ViewBuilder var content: (ChartRange, Bool) -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content(range ?? .h24, false)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(info.summary).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
        .onAppear {
            // `-openChart bz` launch argument, used by the UI smoke test.
            if UserDefaults.standard.string(forKey: "openChart") == info.id { expanded = true }
        }
        .fullScreenCover(isPresented: $expanded) {
            ChartDetailView(info: info, initialRange: range, content: content)
        }
    }
}

/// Full-screen chart: drag (or tap) anywhere on it to read the value and time.
struct ChartDetailView<Content: View>: View {
    var info: ChartInfo
    var initialRange: ChartRange?
    var content: (ChartRange, Bool) -> Content
    @State private var range: ChartRange = .h6
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if initialRange != nil {
                    Picker("Range", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                content(range, true)
                Label("Drag across the chart to read the value and time", systemImage: "hand.draw")
                    .font(.caption).foregroundStyle(.secondary)
                Divider().overlay(Color.white.opacity(0.15))
                ScrollView { InfoContent(info: info).padding(.bottom, 24) }
            }
            .padding()
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .screenBackground()
            .onAppear { if let initialRange { range = initialRange } }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.aurora)
    }
}

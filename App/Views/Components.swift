import AuroraKit
import SwiftUI

enum Theme {
    static let aurora = Color(red: 0.25, green: 0.95, blue: 0.6)
    static let violet = Color(red: 0.62, green: 0.45, blue: 1.0)
    static let south = Color(red: 0.95, green: 0.3, blue: 0.3)
    static let north = Color(red: 0.25, green: 0.8, blue: 0.55)
    static let card = Color.white.opacity(0.06)
    static let background = LinearGradient(
        colors: [Color(red: 0.02, green: 0.03, blue: 0.08), Color(red: 0.03, green: 0.07, blue: 0.12)],
        startPoint: .top, endPoint: .bottom
    )

    static func kpColor(_ kp: Double) -> Color {
        switch KpFormat.gScale(kp) {
        case 0: return kp >= 4 ? .yellow : aurora
        case 1: return .orange
        case 2: return Color(red: 1, green: 0.45, blue: 0.2)
        case 3: return .red
        case 4: return Color(red: 0.85, green: 0.1, blue: 0.4)
        default: return .purple
        }
    }

    static func levelColor(_ level: ActivityLevel) -> Color {
        switch level {
        case .quiet: return .gray
        case .possible: return .yellow
        case .likely: return aurora
        case .strong: return violet
        }
    }

    static func scaleColor(_ value: Int?) -> Color {
        switch value ?? 0 {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        case 3: return .red
        default: return .purple
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var unit: String = ""
    var color: Color = .primary
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ScoreRing: View {
    var score: Int
    var level: ActivityLevel

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    AngularGradient(colors: [Theme.aurora, .teal, Theme.violet, Theme.aurora], center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Text(level.title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.levelColor(level))
            }
        }
        .frame(width: 110, height: 110)
        .animation(.easeOut, value: score)
    }
}

struct ScaleBadge: View {
    var letter: String
    var value: Int?

    var body: some View {
        Text("\(letter)\(value ?? 0)")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.scaleColor(value).opacity(0.25), in: Capsule())
            .foregroundStyle(Theme.scaleColor(value))
    }
}

struct FactorRow: View {
    var factor: OutlookFactor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.name).font(.subheadline.weight(.medium))
                Text(factor.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if factor.points > 0 {
                Text("+\(factor.points)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    var icon: String {
        switch factor.effect {
        case .positive: return "arrow.up.circle.fill"
        case .negative: return "arrow.down.circle.fill"
        case .neutral: return "minus.circle"
        }
    }

    var color: Color {
        switch factor.effect {
        case .positive: return Theme.aurora
        case .negative: return Theme.south
        case .neutral: return .secondary
        }
    }
}

extension Double {
    func f(_ digits: Int = 1) -> String { String(format: "%.\(digits)f", self) }
}

extension Optional where Wrapped == Double {
    func f(_ digits: Int = 1, placeholder: String = "--") -> String {
        map { $0.f(digits) } ?? placeholder
    }
}

extension View {
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

/// Formats dates in the observer's time zone.
struct LocalTime {
    var tz: TimeZone

    func time(_ date: Date) -> String { TimeText.time(date, tz) }
    func dayTime(_ date: Date) -> String { TimeText.dayTime(date, tz) }
    func day(_ date: Date) -> String { TimeText.day(date, tz) }
    func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        return interval >= 0 ? "in \(TimeText.duration(interval))" : "\(TimeText.duration(-interval)) ago"
    }
}

import AuroraKit
import SwiftUI

/// Tonight hour by hour: darkness, expected Kp, clouds and the Moon, with the best stretch highlighted.
struct ViewingPlanCard: View {
    var plan: ViewingPlan
    var location: ObserverLocation

    var body: some View {
        let lt = LocalTime(tz: location.timeZone)
        let maxKp = plan.hours.compactMap(\.kp).max() ?? 0
        Card(title: "Tonight hour by hour", systemImage: "clock", info: .viewingPlan) {
            if let best = plan.best {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best time: **\(lt.time(best.start)) – \(lt.time(best.end))**")
                    Text(maxKp >= location.visibility.camera
                         ? "Darkest and clearest stretch while Kp is up to \(KpFormat.label(maxKp))."
                         : "Darkest and clearest stretch — but Kp is only expected to reach \(KpFormat.label(maxKp)), so aurora is unlikely unless activity picks up.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Time"); Text("Sky"); Text("Kp"); Text("Clouds"); Text("Moon"); Text("")
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                // Hours that are already over are left out; the current hour stays.
                ForEach(plan.hours.filter { $0.start.addingTimeInterval(3600) > Date() }) { hour in
                    let inBest = plan.best.map { hour.start < $0.end && hour.start.addingTimeInterval(3600) > $0.start } ?? false
                    let twilight = Sky.Twilight(rawValue: hour.twilight) ?? .day
                    GridRow {
                        Text(lt.time(hour.start)).monospacedDigit()
                            .fontWeight(inBest ? .bold : .regular)
                            .foregroundStyle(inBest ? Theme.aurora : .primary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SkyTimeline.color(twilight))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 22, height: 12)
                        Text(hour.kp.map { KpFormat.label($0) } ?? "—")
                            .foregroundStyle(hour.kp.map(Theme.kpColor) ?? .secondary)
                        Text(hour.cloudCover.map { "\(Int($0))%" } ?? "—")
                            .foregroundStyle((hour.cloudCover ?? 0) >= 70 ? Theme.south : .primary)
                        Image(systemName: hour.moonUp ? "moon.fill" : "moon")
                            .foregroundStyle(hour.moonUp ? .yellow.opacity(0.8) : .secondary.opacity(0.4))
                        scoreBar(hour.score, highlighted: inBest)
                    }
                    .font(.caption)
                    .padding(.vertical, 1)
                }
            }
            Text("Bar = viewing quality: how dark × how clear × Moon × the Kp expected that hour. Best hours in green.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    func scoreBar(_ score: Int, highlighted: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(highlighted ? Theme.aurora : Theme.aurora.opacity(0.5))
                    .frame(width: geo.size.width * CGFloat(min(max(score, 0), 100)) / 100)
            }
        }
        .frame(height: 6)
        .frame(minWidth: 40)
    }
}

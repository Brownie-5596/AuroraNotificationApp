import AuroraKit
import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var model: AppModel
    @State private var source = 0

    var body: some View {
        NavigationStack {
            List {
                Picker("Source", selection: $source) {
                    Text("My alerts").tag(0)
                    Text("NOAA messages").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if source == 0 { myAlerts } else { noaaAlerts }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await model.refresh() }
            .navigationTitle("Alerts")
            .toolbar {
                if source == 0 && !model.history.isEmpty {
                    Button("Clear") { model.clearHistory() }
                }
            }
            .screenBackground()
        }
    }

    @ViewBuilder
    var myAlerts: some View {
        if model.history.isEmpty {
            Text("No alerts yet. When conditions match your rules you'll get a notification and it'll show up here.")
                .font(.subheadline).foregroundStyle(.secondary)
                .listRowBackground(Theme.card)
        }
        ForEach(model.history) { alert in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(LocalTime(tz: model.location.timeZone).dayTime(alert.date))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(alert.body).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.card)
        }
    }

    @ViewBuilder
    var noaaAlerts: some View {
        let alerts = Array((model.snapshot?.alerts ?? []).prefix(40))
        if alerts.isEmpty {
            Text("No recent NOAA messages.").foregroundStyle(.secondary).listRowBackground(Theme.card)
        }
        ForEach(alerts) { alert in
            NavigationLink {
                ScrollView {
                    Text(alert.message)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle(alert.kind.title)
                .screenBackground()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(alert.kind.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color(alert).opacity(0.25), in: Capsule())
                            .foregroundStyle(color(alert))
                        Spacer()
                        Text(LocalTime(tz: model.location.timeZone).dayTime(alert.issued))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(AlertEngineText.short(alert)).font(.subheadline)
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    func color(_ alert: SWPCAlert) -> Color {
        switch alert.kind {
        case .alert: return .red
        case .warning: return .orange
        case .watch: return .yellow
        case .summary: return .blue
        default: return .gray
        }
    }
}

enum AlertEngineText {
    static func short(_ alert: SWPCAlert) -> String {
        var h = alert.headline
        for prefix in ["EXTENDED WARNING:", "WARNING:", "WATCH:", "ALERT:", "SUMMARY:", "CONTINUED ALERT:"] where h.hasPrefix(prefix) {
            h = String(h.dropFirst(prefix.count))
        }
        return h.trimmingCharacters(in: .whitespaces)
    }
}

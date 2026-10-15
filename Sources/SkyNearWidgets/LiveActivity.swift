import SwiftUI
import WidgetKit
import ActivityKit
import RadarCore

struct NearbyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NearbyActivityAttributes.self) { context in
            let language = context.state.language ?? .de
            let ended = context.isStale && (context.state.validUntil.map { $0 <= Date() } ?? false)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(language.text("Nächste Flugzeuge"), systemImage: "airplane").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text(context.state.updated, style: .time).font(.system(size: 9)).monospacedDigit()
                    if context.isStale { Text(language.text(ended ? "Prognose beendet" : "Veraltet")).font(.system(size: 9)).foregroundStyle(.orange) }
                }
                HStack {
                    Text(context.state.source?.title ?? "—")
                    Text(context.state.updated, style: .relative).monospacedDigit()
                    if let status = context.state.status { Text(status).lineLimit(1) }
                    else if context.state.estimated == true { Text(language.text("Geschätzt")) }
                }.font(.system(size: 8)).foregroundStyle(context.state.estimated == true ? .orange : .white)
                if ended { Text(language.text("Keine aktuelle Position verfügbar.")).font(.caption) }
                else {
                    if context.state.rows.isEmpty { Text(language.text("Keine erfassten Flugzeuge")).font(.caption) }
                    ForEach(context.state.rows) { row in
                        HStack(alignment: .center, spacing: 5) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(row.label) · \(row.model)").font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                Text("\(row.company) · \(row.route)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                                if row.estimated == true, let time = row.positionAt {
                                    HStack(spacing: 3) {
                                        Text(language.text("Geschätzt"))
                                        Text(time, style: .time)
                                    }.font(.system(size: 8)).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 2)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(row.altitude) · \(row.speed)").font(.system(size: 9)).lineLimit(1)
                                Text(row.distance).font(.system(size: 8)).foregroundStyle(row.estimated == true ? .orange : .cyan)
                            }
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .environment(\.locale, language.locale)
            .padding(10)
            .activityBackgroundTint(Color(red: 0.035, green: 0.07, blue: 0.12))
            .activitySystemActionForegroundColor(.cyan)
            .widgetURL(URL(string: "skynear://nearby"))
        } dynamicIsland: { context in
            let language = context.state.language ?? .de
            let ended = context.isStale && (context.state.validUntil.map { $0 <= Date() } ?? false)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("SkyNear", systemImage: "airplane").font(.caption).foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(language.text(ended ? "Prognose beendet" : (context.isStale ? "Veraltet" : (context.state.estimated == true ? "Geschätzt" : "Flüge"))))
                        .font(.caption2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !ended {
                            ForEach(context.state.rows) { row in
                                HStack {
                                    Text(row.label).font(.caption2).lineLimit(1)
                                    Text(row.route).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 1)
                                    Text("\(row.altitude) · \(row.speed)").font(.system(size: 9)).lineLimit(1)
                                    if row.estimated == true { Text("~").foregroundStyle(.orange) }
                                }
                            }
                        }
                        HStack(spacing: 4) {
                            Text(context.state.source?.title ?? "—")
                            Text(language.text("Letzte echte Daten"))
                            Text(context.state.updated, style: .time)
                        }.font(.system(size: 8)).foregroundStyle(.secondary)
                    }.environment(\.locale, language.locale)
                }
            } compactLeading: {
                Text(ended ? "—" : (context.state.rows.first?.typeCode ?? "—"))
                    .font(.system(size: 10, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(context.isStale || context.state.estimated == true ? .orange : .cyan)
            } compactTrailing: {
                Text(ended ? "—" : (context.state.rows.first?.distance ?? "—")).font(.system(size: 10))
                    .foregroundStyle(context.state.estimated == true ? .orange : .white)
            } minimal: {
                Image(systemName: "airplane").foregroundStyle(context.state.estimated == true ? .orange : .cyan)
            }
            .widgetURL(URL(string: "skynear://nearby"))
            .keylineTint(context.state.estimated == true ? .orange : .cyan)
        }
    }
}

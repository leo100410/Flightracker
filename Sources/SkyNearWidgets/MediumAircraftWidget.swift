import SwiftUI
import WidgetKit
import UIKit
import RadarCore

struct MediumAircraftWidget: Widget {
    let kind = "SkyNear.NearestMedium.v1"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MediumProvider()) { entry in
            MediumAircraftView(entry: entry)
                .containerBackground(Color(red: 0.035, green: 0.07, blue: 0.12), for: .widget)
        }
        .configurationDisplayName("Flugzeug kompakt")
        .description("Flugdaten und Foto auf einer kompakten Glasfläche. iOS steuert die Aktualisierung.")
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

struct MediumAircraftView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: MediumEntry
    private var language: AppLanguage { entry.language }
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                if let plane = entry.plane, let snapshot = entry.snapshot {
                    HStack(spacing: 4) {
                        Circle().fill(plane.isEstimated ? .orange : .green).frame(width: 5, height: 5)
                        Text(language.text(plane.isEstimated ? "Geschätzt" : "Stand"))
                        Text(plane.positionAt ?? snapshot.dataDate, style: .time)
                        Spacer()
                        Text(snapshot.source?.title ?? "—")
                    }.font(.system(size: 8))
                    HStack(spacing: 5) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(plane.label).font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                            Text(plane.company(in: language)).font(.system(size: 10)).lineLimit(1)
                            Text(plane.model(in: language)).font(.system(size: 10)).italic().lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        WidgetPhoto(data: plane.photoData, language: language, modelCode: plane.modelPhotoCode)
                            .frame(width: 91, height: 50).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 6) {
                        metric(plane.altitudeLabel(in: language), label: language.text("Höhe"))
                        metric(plane.speedLabel(in: language), label: language.text("Tempo"))
                        metric(plane.distanceLabel(from: snapshot.center), label: language.text("Entfernung"))
                    }
                    HStack {
                        Text(plane.routeLabel).lineLimit(1)
                        if let motion = plane.motionLabel(from: snapshot.center, language: language) { Text(motion).lineLimit(1) }
                        Spacer(minLength: 2)

                    }.font(.system(size: 8))
                } else {
                    Text("SkyNear").font(.headline).unredacted()
                    Text(entry.load.message(in: language, at: entry.date)
                        ?? language.text("Keine erfassten Flugzeuge im Umkreis."))
                        .font(.caption).unredacted()
                }
                if entry.plane != nil, let message = entry.load.message(in: language, at: entry.date) {
                    Text(message).font(.system(size: 7)).foregroundStyle(.orange).lineLimit(1).unredacted()
                }
                WidgetDiagnosticFooter(load: entry.load)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .background(.black.opacity(renderingMode == .fullColor ? 0.65 : 0.9), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.4), lineWidth: 1))
        }
        .clipped()
        .widgetURL(URL(string: entry.plane.map { "skynear://aircraft/\($0.id)" } ?? "skynear://nearby"))
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 12, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 7)).foregroundStyle(.white.opacity(0.8))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediumEntry: TimelineEntry, Sendable {
    var date: Date
    var load: WidgetLoad
    var language: AppLanguage = .de
    var snapshot: RadarSnapshot? { load.snapshot(at: date) }
    var plane: Plane? { snapshot.flatMap { $0.nearest(to: $0.center, count: 1).first } }
}
struct MediumProvider: TimelineProvider, Sendable {
    func placeholder(in context: Context) -> MediumEntry { MediumEntry(date: Date(), load: WidgetLoad(real: nil)) }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (MediumEntry) -> Void) {
        RadarDiagnostics.record("provider medium snapshot begin preview=\(context.isPreview)")
        if context.isPreview { completion(placeholder(in: context)); return }
        Task {
            let load = await WidgetRadarData.shared.load().diagnosed(provider: "medium-snapshot", entryCount: 1, next: nil)
            completion(MediumEntry(date: Date(), load: load))
        }
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<MediumEntry>) -> Void) {
        RadarDiagnostics.record("provider medium timeline begin preview=\(context.isPreview)")
        Task {
            var load = await WidgetRadarData.shared.load()
            let now = Date()
            let dates = WidgetDates.entries(for: load, now: now)
            load = load.diagnosed(provider: "medium", entryCount: dates.count, next: now.addingTimeInterval(300))
            let entries = dates.map { MediumEntry(date: $0, load: load) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
        }
    }
}

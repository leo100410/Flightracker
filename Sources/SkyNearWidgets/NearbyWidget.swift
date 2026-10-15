import SwiftUI
import WidgetKit
import UIKit
import RadarCore

struct NearbyEntry: TimelineEntry, Sendable {
    var date: Date
    var load: WidgetLoad
    var language: AppLanguage
    var snapshot: RadarSnapshot? { load.snapshot(at: date) }
}
struct NearbyProvider: TimelineProvider, Sendable {
    var language: AppLanguage = .de
    func placeholder(in context: Context) -> NearbyEntry {
        NearbyEntry(date: Date(), load: WidgetLoad(real: nil,
            locationMessage: "Die fünf nächsten Flugzeuge werden hier angezeigt."), language: language)
    }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (NearbyEntry) -> Void) {
        RadarDiagnostics.record("provider nearby snapshot begin preview=\(context.isPreview)")
        if context.isPreview {
            completion(NearbyEntry(date: Date(), load: WidgetLoad(real: nil), language: language))
            return
        }
        let language = language
        Task {
            var load = await WidgetRadarData.shared.load()
            load = load.diagnosed(provider: "nearby-snapshot", entryCount: 1, next: nil)
            completion(NearbyEntry(date: Date(), load: load, language: language))
        }
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NearbyEntry>) -> Void) {
        RadarDiagnostics.record("provider nearby timeline begin preview=\(context.isPreview)")
        let language = language
        Task {
            var load = await WidgetRadarData.shared.load()
            let now = Date()
            let dates = WidgetDates.entries(for: load, now: now)
            load = load.diagnosed(provider: "nearby", entryCount: dates.count, next: now.addingTimeInterval(300))
            let entries = dates.map {
                NearbyEntry(date: $0, load: load, language: language)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
        }
    }
}
struct NearbyWidget: Widget {
    private let language: AppLanguage = .de
    let kind = "SkyNear.Nearby.v1"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NearbyProvider(language: language)) { entry in
            NearbyWidgetView(entry: entry)
                .containerBackground(Color(red: 0.035, green: 0.07, blue: 0.12), for: .widget)
                .environment(\.locale, entry.language.locale)
        }
        // WidgetKit gallery metadata must not use interpolated LocalizedStringKey values.
        .configurationDisplayName("5 Flugzeuge in deiner Nähe")
        .description("Foto und Flugdaten. iOS steuert die Aktualisierung.")
        .supportedFamilies([.systemLarge])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}
struct NearbyWidgetView: View {
    var entry: NearbyEntry
    private var language: AppLanguage { entry.language }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "airplane").foregroundStyle(.cyan)
                Text("SkyNear · \(language.text("Nächste 5"))").font(.system(size: 12, weight: .bold)).unredacted()
                Spacer()
                if let date = entry.snapshot?.dataDate { Text(date, style: .time).font(.system(size: 10)).monospacedDigit() }
            }
            if let snapshot = entry.snapshot, !snapshot.planes.isEmpty {
                ForEach(snapshot.nearest(to: snapshot.center)) { plane in
                    Link(destination: URL(string: "skynear://aircraft/\(plane.id)")!) {
                        WidgetPlaneRow(plane: plane, origin: snapshot.center, language: language)
                    }
                }
                Spacer(minLength: 0)
                Text("\(snapshot.source?.title ?? "—") · \(language.text(snapshot.isEstimated ? "Geschätzt" : (entry.load.outdated ? "Veraltet" : "Stand"))) · 463 km")
                    .font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(entry.load.outdated ? Color.orange : Color.white.opacity(0.9))
                if let message = entry.load.message(in: language, at: entry.date) {
                    Text(message).font(.system(size: 8)).foregroundStyle(.orange).lineLimit(1)
                }
            } else {
                Spacer()
                Text(entry.load.message(in: language, at: entry.date)
                     ?? language.text(entry.snapshot == nil ? "SkyNear öffnen und Standort für App und Widget erlauben." : "Keine erfassten Flugzeuge im Umkreis."))
                    .font(.caption).multilineTextAlignment(.leading)
                    .unredacted()
                Spacer()
                Text(language.text("App öffnen · Standort erlauben")).font(.caption2)
            }
            WidgetDiagnosticFooter(load: entry.load)
        }
        .foregroundStyle(.white)
        .padding(10)
        .widgetURL(URL(string: "skynear://nearby"))
    }
}
struct WidgetPlaneRow: View {
    var plane: Plane
    var origin: GeoPoint
    var language: AppLanguage
    var body: some View {
        HStack(spacing: 7) {
            WidgetPhoto(data: plane.photoData, language: language, modelCode: plane.modelPhotoCode)
                .frame(width: 53, height: 45).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(plane.label).font(.system(size: 11, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(plane.distanceLabel(from: origin)).font(.system(size: 9))
                        .foregroundStyle(plane.isEstimated ? .orange : .cyan)
                }
                Text("\(plane.company(in: language)) · \(plane.routeLabel)").font(.system(size: 9)).lineLimit(1)
                HStack(spacing: 3) {
                    Text(plane.model(in: language)).lineLimit(1)
                    if plane.isEstimated, let date = plane.positionAt {
                        Spacer(minLength: 1)
                        Text(date, style: .time).foregroundStyle(.orange)
                    }
                }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.9))
                Text("\(plane.altitudeLabel(in: language)) · \(plane.speedLabel(in: language))").font(.system(size: 10, weight: .medium)).monospacedDigit().lineLimit(1)
            }
        }.frame(height: 48)
    }
}
struct WidgetPhoto: View {
    var data: Data?
    var language: AppLanguage
    var modelCode: String? = nil
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                if #available(iOS 18.0, *) {
                    Image(uiImage: image).resizable()
                        .widgetAccentedRenderingMode(.desaturated).scaledToFill()
                } else { Image(uiImage: image).resizable().scaledToFill() }
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    VStack(spacing: 2) {
                        Image(systemName: "airplane")
                        Text(language.text("Kein Foto")).font(.system(size: 8))
                    }.foregroundStyle(.white)
                }
            }
        }.clipped()
        .overlay(alignment: .bottom) {
            if modelCode != nil {
                Text(language.text("Modellbild")).font(.system(size: 6))
                    .foregroundStyle(.white).padding(2).background(.black.opacity(0.8))
            }
        }
    }
}
@main
struct SkyNearWidgetBundle: WidgetBundle {
    var body: some Widget {
        NearbyWidget()
        NearestAircraftWidget()
        MediumAircraftWidget()
        NearbyLiveActivity()
    }
}

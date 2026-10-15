import SwiftUI
import WidgetKit
import MapKit
import UIKit
import RadarCore

struct MapFrame: Sendable {
    var image: Data?
    var userX: Double = 0.5
    var userY: Double = 0.5
    var planeX: Double?
    var planeY: Double?
}
struct NearestEntry: TimelineEntry, Sendable {
    var date: Date
    var load: WidgetLoad
    var language: AppLanguage
    var map: MapFrame
    var snapshot: RadarSnapshot? { load.snapshot(at: date) }
    var plane: Plane? { snapshot.flatMap { $0.nearest(to: $0.center, count: 1).first } }
}

@MainActor
enum WidgetMapSnapshot {
    private static var cached: (key: String, date: Date, snapshot: MKMapSnapshotter.Snapshot)?
    static func frames(load: WidgetLoad, dates: [Date], width: Double, height: Double) async -> [MapFrame] {
        guard let real = load.real else { return dates.map { _ in MapFrame(image: nil) } }
        let selected = dates.map { date in
            load.snapshot(at: date).flatMap { $0.nearest(to: $0.center, count: 1).first }
        }
        let points = [real.center] + selected.compactMap { $0?.point }
        let latitudeMin = points.map(\.latitude).min() ?? real.center.latitude
        let latitudeMax = points.map(\.latitude).max() ?? real.center.latitude
        let offsets = points.map { ($0.longitude - real.center.longitude + 540).truncatingRemainder(dividingBy: 360) - 180 }
        let minOffset = offsets.min() ?? 0, maxOffset = offsets.max() ?? 0
        let centerLongitude = (real.center.longitude + (minOffset + maxOffset) / 2 + 540)
            .truncatingRemainder(dividingBy: 360) - 180
        let options = MKMapSnapshotter.Options()
        let latitudeDelta = min(170, max(0.08, (latitudeMax - latitudeMin) * 3.5))
        options.region = MKCoordinateRegion(
            // Keep both markers in the upper map area, clear of the information card.
            center: CLLocationCoordinate2D(latitude: max(-85, min(85, (latitudeMin + latitudeMax) / 2 - latitudeDelta * 0.28)), longitude: centerLongitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta,
                                   longitudeDelta: min(359, max(0.08, (maxOffset - minOffset) * 1.8))))
        options.size = CGSize(width: max(100, width), height: max(100, height))
        options.scale = 2
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let key = "\(real.fetchedAt.timeIntervalSince1970):\(options.size):\(options.region.center.latitude):\(options.region.center.longitude):\(options.region.span.latitudeDelta):\(options.region.span.longitudeDelta)"
        let snapshotter = MKMapSnapshotter(options: options)
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) }
            catch { return }
            RadarDiagnostics.record("widget map timeout")
            snapshotter.cancel()
        }
        defer { timeout.cancel() }
        do {
            let snapshot: MKMapSnapshotter.Snapshot
            if let cached, cached.key == key, Date().timeIntervalSince(cached.date) < 300 {
                snapshot = cached.snapshot
            } else {
                snapshot = try await snapshotter.start()
                cached = (key, Date(), snapshot)
            }
            let bytes = snapshot.image.jpegData(compressionQuality: 0.8)
            let user = snapshot.point(for: real.center.coordinate)
            return selected.map { plane in
                let position = plane.map { snapshot.point(for: $0.point.coordinate) }
                return MapFrame(image: bytes, userX: user.x / options.size.width, userY: user.y / options.size.height,
                                planeX: position.map { $0.x / options.size.width },
                                planeY: position.map { $0.y / options.size.height })
            }
        } catch { RadarDiagnostics.record("widget map failed \(RadarDiagnostics.errorCode(error))"); return dates.map { _ in MapFrame(image: nil) } }
    }
}
struct NearestProvider: TimelineProvider, Sendable {
    var language: AppLanguage = .de
    func placeholder(in context: Context) -> NearestEntry {
        NearestEntry(date: Date(), load: WidgetLoad(real: nil), language: language, map: MapFrame(image: nil))
    }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (NearestEntry) -> Void) {
        RadarDiagnostics.record("provider map snapshot begin preview=\(context.isPreview)")
        if context.isPreview {
            completion(NearestEntry(date: Date(), load: WidgetLoad(real: nil), language: language, map: MapFrame(image: nil)))
            return
        }
        let width = Double(context.displaySize.width), height = Double(context.displaySize.height)
        let language = language
        Task {
            var load = await WidgetRadarData.shared.load()
            let now = Date()
            let frames = await WidgetMapSnapshot.frames(load: load, dates: [now], width: width, height: height)
            load = load.diagnosed(provider: "map-snapshot", entryCount: 1, next: nil)
            completion(NearestEntry(date: now, load: load, language: language, map: frames.first ?? MapFrame(image: nil)))
        }
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NearestEntry>) -> Void) {
        RadarDiagnostics.record("provider map timeline begin preview=\(context.isPreview)")
        // Copy scalar context values before calling into isolated snapshot generation.
        let width = Double(context.displaySize.width), height = Double(context.displaySize.height)
        let language = language
        Task {
            var load = await WidgetRadarData.shared.load()
            let now = Date()
            let dates = WidgetDates.entries(for: load, now: now)
            let frames = await WidgetMapSnapshot.frames(load: load, dates: dates, width: width, height: height)
            load = load.diagnosed(provider: "map", entryCount: dates.count, next: now.addingTimeInterval(300))
            let entries = zip(dates, frames).map {
                NearestEntry(date: $0.0, load: load, language: language, map: $0.1)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
        }
    }
}
struct NearestAircraftWidget: Widget {
    private let language: AppLanguage = .de
    let kind = "SkyNear.Nearest.v1"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NearestProvider(language: language)) { entry in
            NearestAircraftView(entry: entry)
                .containerBackground(Color(red: 0.035, green: 0.07, blue: 0.12), for: .widget)
                .environment(\.locale, entry.language.locale)
        }
        // Keep gallery metadata literal, as in NearbyWidget.
        .configurationDisplayName("Nächstes Flugzeug")
        .description("Das nächste erfasste Flugzeug mit Karte, Foto und Flugdaten. iOS steuert die Aktualisierung.")
        .supportedFamilies([.systemLarge])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}
struct NearestAircraftView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: NearestEntry
    private var language: AppLanguage { entry.language }
    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geometry in
                if let data = entry.map.image, let image = UIImage(data: data) {
                    mapImage(image).frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    Circle().fill(.blue).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(x: geometry.size.width * entry.map.userX, y: geometry.size.height * entry.map.userY)
                    if let x = entry.map.planeX, let y = entry.map.planeY, let plane = entry.plane {
                        AircraftMarker(plane: plane, size: 28)
                            .position(x: geometry.size.width * x, y: geometry.size.height * y)
                    }
                } else {
                    Color(red: 0.04, green: 0.08, blue: 0.14)
                    Text(language.text("Karte nicht verfügbar")).font(.caption2).foregroundStyle(.white).unredacted()
                        .padding(12)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(language.text("Nächstes Flugzeug")).font(.system(size: 11, weight: .semibold)).unredacted()
                if let plane = entry.plane, let snapshot = entry.snapshot {
                    HStack(spacing: 9) {
                        WidgetPhoto(data: plane.photoData, language: language, modelCode: plane.modelPhotoCode)
                            .frame(width: 65, height: 53).clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(plane.label).font(.system(size: 17, weight: .bold)).lineLimit(1)
                                Spacer(minLength: 2)
                                Text(plane.distanceLabel(from: snapshot.center)).font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(plane.isEstimated ? .orange : .cyan)
                            }
                            Text(plane.company(in: language)).font(.system(size: 11)).lineLimit(1)
                            Text(plane.model(in: language)).font(.system(size: 11)).lineLimit(1)
                        }
                    }
                    Text("\(plane.altitudeLabel(in: language)) · \(plane.speedLabel(in: language)) · \(plane.routeLabel)")
                        .font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    if let motion = plane.motionLabel(from: snapshot.center, language: language), let track = plane.track {
                        Label("\(Int(track.rounded()))° · \(motion)", systemImage: "location.north.line")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.9))
                    }
                    HStack(spacing: 4) {
                        Text(snapshot.source?.title ?? "—")
                        Text(language.text(plane.isEstimated ? "Geschätzt" : (entry.load.outdated ? "Veraltet" : "Stand")))
                        Text(plane.positionAt ?? snapshot.dataDate, style: .time)
                    }.font(.system(size: 9)).foregroundStyle(entry.load.outdated ? .orange : .white)
                } else {
                    Text(language.text(entry.snapshot == nil ? "SkyNear öffnen und Standort für App und Widget erlauben." : "Keine erfassten Flugzeuge im Umkreis."))
                        .font(.caption)
                        .unredacted()
                }
                if let message = entry.load.message(in: language, at: entry.date) {
                    Text(message).font(.system(size: 8)).foregroundStyle(.orange).lineLimit(2).unredacted()
                }
                Text("Apple Maps").font(.system(size: 8)).foregroundStyle(.white.opacity(0.8))
                WidgetDiagnosticFooter(load: entry.load)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .background(.black.opacity(renderingMode == .fullColor ? 0.86 : 0.95), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.3), lineWidth: 1))
            .padding(10)
        }
        .widgetURL(URL(string: entry.plane.map { "skynear://aircraft/\($0.id)" } ?? "skynear://nearby"))
    }
    @ViewBuilder private func mapImage(_ image: UIImage) -> some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: image).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
        } else { Image(uiImage: image).resizable().scaledToFill() }
    }
}

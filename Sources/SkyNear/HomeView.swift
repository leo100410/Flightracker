import SwiftUI
import MapKit
import RadarCore

struct HomeView: View {
    @Environment(\.skyLanguage) private var language
    @ObservedObject var store: RadarStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Plane?
    @State private var settings = false
    @State private var diagnosticImport: String?
    @State private var tab = 0
    @State private var pendingHex: String?
    var body: some View {
        TabView(selection: $tab) {
            MapScreen(store: store, selection: $selection, settings: $settings)
                .tabItem { Label(language.text("Radar"), systemImage: "map") }.tag(0)
            NearbyScreen(store: store, selection: $selection)
                .tabItem { Label(language.text("In deiner Nähe"), systemImage: "airplane.circle") }.tag(1)
        }
        .sheet(item: $selection) { plane in
            NavigationStack { DetailView(initial: plane, store: store) }
        }
        .sheet(isPresented: $settings, onDismiss: { diagnosticImport = nil }) {
            NavigationStack {
                if let diagnosticImport { DiagnosticsView(importMessage: diagnosticImport) }
                else { SettingsView(store: store) }
            }
        }
        .onAppear { AppDiagnostics.capture("view appeared"); if scenePhase == .active { store.activate() } }
        .onChange(of: scenePhase) { _, phase in
            AppDiagnostics.capture("scene \(String(describing: phase))")
            if phase == .active { store.activate() } else { store.deactivate() }
            if phase == .background { BackgroundRefresh.leavingForeground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            AppDiagnostics.capture("power state changed")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification)) { _ in
            AppDiagnostics.capture("background refresh availability changed")
        }
        .onOpenURL { url in
            guard url.scheme == "skynear" else { return }
            if url.host == "diagnostics" {
                do {
                    let count = try RadarDiagnostics.importWidgetURL(url)
                    diagnosticImport = "\(count) Widget-Eintraege uebernommen."
                } catch {
                    diagnosticImport = "Widget-Import fehlgeschlagen: " + RadarDiagnostics.errorCode(error)
                    RadarDiagnostics.record("widget import rejected \(RadarDiagnostics.errorCode(error))")
                }
                selection = nil
                settings = true
                return
            }
            tab = 1
            if url.host == "aircraft", let hex = url.path.split(separator: "/").first {
                pendingHex = String(hex)
                resolvePendingLink()
            }
        }
        .onChange(of: store.nearby?.fetchedAt) { _, _ in resolvePendingLink() }
    }
    private func resolvePendingLink() {
        guard let hex = pendingHex else { return }
        if let plane = store.nearby?.planes.first(where: { $0.id == hex })
                    ?? store.snapshot?.planes.first(where: { $0.id == hex }) {
            selection = plane; pendingHex = nil
        }
    }
}

struct MapScreen: View {
    @Environment(\.skyLanguage) private var language
    @ObservedObject var store: RadarStore
    @ObservedObject private var location: AppLocation
    @Binding var selection: Plane?
    @Binding var settings: Bool
    @State private var camera: MapCameraPosition = .automatic
    @State private var initialCentered = false
    @State private var panTask: Task<Void, Never>?
    init(store: RadarStore, selection: Binding<Plane?>, settings: Binding<Bool>) {
        self.store = store; _location = ObservedObject(wrappedValue: store.location)
        _selection = selection; _settings = settings
    }
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(store.snapshot?.planes ?? []) { plane in
                        Annotation(plane.label, coordinate: plane.point.coordinate, anchor: .center) {
                            Button { selection = plane } label: {
                                AircraftMarker(plane: plane, size: 30)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(plane.label), \(plane.altitudeLabel(in: language)), \(plane.speedLabel(in: language))")
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .mapControls { MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .onEnd) { context in
                    let center = GeoPoint(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                    panTask?.cancel()
                    panTask = Task { @MainActor in
                        do { try await Task.sleep(for: .milliseconds(700)) }
                        catch { return }
                        store.setCenter(center)
                    }
                }
                .onDisappear { panTask?.cancel() }
                VStack(spacing: 8) {
                    HStack {
                        Circle().fill(store.error == nil ? .green : .orange).frame(width: 7, height: 7)
                        Text("\(store.snapshot?.planes.count ?? 0) \(language.text("Erfasste Flugzeuge"))")
                        Spacer()
                        if store.loading { ProgressView() }
                        else if let date = store.snapshot?.dataDate { Text(date, style: .time).monospacedDigit() }
                    }.font(.caption)
                    if let error = store.error { Text(error).foregroundStyle(.orange).font(.caption) }
                    if let snapshot = store.snapshot {
                        Text("\(language.text("Quelle")): \(snapshot.source?.title ?? "—") · \(language.text(snapshot.isEstimated ? "Geschätzt" : "Stand"))")
                            .font(.caption2).foregroundStyle(snapshot.isEstimated ? .orange : .white)
                    }
                    if location.point == nil {
                        Text(language.text(location.message)).font(.caption)
                        Button(language.text("Standort erlauben")) { location.start() }
                    }
                }
                .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
                .padding(12)
            }
            .navigationTitle("SkyNear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { store.restartLoop() } label: { Image(systemName: "arrow.clockwise") }
                    Button {
                        if let point = location.point { move(to: point); store.centerOnMe() }
                        else { location.start() }
                    } label: { Image(systemName: "location.fill") }
                }
            }
            .onChange(of: location.point) { _, point in
                if !initialCentered, let point { initialCentered = true; move(to: point) }
            }
            .onAppear {
                if !initialCentered, let point = location.point { initialCentered = true; move(to: point) }
            }
        }
    }
    private func move(to point: GeoPoint) {
        camera = .region(MKCoordinateRegion(center: point.coordinate,
                         latitudinalMeters: store.radiusKM * 1600, longitudinalMeters: store.radiusKM * 1600))
    }
}

struct NearbyScreen: View {
    @Environment(\.skyLanguage) private var language
    @ObservedObject var store: RadarStore
    @ObservedObject private var location: AppLocation
    @Binding var selection: Plane?
    init(store: RadarStore, selection: Binding<Plane?>) {
        self.store = store; _location = ObservedObject(wrappedValue: store.location); _selection = selection
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let point = location.point, let snapshot = store.nearby {
                        let planes = snapshot.nearest(to: point)
                        if planes.isEmpty { Text(language.text("Keine erfassten Flugzeuge im geladenen Umkreis.")) }
                        ForEach(planes) { plane in
                            Button { selection = plane } label: {
                                PlaneRow(plane: plane, distance: plane.distanceLabel(from: point), origin: point)
                            }.buttonStyle(.plain)
                        }
                        Text("\(language.text("Stand")): \(snapshot.dataDate.formatted(.dateTime.hour().minute().second().locale(language.locale))) · \(snapshot.source?.title ?? "—") · \(Int(snapshot.radiusKM)) km")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(language.text(location.point == nil ? location.message : "Flugzeuge werden geladen …"))
                        if location.point == nil { Button(language.text("Standort freigeben")) { location.start() } }
                    }
                    if let error = store.nearbyError ?? store.error { Text(error).foregroundStyle(.orange) }
                } header: { Text(language.text("Die fünf nächsten erfassten Flugzeuge")) }
                Section(language.text("Sperrbildschirm")) {
                    Button {
                        Task { await store.toggleLive() }
                    } label: {
                        Label(language.text(store.liveRunning ? "Live Activity beenden" : "Live Activity starten"), systemImage: "livephoto")
                    }
                    .disabled(store.liveActionInProgress)
                    if store.liveActionInProgress { ProgressView() }
                    if let error = store.liveError { Text(error).foregroundStyle(.orange) }
                    if let status = store.liveStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                    Text(language.text("Live-Updates erfolgen durch die laufende App. Im Hintergrund sind keine dauerhaften Updates zugesagt."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(language.text("Homescreen-Widget")) {
                    Text(language.text("Widget-Anleitung"))
                    Text(language.text("iOS bestimmt den Aktualisierungszeitpunkt. Prüfe immer den angezeigten Datenstand."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(language.text("In deiner Nähe"))
            .refreshable { await store.refresh() }
        }
    }
}

struct PlaneRow: View {
    @Environment(\.skyLanguage) private var language
    var plane: Plane
    var distance: String
    var origin: GeoPoint? = nil
    var body: some View {
        HStack(spacing: 12) {
            PlanePhoto(url: plane.photoURL, reference: ModelPhotos.reference(for: plane), data: plane.photoData,
                       modelCode: plane.modelPhotoCode).frame(width: 85, height: 65).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                if plane.isEstimated {
                    Text(language.text("Geschätzt")).font(.caption.bold()).foregroundStyle(.orange)
                    if let date = plane.positionAt {
                        Text("\(language.text("Letzte echte Position")): \(date.formatted(.dateTime.hour().minute().second().locale(language.locale)))")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                HStack { Text(plane.label).font(.headline); Spacer(); Text(distance).font(.caption).foregroundStyle(plane.isEstimated ? .orange : .cyan) }
                Text(plane.company(in: language)).font(.caption).lineLimit(1)
                Text("\(plane.model(in: language)) · \(plane.routeLabel)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(plane.altitudeLabel(in: language)) · \(plane.speedLabel(in: language))").font(.caption).monospacedDigit()
                if let origin, let motion = plane.motionLabel(from: origin, language: language) {
                    Text(motion).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 4)
    }
}

struct PlanePhoto: View {
    @Environment(\.skyLanguage) private var language
    let url: URL?
    var reference: ModelPhoto? = nil
    var data: Data? = nil
    var modelCode: String? = nil
    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().clipped()
                .overlay(alignment: .bottomTrailing) {
                    if modelCode != nil { modelLabel }
                }
        } else if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else if phase.error != nil { fallback }
                else { ZStack { Color.white.opacity(0.06); ProgressView() } }
            }.clipped()
        } else { fallback }
    }
    private var modelLabel: some View {
        Text(language.text("Modellbild")).font(.system(size: 8)).foregroundStyle(.white)
            .padding(3).background(.black.opacity(0.8))
    }
    @ViewBuilder private var fallback: some View {
        if let reference, let data = reference.data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().clipped()
                .overlay(alignment: .bottomTrailing) { modelLabel }
        } else { placeholder(language.text("Kein Foto")) }
    }
    private func placeholder(_ text: String) -> some View {
        ZStack {
            Color.white.opacity(0.06)
            VStack(spacing: 4) {
                Image(systemName: "airplane").font(.title2).foregroundStyle(.cyan)
                Text(text).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

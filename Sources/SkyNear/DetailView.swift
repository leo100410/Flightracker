import SwiftUI
import UIKit
import MapKit
import RadarCore

struct DetailView: View {
    @Environment(\.skyLanguage) private var language
    let initial: Plane
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss
    @State private var detailed: Plane?
    @State private var fetching = true
    private var positionAvailable: Bool { store.currentPlane(id: initial.id) != nil }
    private var plane: Plane {
        var result = store.currentPlane(id: initial.id) ?? initial
        if let detailed, detailed.callsign == result.callsign {
            result.metadata = detailed.metadata ?? result.metadata
            result.photoData = detailed.photoData ?? result.photoData
            result.modelPhotoCode = detailed.modelPhotoCode ?? result.modelPhotoCode
        }
        return result
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PlanePhoto(url: plane.photoURL, reference: ModelPhotos.reference(for: plane), data: plane.photoData,
                           modelCode: plane.modelPhotoCode)
                    .frame(height: 220).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                if plane.photoURL != nil {
                    Text(language.text("Foto: airport-data via adsbdb. Urheberrechte beim jeweiligen Fotografen."))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let url = plane.photoURL { Link(language.text("Bildquelle öffnen"), destination: url).font(.caption) }
                }
                HStack { Text(plane.label).font(.largeTitle.bold()); Spacer(); if fetching { ProgressView() } }
                if let reference = ModelPhotos.reference(for: plane) {
                    Text("\(language.text("Modellbild")): \(reference.title) · \(reference.author) · \(reference.license)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(language.text("Modellfoto zeigt ein anderes Flugzeug; Lackierung kann abweichen."))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let url = URL(string: reference.source) {
                        Link(language.text("Bildquelle öffnen"), destination: url).font(.caption)
                    }
                    if let url = URL(string: reference.licenseURL) { Link(reference.license, destination: url).font(.caption) }
                }
                Text(plane.model(in: language)).font(.title3)
                if !positionAvailable {
                    Text(language.text("Keine aktuelle Position verfügbar.")).foregroundStyle(.orange)
                } else if plane.isEstimated {
                    Text(language.text("Geschätzt")).font(.headline).foregroundStyle(.orange)
                    Text(language.text("Prognose-Hinweis")).font(.caption).foregroundStyle(.orange)
                }
                if let date = plane.positionAt {
                    Text("\(language.text("Letzte echte Position")): \(date.formatted(.dateTime.hour().minute().second().locale(language.locale)))")
                        .font(.caption)
                }
                GroupBox(language.text("Flugdaten")) {
                    VStack(spacing: 10) {
                        field(language.text("Airline"), plane.company(in: language))
                        field(language.text("Kennzeichen"), plane.metadata?.aircraft?.registration ?? plane.registration ?? language.text("Unbekannt"))
                        field(language.text("Modellcode"), plane.typeCode ?? language.text("Unbekannt"))
                        field(language.text("Eingetragener Eigentümer"), plane.metadata?.aircraft?.registered_owner ?? language.text("Unbekannt"))
                        field(language.text("Höhe"), plane.altitudeLabel(in: language))
                        field(language.text("Geschwindigkeit über Grund"), plane.speedLabel(in: language))
                        field("ICAO / Mode S", plane.id.uppercased())
                        if positionAvailable, let user = store.location.point { field(language.text("Entfernung zu dir"), plane.distanceLabel(from: user)) }
                        if let track = plane.track, track.isFinite, (0..<360).contains(track) {
                            field(language.text("Kurs"), "\(Int(track.rounded()))°")
                        }
                        if let age = plane.secondsSincePosition, age.isFinite, (0...90).contains(age) {
                            field(language.text("Positionsalter beim Abruf"), "\(Int(age.rounded())) s")
                        }
                    }
                }
                GroupBox(language.text("Bekannte Rufzeichenroute")) {
                    VStack(alignment: .leading, spacing: 10) {
                        airport(language.text("Herkunft"), plane.metadata?.flightroute?.origin)
                        airport(language.text("Ziel"), plane.metadata?.flightroute?.destination)
                        Text(language.text("Route aus einer Referenzdatenbank, nicht als aktueller Flugplan verifiziert. Umleitungen und Zwischenstopps können fehlen."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let origin = plane.metadata?.flightroute?.origin?.point,
                   let destination = plane.metadata?.flightroute?.destination?.point {
                    Map {
                        Marker(language.text("Start"), systemImage: "airplane.departure", coordinate: origin.coordinate)
                        Marker(language.text("Ziel"), systemImage: "airplane.arrival", coordinate: destination.coordinate)
                        if positionAvailable {
                            Annotation(plane.label, coordinate: plane.point.coordinate) {
                                AircraftMarker(plane: plane)
                            }
                        }
                        MapPolyline(coordinates: [origin.coordinate, destination.coordinate]).stroke(.cyan.opacity(0.6), lineWidth: 2)
                    }.frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 14))
                    Text(language.text("Linie verbindet die Flughäfen, sie ist keine tatsächlich geflogene Spur."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if plane.metadata == nil, !fetching {
                    Text(language.text("Keine Referenzdaten verfügbar oder Referenzdienst nicht erreichbar. Positionsdaten bleiben verwendbar."))
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(language.text("Höhe ist nicht Höhe über dem Boden."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle(language.text("Flugzeug"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(language.text("Fertig")) { dismiss() } } }
        .task(id: initial.id) {
            fetching = true
            let result = await store.details(for: initial)
            if !Task.isCancelled { detailed = result; fetching = false }
        }
    }
    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }
            .font(.subheadline)
    }
    private func airport(_ name: String, _ airport: Airport?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(language.text(airport?.label ?? "Unbekannt")).font(.headline)
            if let title = airport?.name { Text(title).font(.subheadline) }
            if let city = airport?.municipality { Text(city).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct SettingsView: View {
    @Environment(\.skyLanguage) private var language
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Diagnose") {
                NavigationLink("Aktualisierung und Logdatei") { DiagnosticsView() }
            }
            Section(language.text("Sprache")) {
                Picker(language.text("Sprache"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { item in Text(item.title).tag(item) }
                }
                Text(language.text("Widget-Sprache separat wählen")).font(.caption)
            }
            Section(language.text("Kartenumkreis")) {
                Picker(language.text("Radius"), selection: $store.radiusKM) {
                    Text("50 km").tag(50.0)
                    Text("150 km").tag(150.0)
                    Text("300 km").tag(300.0)
                    Text("463 km").tag(463.0)
                }.onChange(of: store.radiusKM) { _, _ in store.changeRadius() }
                Text(language.text("Die Karte lädt alle von der Quelle gemeldeten aktuellen Positionen in diesem Umkreis. Verschiebe sie, um andere Regionen zu laden. Keine vollständige Weltabdeckung."))
                    .font(.caption)
            }
            Section(language.text("Einheiten und Updates")) {
                Text(language.text("Höhe: Meter · Geschwindigkeit: km/h · Entfernung: km"))
                Text(language.text("App: 20 Sekunden gewünschtes Abrufintervall bei aktiver App. Netzwerkzeit kommt hinzu. Widget: 5 Minuten angefragt, tatsächlicher Zeitpunkt durch iOS."))
                    .font(.caption)
                Text(language.text("Widget-Prognosen: Minutenschritte angefragt, maximal 15 Minuten. iOS kann Einträge verzögern. Höhe und Tempo bleiben Messwerte."))
                    .font(.caption)
                Text(language.text("Ohne Server: Live Activity aktualisiert bei aktiver App und gelegentlich im Hintergrund. Kein garantierter Hintergrundtakt."))
                    .font(.caption)
                if let time = UserDefaults.standard.object(forKey: "skynear.background-success.v1") as? Double {
                    HStack {
                        Text(language.text("Letzter Hintergrundabruf"))
                        Text(Date(timeIntervalSince1970: time), style: .time)
                    }.font(.caption)
                }
                if let error = UserDefaults.standard.string(forKey: "skynear.background-error.v1") {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            Section(language.text("Datenquellen, Datenschutz und Grenzen")) {
                Text(SourceInformation.text(in: language)).font(.caption)
                Link("ADSB.lol", destination: URL(string: "https://www.adsb.lol/")!)
                Link("adsb.fi", destination: URL(string: "https://adsb.fi/")!)
                Link("adsbdb", destination: URL(string: "https://www.adsbdb.com/")!)
                Button(language.text("iPhone-App-Einstellungen öffnen")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .navigationTitle(language.text("Einstellungen"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(language.text("Fertig")) { dismiss() } } }
    }
}

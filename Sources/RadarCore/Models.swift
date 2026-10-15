import Foundation
import CoreLocation
import ActivityKit

public struct GeoPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude; self.longitude = longitude
    }
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    public func distance(to other: GeoPoint) -> Double {
        let r = 6_371.0
        let p1 = latitude * .pi / 180, p2 = other.latitude * .pi / 180
        let dp = (other.latitude - latitude) * .pi / 180
        let dl = (other.longitude - longitude) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return r * 2 * atan2(sqrt(max(0, min(1, a))), sqrt(max(0, 1 - a)))
    }
}

public struct Airport: Codable, Sendable, Hashable {
    public let iata_code: String?
    public let icao_code: String?
    public let name: String?
    public let municipality: String?
    public let latitude: Double?
    public let longitude: Double?
    public var label: String { iata_code?.nonEmpty ?? icao_code?.nonEmpty ?? name?.nonEmpty ?? "Unbekannt" }
    public var point: GeoPoint? {
        guard let latitude, let longitude else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }
}

public struct Airline: Codable, Sendable, Hashable { public let name: String? }
public struct AircraftReference: Codable, Sendable, Hashable {
    public let type: String?
    public let manufacturer: String?
    public let registration: String?
    public let registered_owner: String?
    public let url_photo: String?
    public let url_photo_thumbnail: String?
}
public struct FlightRoute: Codable, Sendable, Hashable {
    public let airline: Airline?
    public let origin: Airport?
    public let destination: Airport?
}
public struct Metadata: Codable, Sendable, Hashable {
    public var aircraft: AircraftReference?
    public var flightroute: FlightRoute?
    public init(aircraft: AircraftReference? = nil, flightroute: FlightRoute? = nil) {
        self.aircraft = aircraft; self.flightroute = flightroute
    }
}

public struct Plane: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var callsign: String
    public var registration: String?
    public var typeCode: String?
    public var point: GeoPoint
    public var altitudeFeet: Double?
    public var onGround: Bool
    public var speedKnots: Double?
    public var track: Double?
    public var secondsSincePosition: Double?
    public var metadata: Metadata?
    public var photoData: Data?
    public var metadataChecked: Bool = false
    // Optional additions keep the existing v1 widget cache readable.
    public var positionAt: Date? = nil
    public var estimatedAt: Date? = nil
    public var modelPhotoCode: String? = nil
    public var isEstimated: Bool { estimatedAt != nil }
    public func motionLabel(from origin: GeoPoint, language: AppLanguage) -> String? {
        guard !onGround, let speedKnots, speedKnots > 20, let track,
              let next = PositionPrediction.destination(from: point, speedKnots: speedKnots, course: track, seconds: 10) else { return nil }
        let change = origin.distance(to: next) - origin.distance(to: point)
        return language.text(abs(change) < 0.005 ? "Seitlich" : (change < 0 ? "Nähert sich" : "Entfernt sich"))
    }
    public var label: String { callsign.nonEmpty ?? registration?.nonEmpty ?? id.uppercased() }
    public var model: String { metadata?.aircraft?.type?.nonEmpty ?? typeCode?.nonEmpty ?? "Modell unbekannt" }
    public var company: String { metadata?.flightroute?.airline?.name?.nonEmpty ?? "Airline unbekannt" }
    public var owner: String { metadata?.aircraft?.registered_owner?.nonEmpty ?? "Unbekannt" }
    public var routeLabel: String {
        "\(metadata?.flightroute?.origin?.label ?? "?") → \(metadata?.flightroute?.destination?.label ?? "?")"
    }
    public var photoURL: URL? {
        guard let text = metadata?.aircraft?.url_photo_thumbnail ?? metadata?.aircraft?.url_photo,
              let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }
    public var altitudeLabel: String {
        if onGround { return "Am Boden" }
        guard let altitudeFeet, altitudeFeet.isFinite, abs(altitudeFeet) < 1_000_000 else { return "Höhe ?" }
        return "\(Int((altitudeFeet * 0.3048).rounded())) m"
    }
    public var speedLabel: String {
        guard let speedKnots, speedKnots.isFinite, (0...1500).contains(speedKnots) else { return "Tempo ?" }
        return "\(Int((speedKnots * 1.852).rounded())) km/h"
    }
    public func distanceLabel(from origin: GeoPoint) -> String {
        (isEstimated ? "~" : "") + String(format: "%.1f km", origin.distance(to: point))
    }
    public func model(in language: AppLanguage) -> String {
        metadata?.aircraft?.type?.nonEmpty ?? typeCode?.nonEmpty ?? language.text("Modell unbekannt")
    }
    public func company(in language: AppLanguage) -> String {
        metadata?.flightroute?.airline?.name?.nonEmpty ?? language.text("Airline unbekannt")
    }
    public func altitudeLabel(in language: AppLanguage) -> String {
        language.text(altitudeLabel)
    }
    public func speedLabel(in language: AppLanguage) -> String { language.text(speedLabel) }
}

public struct RadarSnapshot: Codable, Sendable {
    public var fetchedAt: Date
    public var center: GeoPoint
    public var radiusKM: Double
    public var planes: [Plane]
    public var source: PositionSource? = nil
    public var sourceTime: Date? = nil
    public var sourceIssues: [SourceIssue]? = nil
    public init(fetchedAt: Date, center: GeoPoint, radiusKM: Double, planes: [Plane]) {
        self.fetchedAt = fetchedAt; self.center = center; self.radiusKM = radiusKM; self.planes = planes
    }
    public func nearest(to point: GeoPoint, count: Int = 5) -> [Plane] {
        Array(planes.sorted { point.distance(to: $0.point) < point.distance(to: $1.point) }.prefix(count))
    }
}

public enum AltitudeValue: Decodable, Sendable {
    case feet(Double), ground, unavailable
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Double.self) { self = .feet(number) }
        else if let text = try? value.decode(String.self) {
            if text == "ground" { self = .ground }
            else if let number = Double(text) { self = .feet(number) }
            else { self = .unavailable }
        } else { self = .unavailable }
    }
}

struct LiveResponse: Decodable, Sendable {
    let ac: [LiveAircraft]?
    let aircraft: [LiveAircraft]?
    let msg: String?
    let now: Double?
}
struct LiveAircraft: Decodable, Sendable {
    let hex: String
    let flight: String?
    let r: String?
    let t: String?
    let lat: Double?
    let lon: Double?
    let alt_baro: AltitudeValue?
    let alt_geom: Double?
    let gs: Double?
    let track: Double?
    let seen_pos: Double?
    func plane(responseTime: Date? = nil, fetchedAt: Date = Date()) -> Plane? {
        guard !hex.isEmpty, hex.count <= 8,
              hex.allSatisfy({ $0.isHexDigit || $0 == "~" }) else { return nil }
        guard let lat, let lon, lat.isFinite, lon.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        guard seen_pos.map({ $0.isFinite && $0 >= 0 && $0 <= 90 }) ?? true else { return nil }
        let positionTime = responseTime.flatMap { time in
            seen_pos.map { time.addingTimeInterval(-$0) }
        }
        if let positionTime {
            guard fetchedAt.timeIntervalSince(positionTime) >= -5,
                  fetchedAt.timeIntervalSince(positionTime) <= 90 else { return nil }
        }
        var feet: Double? = alt_geom
        var ground = false
        if let alt_baro {
            switch alt_baro {
            case .feet(let value): feet = value
            case .ground: ground = true; feet = nil
            case .unavailable: break
            }
        }
        var result = Plane(id: hex.lowercased(), callsign: flight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                     registration: r, typeCode: t, point: GeoPoint(latitude: lat, longitude: lon),
                     altitudeFeet: feet, onGround: ground, speedKnots: gs, track: track,
                     secondsSincePosition: seen_pos)
        result.positionAt = positionTime
        return result
    }
}

public enum RadarError: LocalizedError, Sendable {
    case http(Int), invalidResponse, location(String), rateLimited(Int, Date?), deferred(Date)
    public var errorDescription: String? {
        switch self {
        case .http(403): return "Positionsquelle verweigert Zugriff (HTTP 403). Keine aktuellen Flugdaten geladen."
        case .http(429): return "Die Datenquelle begrenzt gerade Anfragen. Später erneut versuchen."
        case .http(let code): return "Datenquelle antwortet mit HTTP \(code)."
        case .invalidResponse: return "Die Datenquelle hat keine gültige Flugzeugantwort geliefert."
        case .location(let message): return message
        case .rateLimited(let code, _): return "HTTP \(code) · \(AppLanguage.de.text("Wartezeit der Quelle"))"
        case .deferred: return "Nächster Abruf vorgemerkt."
        }
    }
    public func message(in language: AppLanguage) -> String {
        switch self {
        case .http(let code), .rateLimited(let code, _):
            return "HTTP \(code) · " + language.text(code == 429 ? "Rate Limit" : "Quelle nicht erreichbar")
        case .invalidResponse: return language.text("Ungültige Antwort")
        case .location(let message): return language.text(message)
        case .deferred(let date): return language.text("Nächster Abruf") + " " + date.formatted(date: .omitted, time: .standard)
        }
    }
}

public struct NearbyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var updated: Date
        public var rows: [ActivityRow]
        public var language: AppLanguage? = nil
        public var source: PositionSource? = nil
        public var estimated: Bool? = nil
        public var validUntil: Date? = nil
        public var status: String? = nil
        public init(updated: Date, rows: [ActivityRow], language: AppLanguage = .de,
                    source: PositionSource? = nil, estimated: Bool = false,
                    validUntil: Date? = nil, status: String? = nil) {
            self.updated = updated; self.rows = rows; self.language = language
            self.source = source; self.estimated = estimated; self.validUntil = validUntil; self.status = status
        }
    }
    public var title: String
    public init(title: String) { self.title = title }
}
public struct ActivityRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var model: String
    public var company: String
    public var route: String
    public var altitude: String
    public var speed: String
    public var distance: String
    public var typeCode: String? = nil
    public var positionAt: Date? = nil
    public var estimated: Bool? = nil
    public init(plane: Plane, origin: GeoPoint, language: AppLanguage = .de) {
        id = plane.id; label = String(plane.label.prefix(12)); model = String(plane.model(in: language).prefix(26))
        company = String(plane.company(in: language).prefix(26)); route = String(plane.routeLabel.prefix(20))
        altitude = plane.altitudeLabel(in: language); speed = plane.speedLabel(in: language)
        distance = plane.distanceLabel(from: origin)
        if let code = plane.typeCode?.nonEmpty { typeCode = String(code.prefix(6)) }
        positionAt = plane.positionAt; estimated = plane.isEstimated
    }
}

extension String {
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

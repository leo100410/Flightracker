import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor RadarAPI {
    public static let shared = RadarAPI()
    private struct CacheItem { let value: Metadata?; let expires: Date }
    private var metadataCache: [String: CacheItem] = [:]
    private let session: URLSession
    public init(requestTimeout: TimeInterval = 7, resourceTimeout: TimeInterval = 12) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpMaximumConnectionsPerHost = 5
        session = URLSession(configuration: configuration)
    }
    private func get(_ url: URL, maxBytes: Int = 8_000_000) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("SkyNear/1.1 (personal iOS flight radar)", forHTTPHeaderField: "User-Agent")
        let requestID = String(UUID().uuidString.prefix(8))
        let category: String
        switch url.host {
        case "api.adsb.lol": category = "positions.adsbLOL"
        case "opendata.adsb.fi": category = "positions.adsbFI"
        case "api.adsbdb.com": category = "metadata"
        default: category = "photo"
        }
        let start = Date()
        RadarDiagnostics.record("network begin id=\(requestID) kind=\(category)")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw RadarError.invalidResponse }
            let retry = PositionTime.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: Date())
            RadarDiagnostics.record("network response id=\(requestID) kind=\(category) http=\(http.statusCode) bytes=\(data.count) ms=\(Int(Date().timeIntervalSince(start) * 1000)) retry=\(RadarDiagnostics.stamp(retry))")
            guard (200..<300).contains(http.statusCode) else {
                throw RadarError.rateLimited(http.statusCode, retry)
            }
            guard data.count <= maxBytes else { throw RadarError.invalidResponse }
            return data
        } catch {
            RadarDiagnostics.record("network failed id=\(requestID) kind=\(category) error=\(RadarDiagnostics.errorCode(error)) timeout=\((error as NSError).code == NSURLErrorTimedOut) cancelled=\(Task.isCancelled) ms=\(Int(Date().timeIntervalSince(start) * 1000))")
            throw error
        }
    }

    public func positions(source: PositionSource, center: GeoPoint, radiusKM: Double) async throws -> RadarSnapshot {
        let radiusNM = min(250, max(1, radiusKM / 1.852))
        let url = source.url(center: center, radiusKM: radiusKM)
        let response = try JSONDecoder().decode(LiveResponse.self, from: try await get(url))
        let fetchedAt = Date()
        let responseTime = PositionTime.date(response.now, fetchedAt: fetchedAt)
        if response.now != nil, responseTime == nil { throw RadarError.invalidResponse }
        guard let raw = response.ac ?? response.aircraft else { throw RadarError.invalidResponse }
        if let msg = response.msg, msg.lowercased() != "no error", !msg.isEmpty {
            throw RadarError.invalidResponse
        }
        var ids = Set<String>()
        let planes = raw.compactMap { $0.plane(responseTime: responseTime, fetchedAt: fetchedAt) }
            .filter { ids.insert($0.id).inserted }
        var snapshot = RadarSnapshot(fetchedAt: fetchedAt, center: center, radiusKM: radiusNM * 1.852, planes: planes)
        snapshot.source = source; snapshot.sourceTime = responseTime
        return snapshot
    }
    public func enrichSnapshot(_ positions: RadarSnapshot, at origin: GeoPoint?, photos: Bool = false) async throws -> RadarSnapshot {
        var snapshot = positions
        if let origin {
            let nearest = snapshot.nearest(to: origin)
            let enriched = await withTaskGroup(of: Plane.self, returning: [Plane].self) { group in
                for plane in nearest {
                    group.addTask { await self.enrich(plane, photo: photos) }
                }
                var result: [Plane] = []
                for await plane in group { result.append(plane) }
                return result
            }
            let byID = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })
            snapshot.planes = positions.planes.map { byID[$0.id] ?? $0 }
        }
        try Task.checkCancellation()
        return snapshot
    }
    public func enrich(_ plane: Plane, photo: Bool = false) async -> Plane {
        var result = plane
        result.metadata = await metadata(hex: plane.id, callsign: plane.callsign) ?? plane.metadata
        result.metadataChecked = true
        if photo, let url = result.photoURL, !Task.isCancelled,
           let bytes = try? await get(url, maxBytes: 3_000_000) {
            result.photoData = Self.thumbnail(bytes)
            if result.photoData != nil { result.modelPhotoCode = nil }
        }
        if photo, result.photoData == nil, let reference = ModelPhotos.reference(for: result), let data = reference.data {
            result.photoData = data; result.modelPhotoCode = reference.code
        }
        return result
    }
    private struct Envelope: Decodable { let response: Metadata }
    private func metadata(hex: String, callsign: String) async -> Metadata? {
        let key = hex + ":" + callsign
        if let cached = metadataCache[key], cached.expires > Date() { return cached.value }
        guard !Task.isCancelled else { return nil }
        if metadataCache.count > 800 { metadataCache = metadataCache.filter { $0.value.expires > Date() } }
        var components = URLComponents(string: "https://api.adsbdb.com/v0/aircraft/\(hex)")!
        if !callsign.isEmpty { components.queryItems = [URLQueryItem(name: "callsign", value: callsign)] }
        var value: Metadata?
        if let url = components.url, let data = try? await get(url, maxBytes: 500_000) {
            value = try? JSONDecoder().decode(Envelope.self, from: data).response
        }
        // A known route can exist even when the aircraft isn't in the reference database.
        if value == nil, !callsign.isEmpty, !Task.isCancelled,
           let encoded = callsign.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "https://api.adsbdb.com/v0/callsign/\(encoded)"),
           let data = try? await get(url, maxBytes: 500_000),
           let route = try? JSONDecoder().decode(Envelope.self, from: data).response.flightroute {
            if value == nil { value = Metadata() }
            value?.flightroute = route
        }
        if !Task.isCancelled {
            // Memory only. No permanent route database or bulk harvesting.
            metadataCache[key] = CacheItem(value: value, expires: Date().addingTimeInterval(value == nil ? 180 : 1800))
        }
        return value
    }
    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 144,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

public enum SourceInformation {
    public static var text: String {
        guard let url = RadarResources.url(forResource: "Sources", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "ADSB.lol · adsb.fi · adsbdb" }
        return text
    }
    public static func text(in language: AppLanguage) -> String {
        let name = language == .de ? "Sources" : "Sources-\(language.rawValue)"
        guard let url = RadarResources.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return Self.text }
        return text
    }
}

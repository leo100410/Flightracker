import Foundation

public struct SavedLocation: Codable, Sendable {
    public var point: GeoPoint
    public var measuredAt: Date
    public init(point: GeoPoint, measuredAt: Date) {
        self.point = point; self.measuredAt = measuredAt
    }
}

// Each process uses its own sandbox. No unsigned App Group entitlement is assumed.
public enum LocationMemory {
    public static func load() -> SavedLocation? {
        guard let data = UserDefaults.standard.data(forKey: "skynear.last-location.v1"),
              let saved = try? JSONDecoder().decode(SavedLocation.self, from: data),
              saved.point.latitude.isFinite, saved.point.longitude.isFinite,
              (-90...90).contains(saved.point.latitude), (-180...180).contains(saved.point.longitude),
              saved.measuredAt.timeIntervalSinceNow <= 5 else { return nil }
        return saved
    }
    public static func save(_ saved: SavedLocation) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: "skynear.last-location.v1")
    }
}

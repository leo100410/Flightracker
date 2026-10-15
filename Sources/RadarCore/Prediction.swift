import Foundation

public extension NearbyActivityAttributes.ContentState {
    /// Freshness and prediction expiry are separate: a valid estimate is still old data.
    var staleAt: Date { min(updated.addingTimeInterval(60), validUntil ?? .distantFuture) }
}

public enum PositionPrediction {
    public static let maximumAge: TimeInterval = 15 * 60

    public static func displayedPlane(_ real: Plane, fetchedAt: Date, at date: Date) -> Plane? {
        guard !real.isEstimated else { return nil }
        let age = date.timeIntervalSince(real.positionAt ?? fetchedAt)
        guard age >= -5 else { return nil }
        if age <= 5 { return real }
        if let projected = plane(real, at: date) { return projected }
        // Ground aircraft and incomplete measurements stay real briefly, never projected.
        return age < 90 ? real : nil
    }

    public static func expiry(of real: Plane, fetchedAt: Date) -> Date {
        let time = real.positionAt ?? fetchedAt
        let projectable = !real.onGround && real.positionAt != nil && real.speedKnots != nil
            && real.track != nil && destination(from: real.point, speedKnots: real.speedKnots ?? -1,
                                                course: real.track ?? -1, seconds: 0) != nil
        return time.addingTimeInterval(projectable ? maximumAge : 90)
    }

    public static func destination(from origin: GeoPoint, speedKnots: Double,
                                   course: Double, seconds: TimeInterval) -> GeoPoint? {
        guard origin.latitude.isFinite, origin.longitude.isFinite,
              (-90...90).contains(origin.latitude), (-180...180).contains(origin.longitude),
              speedKnots.isFinite, speedKnots >= 0, speedKnots <= 1500,
              course.isFinite, (0..<360).contains(course), seconds.isFinite,
              seconds >= 0, seconds <= maximumAge else { return nil }
        let angularDistance = speedKnots * 1.852 * seconds / 3600 / 6371
        let bearing = course * .pi / 180
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180
        let nextLatitude = asin(max(-1, min(1, sin(latitude) * cos(angularDistance)
            + cos(latitude) * sin(angularDistance) * cos(bearing))))
        let nextLongitude = longitude + atan2(sin(bearing) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(nextLatitude))
        let degrees = nextLongitude * 180 / .pi
        return GeoPoint(latitude: nextLatitude * 180 / .pi,
                        longitude: (degrees + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    public static func plane(_ real: Plane, at date: Date) -> Plane? {
        guard !real.onGround, real.estimatedAt == nil,
              let time = real.positionAt, let speed = real.speedKnots, let course = real.track,
              let point = destination(from: real.point, speedKnots: speed,
                                      course: course, seconds: date.timeIntervalSince(time)),
              date.timeIntervalSince(time) < maximumAge else { return nil }
        var result = real
        result.point = point
        result.estimatedAt = date
        return result
    }

    public static func timelineDates(for real: RadarSnapshot, from now: Date) -> [Date] {
        let ends = real.planes.map { expiry(of: $0, fetchedAt: real.fetchedAt) }.filter { $0 > now }
        guard let last = ends.max() else { return [now] }
        var dates = [now]
        var next = now.addingTimeInterval(60)
        while next < last { dates.append(next); next = next.addingTimeInterval(60) }
        // Every row gets its own terminal entry; one expiry must not stop other rows.
        dates.append(contentsOf: ends)
        return Array(Set(dates)).sorted()
    }
}

extension RadarSnapshot {
    public func displayed(at date: Date) -> RadarSnapshot {
        var result = self
        result.planes = planes.compactMap { PositionPrediction.displayedPlane($0, fetchedAt: fetchedAt, at: date) }
            .filter { center.distance(to: $0.point) <= radiusKM }
        return result
    }
    public func predicted(at date: Date) -> RadarSnapshot {
        var result = self
        result.planes = planes.compactMap { PositionPrediction.plane($0, at: date) }
            .filter { center.distance(to: $0.point) <= radiusKM }
        return result
    }

    public var dataDate: Date { sourceTime ?? fetchedAt }
    public var isEstimated: Bool { planes.contains { $0.isEstimated } }
    public var predictionEnd: Date? {
        planes.compactMap(\.positionAt).map { $0.addingTimeInterval(PositionPrediction.maximumAge) }.min()
    }
}

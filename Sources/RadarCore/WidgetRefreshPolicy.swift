import Foundation

public enum WidgetRefreshPolicy {
    public static func canReuse(_ success: RadarSnapshot, at date: Date, center: GeoPoint) -> Bool {
        let age = date.timeIntervalSince(success.fetchedAt)
        return age >= 0 && age < 60 && success.center.distance(to: center) < 3
    }
}

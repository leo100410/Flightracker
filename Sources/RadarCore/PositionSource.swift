import Foundation

public enum PositionSource: String, Codable, CaseIterable, Hashable, Sendable {
    case adsbLOL, adsbFI
    public var title: String { self == .adsbLOL ? "ADSB.lol" : "adsb.fi" }
    public func url(center: GeoPoint, radiusKM: Double) -> URL {
        let locale = Locale(identifier: "en_US_POSIX")
        let lat = String(format: "%.3f", locale: locale, center.latitude)
        let lon = String(format: "%.3f", locale: locale, center.longitude)
        let nm = String(format: "%.1f", locale: locale, min(250, max(1, radiusKM / 1.852)))
        let base = self == .adsbLOL ? "https://api.adsb.lol/v2/point/\(lat)/\(lon)/\(nm)"
            : "https://opendata.adsb.fi/api/v3/lat/\(lat)/lon/\(lon)/dist/\(nm)"
        return URL(string: base)!
    }
}

public struct SourceIssue: Codable, Sendable, Hashable {
    public var source: PositionSource
    public var code: Int?
    public var retryAt: Date
    public func message(in language: AppLanguage) -> String {
        source.title + ": " + (code.map { "HTTP \($0)" } ?? language.text("Quelle nicht erreichbar"))
            + " · " + language.text("Nächster Abruf") + " "
            + retryAt.formatted(.dateTime.hour().minute().second().locale(language.locale))
    }
}

public struct PositionUnavailable: Error, Sendable {
    public var issues: [SourceIssue]
    public func message(in language: AppLanguage) -> String {
        issues.map { $0.message(in: language) }.joined(separator: "\n")
    }
}

public struct SourceCooldown: Codable, Sendable {
    public var failures = 0
    public var until = Date.distantPast
    public var code: Int? = nil
    public init() {}
    public mutating func fail(at date: Date, code: Int?, retryAfter: Date?, jitter: Double = 0) {
        failures = min(10, failures + 1)
        self.code = code
        let backoff = min(300, 30 * pow(2, Double(failures - 1)))
        // Retry-After is authoritative, including values longer than our backoff cap.
        until = max(date.addingTimeInterval(backoff + max(0, min(5, jitter))), retryAfter ?? date)
        if let code, [400, 401, 403, 404].contains(code) { until = max(until, date.addingTimeInterval(900)) }
    }
}

public enum PositionTime {
    public static func date(_ value: Double?, fetchedAt: Date) -> Date? {
        guard let value, value.isFinite else { return nil }
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        let date = Date(timeIntervalSince1970: seconds)
        guard seconds >= 1_577_836_800, date.timeIntervalSince(fetchedAt) <= 5,
              fetchedAt.timeIntervalSince(date) <= 90 else { return nil }
        return date
    }
    public static func retryAfter(_ value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return now.addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}

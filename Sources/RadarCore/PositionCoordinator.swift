import Foundation

/// One queue per process. App and extension intentionally have separate sandboxes.
public actor PositionCoordinator {
    public static let shared = PositionCoordinator()
    public typealias Fetch = @Sendable (PositionSource, GeoPoint, Double) async throws -> RadarSnapshot
    private let fetch: Fetch
    private let clock: @Sendable () -> Date
    private let spacing: TimeInterval
    private let persist: Bool
    private var cooldowns: [String: SourceCooldown]
    private var inFlight: (id: UUID, key: String, task: Task<RadarSnapshot, any Error>)?
    private var lastResult: [String: RadarSnapshot] = [:]
    private var lastRequest = Date.distantPast

    public init(api: RadarAPI = .shared, persist: Bool = true, spacing: TimeInterval = 1.1,
                clock: @escaping @Sendable () -> Date = { Date() }, fetch: Fetch? = nil) {
        self.fetch = fetch ?? { source, center, radius in
            try await api.positions(source: source, center: center, radiusKM: radius)
        }
        self.clock = clock; self.spacing = spacing; self.persist = persist
        if persist, let data = UserDefaults.standard.data(forKey: "skynear.source-cooldowns.v1"),
           let stored = try? JSONDecoder().decode([String: SourceCooldown].self, from: data) {
            cooldowns = stored
        } else { cooldowns = [:] }
    }

    public func snapshot(center: GeoPoint, radiusKM: Double, minimumInterval: TimeInterval = 20) async throws -> RadarSnapshot {
        try Task.checkCancellation()
        let key = PositionSource.adsbLOL.url(center: center, radiusKM: radiusKM).absoluteString
        if let cached = lastResult[key], clock().timeIntervalSince(cached.fetchedAt) < minimumInterval {
            RadarDiagnostics.record("position success cache")
            return cached
        }
        if let running = inFlight {
            if running.key == key {
                RadarDiagnostics.record("position request coalesced")
                let value = try await running.task.value
                try Task.checkCancellation()
                return value
            }
            // A different map scope waits for the queue; it cannot start a parallel fetch.
            _ = try? await running.task.value
            try Task.checkCancellation()
            if inFlight?.id == running.id { inFlight = nil }
            return try await snapshot(center: center, radiusKM: radiusKM, minimumInterval: minimumInterval)
        }
        let id = UUID()
        let task = Task { try await self.perform(center: center, radiusKM: radiusKM) }
        inFlight = (id, key, task)
        defer { if inFlight?.id == id { inFlight = nil } }
        let result = try await task.value
        if lastResult.count > 20 { lastResult.removeAll() }
        lastResult[key] = result
        try Task.checkCancellation()
        return result
    }

    private func perform(center: GeoPoint, radiusKM: Double) async throws -> RadarSnapshot {
        var issues: [SourceIssue] = []
        for source in PositionSource.allCases {
            var cooldown = cooldowns[source.rawValue] ?? SourceCooldown()
            if cooldown.until > clock() {
                RadarDiagnostics.record("source cooldown \(source.title) until=\(RadarDiagnostics.stamp(cooldown.until)) http=\(cooldown.code ?? 0)")
                issues.append(SourceIssue(source: source, code: cooldown.code, retryAt: cooldown.until))
                continue
            }
            let wait = spacing - clock().timeIntervalSince(lastRequest)
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            lastRequest = clock()
            do {
                RadarDiagnostics.record("source request \(source.title)")
                var value = try await fetch(source, center, radiusKM)
                try Task.checkCancellation()
                cooldowns[source.rawValue] = SourceCooldown()
                saveCooldowns()
                value.source = source
                value.sourceIssues = issues
                RadarDiagnostics.record("source success \(source.title) planes=\(value.planes.count) real=\(value.dataDate.timeIntervalSince1970)")
                return value // An empty success is authoritative; do not query or merge old planes.
            } catch is CancellationError { throw CancellationError() }
            catch {
                RadarDiagnostics.record("source failure \(source.title) code=\((error as NSError).code)")
                var code: Int?
                var retry: Date?
                if let error = error as? RadarError {
                    switch error {
                    case .http(let value): code = value
                    case .rateLimited(let value, let date): code = value; retry = date
                    case .deferred: throw error
                    default: break
                    }
                }
                cooldown.fail(at: clock(), code: code, retryAfter: retry, jitter: Double.random(in: 0...3))
                RadarDiagnostics.record("source backoff \(source.title) http=\(code ?? 0) until=\(RadarDiagnostics.stamp(cooldown.until))")
                cooldowns[source.rawValue] = cooldown
                saveCooldowns()
                issues.append(SourceIssue(source: source, code: code, retryAt: cooldown.until))
            }
        }
        throw PositionUnavailable(issues: issues)
    }

    private func saveCooldowns() {
        guard persist, let data = try? JSONEncoder().encode(cooldowns) else { return }
        UserDefaults.standard.set(data, forKey: "skynear.source-cooldowns.v1")
    }
}

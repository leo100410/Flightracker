import Foundation
import WidgetKit
import RadarCore

private actor WidgetLoadRace {
    private var result: WidgetLoad?
    private var continuation: CheckedContinuation<WidgetLoad, Never>?
    func finish(_ value: WidgetLoad) {
        guard result == nil else { return }
        result = value
        continuation?.resume(returning: value); continuation = nil
    }
    func value() async -> WidgetLoad {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
}

struct WidgetLoad: Sendable {
    var real: RadarSnapshot?
    var issues: [SourceIssue] = []
    var locationMessage: String?
    var predict = false
    var outdated = false
    var predictionDeadline: Date?
    var savedLocationAt: Date?
    var diagnosticAt: Date?
    var diagnosticStatus = "Kein Abruf"
    var diagnosticURL: URL?
    func snapshot(at date: Date) -> RadarSnapshot? {
        guard let real else { return nil }
        return real.displayed(at: date)
    }
    func message(in language: AppLanguage, at date: Date) -> String? {
        let status = statusMessage(in: language, at: date)
        guard let savedLocationAt else { return status }
        return [status, language.text("Letzter Standort") + " · " + savedLocationAt.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · ")
    }
    private func statusMessage(in language: AppLanguage, at date: Date) -> String? {
        if let locationMessage { return language.text(locationMessage) }
        if real?.planes.isEmpty == false, snapshot(at: date)?.planes.isEmpty == true {
            return language.text("Prognose beendet") + " · " + issues.map { $0.message(in: language) }.joined(separator: " · ")
        }
        if !issues.isEmpty { return issues.map { $0.message(in: language) }.joined(separator: " · ") }
        return nil
    }
}
// Same filename and optional model additions keep the previous v1 cache readable.
actor PositionCache {
    static let shared = PositionCache()
    private var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("skynear-widget-positions-v1.json")
    }
    func save(_ snapshot: RadarSnapshot) {
        SharedWidgetStorage.publish(snapshot)
        guard let url else { return }
        if let old = load(), old.dataDate > snapshot.dataDate ||
            (old.dataDate == snapshot.dataDate && old.fetchedAt > snapshot.fetchedAt) { return }
        var positions = snapshot
        positions.planes = snapshot.planes.map {
            var plane = $0
            // Keep bounded reference data/photos so an outage does not erase useful details.
            if let data = plane.photoData, data.count > 100_000 { plane.photoData = nil }
            return plane
        }
        do {
            let data = try JSONEncoder().encode(positions)
            try data.write(to: url, options: .atomic)
            RadarDiagnostics.record("widget position cache saved")
        } catch { RadarDiagnostics.record("widget position cache write failed \(RadarDiagnostics.errorCode(error))") }
    }
    func load() -> RadarSnapshot? {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(RadarSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.fetchedAt) >= 0,
              Date().timeIntervalSince(snapshot.fetchedAt) < 1800 else { return nil }
        return snapshot
    }
}
actor WidgetRadarData {
    static let shared = WidgetRadarData()
    private let api: RadarAPI
    private let coordinator: PositionCoordinator
    private var task: Task<WidgetLoad, Never>?
    private var recent: WidgetLoad?
    private var enrichment: Task<Void, Never>?
    private var provisional = WidgetLoad(real: nil, locationMessage: "Widget-Abruf hat zu lange gedauert. App öffnen und erneut versuchen.")
    init() {
        let api = RadarAPI(requestTimeout: 4, resourceTimeout: 5)
        self.api = api
        coordinator = PositionCoordinator(api: api)
    }
    func load() async -> WidgetLoad {
        RadarDiagnostics.record("shared storage \(SharedWidgetStorage.inspect(process: "widget"))")
        RadarDiagnostics.record("widget provider load")
        if let task { RadarDiagnostics.record("widget coalesced"); return await task.value }
        let operation = Task { await self.diagnosedFetch() }
        task = operation
        let value = await operation.value
        recent = value; task = nil
        return value
    }
    private func diagnosedFetch() async -> WidgetLoad {
        let value = await boundedFetch()
        var result = value
        result.diagnosticAt = Date()
        if value.locationMessage != nil { result.diagnosticStatus = "Fehler/Timeout" }
        else if value.outdated { result.diagnosticStatus = "Quellenfehler" }
        else if let real = value.real {
            result.diagnosticStatus = value.diagnosticStatus == "Cache" ? "Cache" : (Date().timeIntervalSince(real.fetchedAt) < 60 ? "Abruf OK" : "Alte Daten")
        } else { result.diagnosticStatus = "Keine Daten" }
        RadarDiagnostics.record("widget load finished status=\(result.diagnosticStatus) fetched=\(RadarDiagnostics.stamp(result.real?.fetchedAt)) real=\(RadarDiagnostics.stamp(result.real?.dataDate)) issues=\(result.issues.count)")
        return result
    }
    private func boundedFetch() async -> WidgetLoad {
        let disk = await PositionCache.shared.load()
        let cached = SharedPositionStore.newest([recent?.real, disk, SharedWidgetStorage.positions?.load()])
        provisional = WidgetLoad(real: cached,
            locationMessage: "Widget-Abruf hat zu lange gedauert. App öffnen und erneut versuchen.", outdated: cached != nil)
        let race = WidgetLoadRace()
        let work = Task { await race.finish(self.fetch()) }
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(16)) }
            catch { return }
            RadarDiagnostics.record("widget timeout")
            await race.finish(self.provisional)
        }
        let value = await race.value()
        work.cancel(); deadline.cancel()
        return value
    }
    private func fetch() async -> WidgetLoad {
        let disk = await PositionCache.shared.load()
        var cached = SharedPositionStore.newest([recent?.real, disk, SharedWidgetStorage.positions?.load()])
        var savedLocationAt: Date?
        do {
            let point: GeoPoint
            RadarDiagnostics.record("widget location begin")
            do { point = try await WidgetLocationRequest.current(timeout: 4); RadarDiagnostics.record("widget location success") }
            catch is CancellationError { throw CancellationError() }
            catch {
                guard let saved = LocationMemory.load() else {
                    RadarDiagnostics.record("widget location failure no fallback \(RadarDiagnostics.errorCode(error))")
                    throw error
                }
                RadarDiagnostics.record("widget location fallback measured=\(RadarDiagnostics.stamp(saved.measuredAt))")
                point = saved.point; savedLocationAt = saved.measuredAt
            }
            try Task.checkCancellation()
            cached = SharedPositionStore.newest([recent?.real, disk, SharedWidgetStorage.positions?.load()], center: point)
            provisional.savedLocationAt = savedLocationAt
            provisional.real = cached
            if let cached, WidgetRefreshPolicy.canReuse(cached, at: Date(), center: point) {
                RadarDiagnostics.record("widget success cache fetched=\(RadarDiagnostics.stamp(cached.fetchedAt)) real=\(RadarDiagnostics.stamp(cached.dataDate))")
                var value = WidgetLoad(real: cached, issues: cached.sourceIssues ?? [], savedLocationAt: savedLocationAt)
                value.diagnosticStatus = "Cache"
                return value
            }
            var value = try await coordinator.snapshot(center: point, radiusKM: 463, minimumInterval: 60)
            try Task.checkCancellation()
            // The extension displays at most five planes; avoid retaining a whole regional feed.
            value.planes = value.nearest(to: point, count: 20)
            if let cached {
                let old = Dictionary(uniqueKeysWithValues: cached.planes.map { ($0.id, $0) })
                value.planes = value.planes.map { fresh in
                    guard let previous = old[fresh.id], previous.callsign == fresh.callsign else { return fresh }
                    var result = fresh
                    result.metadata = previous.metadata; result.photoData = previous.photoData
                    result.modelPhotoCode = previous.modelPhotoCode
                    return result
                }
            }
            value.planes = value.planes.map { plane in
                var result = plane
                if result.photoData == nil, let photo = ModelPhotos.reference(for: plane) {
                    result.photoData = photo.data; result.modelPhotoCode = photo.code
                }
                return result
            }
            RadarDiagnostics.record("widget positions accepted count=\(value.planes.count) real=\(RadarDiagnostics.stamp(value.dataDate))")
            await PositionCache.shared.save(value) // Commit real/empty results before optional enrichment.
            try Task.checkCancellation()
            provisional = WidgetLoad(real: value, issues: value.sourceIssues ?? [], savedLocationAt: savedLocationAt)
            // Optional work never delays a successful position timeline.
            enrichment?.cancel()
            let positions = value
            enrichment = Task {
                RadarDiagnostics.record("widget enrichment begin")
                guard let enriched = try? await api.enrichSnapshot(positions, at: point, photos: true),
                      !Task.isCancelled else { return }
                RadarDiagnostics.record("widget enrichment success")
                await PositionCache.shared.save(enriched)
                if recent?.real?.fetchedAt == enriched.fetchedAt { recent?.real = enriched }
            }
            return provisional
        } catch let failure as PositionUnavailable {
            let now = Date()
            let deadline = cached.flatMap { PositionPrediction.timelineDates(for: $0, from: now).last }
            return WidgetLoad(real: cached, issues: failure.issues, predict: true, outdated: true,
                              predictionDeadline: deadline, savedLocationAt: savedLocationAt)
        } catch is CancellationError {
            return provisional
        } catch {
            let message = (error as? RadarError).flatMap { value -> String? in
                if case .location(let text) = value { return text }
                return nil
            } ?? "Widget-Abruf fehlgeschlagen. App öffnen und erneut versuchen."
            return WidgetLoad(real: cached, locationMessage: message, outdated: cached != nil, savedLocationAt: savedLocationAt)
        }
    }
}
enum WidgetDates {
    static func entries(for load: WidgetLoad, now: Date) -> [Date] {
        RadarDiagnostics.record("widget timeline real=\(load.real?.dataDate.timeIntervalSince1970 ?? 0) display=\(now.timeIntervalSince1970)")
        guard let real = load.real else { return [now] }
        return PositionPrediction.timelineDates(for: real, from: now)
    }
}

// Captured once per provider result, shared by its forecast entries. No file I/O in views.
extension WidgetLoad {
    func diagnosed(provider: String, entryCount: Int, next: Date?) -> WidgetLoad {
        var value = self
        value.diagnosticAt = Date()
        RadarDiagnostics.record("provider \(provider) timeline ready entries=\(entryCount) nextRequested=\(RadarDiagnostics.stamp(next)) real=\(RadarDiagnostics.stamp(real?.dataDate))")
        value.diagnosticURL = RadarDiagnostics.widgetTransferURL()
        return value
    }
}

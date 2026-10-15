import Foundation
import Combine
import CoreLocation
import ActivityKit
import WidgetKit
import RadarCore

@MainActor
final class RadarStore: ObservableObject {
    @Published private(set) var snapshot: RadarSnapshot?
    @Published private(set) var nearby: RadarSnapshot?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var nearbyError: String?
    @Published private(set) var liveError: String?
    @Published private(set) var liveRunning = false
    @Published private(set) var liveActionInProgress = false
    @Published private(set) var liveStatus: String?
    @Published var radiusKM: Double = UserDefaults.standard.object(forKey: "skynear.radius.v1") as? Double ?? 150
    @Published var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "skynear.language.v1") ?? "de") ?? .de {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "skynear.language.v1")
            renderPositions()
            Task { await updateLive() }
        }
    }
    let location = AppLocation()
    private var realMap: RadarSnapshot?
    private var realNearby: RadarSnapshot?
    private var mapIssues: [SourceIssue] = []
    private var nearbyIssues: [SourceIssue] = []
    private var mapUnavailable = false
    private var nearbyUnavailable = false
    private var mapCenter: GeoPoint?
    private var revision = 0
    private var refreshTask: Task<Void, Never>?
    private var activityID: String?
    private var liveUpdateInProgress = false
    private var liveActionToken: UUID?
    private var endingActivityIDs = Set<String>()
    private var lastWidgetReload = Date.distantPast
    private var locationSubscription: AnyCancellable?
    private var active = false
    private var lastAttempt = Date.distantPast
    private var lastNearbyAttempt = Date.distantPast
    private var liveFailureKey: String?
    private var lastLiveState: NearbyActivityAttributes.ContentState?

    init() {
        activityID = Activity<NearbyActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }?.id
        liveRunning = activityID != nil
        locationSubscription = location.$point.sink { [weak self] point in
            guard let self, let point else { return }
            if self.mapCenter == nil { self.mapCenter = point }
            self.renderPositions()
        }
    }
    func activate() {
        guard !active else { return }
        reconcileLiveState()
        AppDiagnostics.capture("activate")
        active = true; location.start(); restartLoop()
    }
    func deactivate() {
        RadarDiagnostics.record("app foreground loop stopping")
        active = false; refreshTask?.cancel(); refreshTask = nil; location.stop()
    }
    func setCenter(_ point: GeoPoint) {
        if let old = mapCenter, old.distance(to: point) < 3 { return }
        mapCenter = point; revision += 1
        requestRefresh()
    }
    func centerOnMe() {
        guard let point = location.point else { location.start(); return }
        mapCenter = point; revision += 1; requestRefresh()
    }
    func changeRadius() {
        UserDefaults.standard.set(radiusKM, forKey: "skynear.radius.v1")
        revision += 1; renderPositions(); requestRefresh()
    }
    // Triggers no longer cancel/restart an active network request or reset its budget.
    func restartLoop() {
        guard active else { return }
        if refreshTask != nil { requestRefresh(); return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                self.renderPositions()
                await self.updateLive()
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }
    private func requestRefresh() {
        guard active else { return }
        Task { await refresh() }
    }
    func refresh() async {
        guard active, !loading, Date().timeIntervalSince(lastAttempt) >= 20,
              let center = mapCenter ?? location.point else { return }
        RadarDiagnostics.record("app refresh begin")
        lastAttempt = Date(); loading = true
        defer { loading = false; RadarDiagnostics.record("app refresh finished cancelled=\(Task.isCancelled)") }
        let generation = revision
        let radius = radiusKM
        let user = location.point
        let sameArea = user.map { center.distance(to: $0) < 5 } ?? false
        do {
            var value = try await PositionCoordinator.shared.snapshot(center: sameArea ? (user ?? center) : center,
                                                                       radiusKM: sameArea ? 463 : radius)
            try Task.checkCancellation()
            value = preserveMetadata(value, previous: sameArea ? realNearby : realMap)
            guard active else { return }
            if sameArea, let user, location.point.map({ $0.distance(to: user) < 3 }) == true {
                acceptNearby(value); lastNearbyAttempt = Date()
            }
            if revision == generation { acceptMap(value) }
            renderPositions() // Real positions immediately replace estimates, before metadata requests.
            await updateLive()
            value = try await RadarAPI.shared.enrichSnapshot(value, at: sameArea ? user : nil)
            try Task.checkCancellation()
            guard active else { return }
            if sameArea, let user, location.point.map({ $0.distance(to: user) < 3 }) == true {
                acceptNearby(value); lastNearbyAttempt = Date()
            }
            if revision == generation {
                // Retain the full real response; rendering applies the chosen map radius.
                acceptMap(value)
            }
        } catch is CancellationError { return }
        catch let failure as PositionUnavailable {
            if generation == revision { mapIssues = failure.issues; mapUnavailable = true }
            if sameArea { nearbyIssues = failure.issues; nearbyUnavailable = true; lastNearbyAttempt = Date() }
        } catch {
            if !Task.isCancelled, generation == revision { self.error = localized(error) }
        }
        // A failed distant-map query must not prevent the independent local overview.
        if !sameArea, let user, Date().timeIntervalSince(lastNearbyAttempt) >= 60 {
            lastNearbyAttempt = Date()
            do {
                var local = try await PositionCoordinator.shared.snapshot(center: user, radiusKM: 463)
                local = preserveMetadata(local, previous: realNearby)
                if active, location.point.map({ $0.distance(to: user) < 3 }) == true {
                    acceptNearby(local); renderPositions(); await updateLive()
                }
                local = try await RadarAPI.shared.enrichSnapshot(local, at: user)
                try Task.checkCancellation()
                if active, location.point.map({ $0.distance(to: user) < 3 }) == true { acceptNearby(local) }
            } catch is CancellationError { return }
            catch let failure as PositionUnavailable { nearbyIssues = failure.issues; nearbyUnavailable = true }
            catch { nearbyError = localized(error) }
        }
        renderPositions()
        await updateLive()
    }
    private func acceptMap(_ value: RadarSnapshot) {
        guard realMap.map({ value.dataDate >= $0.dataDate }) ?? true else { return }
        realMap = value; mapUnavailable = false; mapIssues = value.sourceIssues ?? []; error = nil
    }
    private func acceptNearby(_ value: RadarSnapshot) {
        guard realNearby.map({ value.dataDate >= $0.dataDate }) ?? true else { return }
        realNearby = value; nearbyUnavailable = false; nearbyIssues = value.sourceIssues ?? []; nearbyError = nil
        RadarDiagnostics.record("app nearby accepted real=\(RadarDiagnostics.stamp(value.dataDate)) count=\(value.planes.count)")
        BackgroundRefresh.save(value)
        // Request only after positions are committed, before optional enrichment can stall.
        if Date().timeIntervalSince(lastWidgetReload) >= 60 {
            RadarDiagnostics.record("widget reload requested by foreground real=\(RadarDiagnostics.stamp(value.dataDate))")
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetReload = Date()
        }
    }
    private func preserveMetadata(_ value: RadarSnapshot, previous: RadarSnapshot?) -> RadarSnapshot {
        guard let previous else { return value }
        let byID = Dictionary(uniqueKeysWithValues: previous.planes.map { ($0.id, $0) })
        var result = value
        result.planes = value.planes.map { fresh in
            guard let old = byID[fresh.id], old.callsign == fresh.callsign else { return fresh }
            var merged = fresh
            if let oldTime = old.positionAt, let newTime = fresh.positionAt, newTime < oldTime { merged = old }
            merged.metadata = old.metadata
            merged.photoData = old.photoData
            merged.modelPhotoCode = old.modelPhotoCode
            return merged
        }
        return result
    }
    private func renderPositions() {
        let now = Date()
        if let realMap {
            var visible = realMap.displayed(at: now)
            if let center = mapCenter, center.distance(to: realMap.center) + radiusKM <= realMap.radiusKM + 1 {
                visible.center = center; visible.radiusKM = radiusKM
                visible.planes = visible.planes.filter { center.distance(to: $0.point) <= radiusKM }
            }
            snapshot = visible
        }
        if let realNearby { nearby = realNearby.displayed(at: now) }
        if !mapIssues.isEmpty { error = mapIssues.map { $0.message(in: language) }.joined(separator: "\n") }
        if !nearbyIssues.isEmpty { nearbyError = nearbyIssues.map { $0.message(in: language) }.joined(separator: "\n") }
        if let key = liveFailureKey { liveError = language.text(key) }
    }
    private func localized(_ error: any Error) -> String {
        (error as? RadarError)?.message(in: language) ?? language.text("Quelle nicht erreichbar")
    }
    func currentPlane(id: String) -> Plane? {
        let candidates = [nearby?.planes.first { $0.id == id }, snapshot?.planes.first { $0.id == id }].compactMap { $0 }
        return candidates.max { lhs, rhs in
            if lhs.isEstimated != rhs.isEstimated { return lhs.isEstimated }
            return (lhs.positionAt ?? .distantPast) < (rhs.positionAt ?? .distantPast)
        }
    }
    func details(for plane: Plane) async -> Plane {
        return await RadarAPI.shared.enrich(plane, photo: true)
    }
    private func activityState(_ nearby: RadarSnapshot, user: GeoPoint) -> NearbyActivityAttributes.ContentState {
        let issues = nearbyUnavailable ? nearbyIssues : (nearby.sourceIssues ?? [])
        let shortErrors = issues.map { issue in
            issue.source.title + ": " + (issue.code.map { "HTTP \($0)" } ?? language.text("Quelle nicht erreichbar"))
        }.joined(separator: " · ")
        let predictionStatus = nearby.isEstimated ? language.text("Geschätzt") : ""
        let status = [predictionStatus, shortErrors].filter { !$0.isEmpty }.joined(separator: " · ")
        return NearbyActivityAttributes.ContentState(updated: nearby.dataDate,
            rows: nearby.nearest(to: user).map { ActivityRow(plane: $0, origin: user, language: language) },
            language: language, source: nearby.source, estimated: nearby.isEstimated,
            validUntil: nearby.nearest(to: user).map { PositionPrediction.expiry(of: $0, fetchedAt: nearby.fetchedAt) }.min() ?? Date(),
            status: status.isEmpty ? nil : String(status.prefix(100)))
    }
    func toggleLive() async {
        guard !liveActionInProgress else {
            liveError = language.text("Live-Activity-Aktion läuft bereits. Bitte kurz warten.")
            return
        }
        reconcileLiveState()
        let token = UUID()
        liveActionToken = token; liveActionInProgress = true
        let watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.liveActionToken == token else { return }
            self.liveActionInProgress = false; self.liveActionToken = nil
            self.liveError = self.language.text("ActivityKit hat nicht rechtzeitig geantwortet. Erneut versuchen.")
        }
        defer {
            watchdog.cancel()
            if liveActionToken == token { liveActionToken = nil; liveActionInProgress = false }
        }
        liveError = nil; liveFailureKey = nil; liveStatus = nil
        if let id = activityID {
            // Clear the cached ID before awaiting the OS so a failed/stalled end cannot lock out start.
            activityID = nil; liveRunning = false; lastLiveState = nil
            endingActivityIDs.insert(id)
            let ended = await LiveActivityOperations.end(id: id)
            endingActivityIDs.remove(id)
            guard liveActionToken == token else { return }
            liveStatus = language.text(ended ? "Live Activity beendet." : "Die bisherige Live Activity war bereits beendet.")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveFailureKey = "Live Activities sind nicht erlaubt. In den iPhone-Einstellungen aktivieren."
            renderPositions(); return
        }
        guard let user = location.point else {
            liveFailureKey = "Kein Gerätestandort für die Live Activity verfügbar."
            renderPositions(); return
        }
        renderPositions()
        guard let nearby, !nearby.nearest(to: user).isEmpty else {
            liveFailureKey = "Keine aktuellen Flugzeuge für die Live Activity verfügbar. Zuerst die Umgebung laden."
            renderPositions(); return
        }
        do {
            let state = activityState(nearby, user: user)
            let attributes = NearbyActivityAttributes(title: "SkyNear")
            let bytes = try JSONEncoder().encode(state).count + JSONEncoder().encode(attributes).count
            guard bytes <= 4096 else {
                liveError = "\(language.text("Live-Activity-Daten sind zu groß")): \(bytes) / 4096 bytes"
                return
            }
            let activity = try Activity<NearbyActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.staleAt),
                pushType: nil
            )
            guard activity.activityState == .active || activity.activityState == .stale else {
                liveError = "\(language.text("ActivityKit hat die Live Activity sofort beendet")): \(String(describing: activity.activityState))"
                return
            }
            activityID = activity.id
            liveRunning = true
            lastLiveState = state
            liveStatus = language.text("Live Activity vom System angenommen. Auf Sperrbildschirm oder Dynamic Island prüfen.")
        } catch {
            activityID = nil; liveRunning = false; lastLiveState = nil
            let concrete = error as NSError
            liveError = "Activity.request: \(concrete.domain) (\(concrete.code)) · \(concrete.localizedDescription)"
            if let reason = concrete.localizedFailureReason { liveError = (liveError ?? "") + " · " + reason }
        }
    }
    private func reconcileLiveState() {
        let visible = Activity<NearbyActivityAttributes>.activities.filter {
            !endingActivityIDs.contains($0.id) && ($0.activityState == .active || $0.activityState == .stale)
        }
        if let id = activityID, !visible.contains(where: { $0.id == id }) {
            activityID = nil; lastLiveState = nil
        }
        if activityID == nil { activityID = visible.first?.id }
        liveRunning = activityID != nil
    }
    private func updateLive() async {
        guard !liveActionInProgress, !liveUpdateInProgress,
              let id = activityID, let nearby, let user = location.point else { return }
        liveUpdateInProgress = true
        defer { liveUpdateInProgress = false }
        let state = activityState(nearby, user: user)
        guard state != lastLiveState else { return }
        let stillActive = await LiveActivityOperations.update(id: id, state: state,
            staleDate: state.staleAt)
        guard activityID == id else { return } // A late update must not change a newer start/stop action.
        if !stillActive { activityID = nil; liveRunning = false; lastLiveState = nil }
        else { lastLiveState = state }
    }
}

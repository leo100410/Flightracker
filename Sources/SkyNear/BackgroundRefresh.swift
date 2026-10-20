#if os(iOS)
import Foundation
import BackgroundTasks
import UIKit
import ActivityKit
import WidgetKit
import RadarCore

@MainActor
enum BackgroundRefresh {
    static var permittedIdentifiers: [String] {
        Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
    }
    static var modes: [String] {
        Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    }
    // Some signing tools rename the bundle and permitted task IDs together.
    // The SwiftUI handler and submitted request must use the same installed identifier.
    static let identifier: String = {
        let installed = (Bundle.main.bundleIdentifier ?? "de.leola.skynear") + ".refresh"
        if permittedIdentifiers.contains(installed) { return installed }
        if permittedIdentifiers.contains("de.leola.skynear.refresh") { return "de.leola.skynear.refresh" }
        let candidates = permittedIdentifiers.filter { $0.hasSuffix(".refresh") }
        return candidates.count == 1 ? candidates[0] : installed
    }()
    static func inspectConfiguration() {
        RadarDiagnostics.record("background installed bundle=\(Bundle.main.bundleIdentifier ?? "none") task=\(identifier) permitted=\(permittedIdentifiers.joined(separator: ",")) modes=\(modes.joined(separator: ",")) valid=\(permittedIdentifiers.contains(identifier) && modes.contains("fetch"))")
    }
    private static var transitionTask: Task<Void, Never>?
    private static var transitionID: UIBackgroundTaskIdentifier = .invalid
    private static var running = false
    private static var scheduling = false
    private static var transitionGeneration = UUID()
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("skynear-background-positions-v1.json")
    }
    static func save(_ snapshot: RadarSnapshot) {
        SharedWidgetStorage.publish(snapshot)
        guard let url = cacheURL else { return }
        if let old = load(), old.dataDate > snapshot.dataDate { return }
        var value = snapshot
        value.planes = snapshot.nearest(to: snapshot.center, count: 20).map {
            var plane = $0; plane.photoData = nil; return plane
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func load() -> RadarSnapshot? {
        let local = cacheURL.flatMap { url -> RadarSnapshot? in
            guard let data = try? Data(contentsOf: url),
                  let value = try? JSONDecoder().decode(RadarSnapshot.self, from: data),
                  (0..<1800).contains(Date().timeIntervalSince(value.fetchedAt)) else { return nil }
            return value
        }
        return SharedPositionStore.newest([local, SharedWidgetStorage.positions?.load()])
    }
    static func schedule() {
        inspectConfiguration()
        guard !scheduling else { RadarDiagnostics.record("background schedule coalesced"); return }
        scheduling = true
        Task { @MainActor in
            defer { scheduling = false }
            let pending = await BGTaskScheduler.shared.pendingTaskRequests()
            if let existing = pending.first(where: { $0.identifier == identifier }) {
                RadarDiagnostics.record("background schedule retained earliest=\(RadarDiagnostics.stamp(existing.earliestBeginDate))")
                return
            }
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
            do {
                try BGTaskScheduler.shared.submit(request)
                RadarDiagnostics.record("background schedule submitted earliest=\(RadarDiagnostics.stamp(request.earliestBeginDate))")
                let confirmed = await BGTaskScheduler.shared.pendingTaskRequests().first { $0.identifier == identifier }
                RadarDiagnostics.record("background submission verification pending=\(confirmed != nil) earliest=\(RadarDiagnostics.stamp(confirmed?.earliestBeginDate))")
                UserDefaults.standard.removeObject(forKey: "skynear.background-error.v1")
            } catch {
                RadarDiagnostics.record("background schedule rejected \(RadarDiagnostics.errorCode(error))")
                let concrete = error as NSError
                UserDefaults.standard.set("\(concrete.domain) (\(concrete.code)): \(concrete.localizedDescription)",
                                          forKey: "skynear.background-error.v1")
            }
        }
    }
    // One bounded update when leaving the app, not a continuous background loop.
    static func leavingForeground() {
        AppDiagnostics.capture("leaving foreground")
        schedule()
        guard transitionTask == nil else { return }
        let generation = UUID()
        transitionGeneration = generation
        transitionID = UIApplication.shared.beginBackgroundTask(withName: "SkyNear positions") {
            Task { @MainActor in
                guard transitionGeneration == generation else { return }
                RadarDiagnostics.record("transition system expiration")
                transitionTask?.cancel(); finishTransition(generation)
            }
        }
        guard transitionID != .invalid else { RadarDiagnostics.record("transition background time denied"); return }
        RadarDiagnostics.record("transition background time granted")
        transitionTask = Task { @MainActor in
            let deadline = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard transitionGeneration == generation else { return }
                RadarDiagnostics.record("transition deadline 20s")
                transitionTask?.cancel()
            }
            await perform(trigger: "leaving-foreground")
            deadline.cancel(); finishTransition(generation)
        }
    }
    private static func finishTransition(_ generation: UUID) {
        guard transitionGeneration == generation else { return }
        RadarDiagnostics.record("transition finished")
        let id = transitionID
        transitionID = .invalid; transitionTask = nil
        if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
    }
    static func perform(trigger: String = "scheduled") async {
        AppDiagnostics.capture("background \(trigger)")
        RadarDiagnostics.record("background execution begin trigger=\(trigger)")
        schedule()
        guard !running else { RadarDiagnostics.record("background skipped already-running"); return }
        guard !Task.isCancelled else { RadarDiagnostics.record("background skipped cancelled"); return }
        guard let saved = LocationMemory.load() else { RadarDiagnostics.record("background skipped no-location"); return }
        RadarDiagnostics.record("background saved-location measured=\(RadarDiagnostics.stamp(saved.measuredAt))")
        running = true
        defer { running = false; RadarDiagnostics.record("background execution finished cancelled=\(Task.isCancelled)") }
        let activityIDs = Set(Activity<NearbyActivityAttributes>.activities.map(\.id))
        var real = load()
        var errorStatus: String?
        do {
            var fresh = try await PositionCoordinator.shared.snapshot(center: saved.point, radiusKM: 463, minimumInterval: 0)
            if let previous = real {
                let old = Dictionary(uniqueKeysWithValues: previous.planes.map { ($0.id, $0) })
                fresh.planes = fresh.planes.map { plane in
                    var value = plane
                    if let match = old[plane.id], match.callsign == plane.callsign { value.metadata = match.metadata }
                    return value
                }
            }
            try Task.checkCancellation()
            save(fresh); real = load() ?? fresh
            RadarDiagnostics.record("background position success real=\(RadarDiagnostics.stamp(fresh.dataDate)) planes=\(fresh.planes.count)")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "skynear.background-success.v1")
        } catch is CancellationError { RadarDiagnostics.record("background fetch cancelled"); return }
        catch { RadarDiagnostics.record("background fetch failed \(RadarDiagnostics.errorCode(error))"); errorStatus = "Positionsdaten konnten im Hintergrund nicht erneuert werden." }
        guard let real, !Task.isCancelled else { return }
        let display = real.displayed(at: Date())
        let activities = Activity<NearbyActivityAttributes>.activities.filter {
            activityIDs.contains($0.id) && ($0.activityState == .active || $0.activityState == .stale)
        }.map { (id: $0.id, language: $0.content.state.language ?? .de) }
        for activity in activities {
            guard !Task.isCancelled else { return }
            let language = activity.language
            let rows = display.nearest(to: saved.point)
            let deadline = rows.map { PositionPrediction.expiry(of: $0, fetchedAt: real.fetchedAt) }.min() ?? Date()
            let state = NearbyActivityAttributes.ContentState(updated: real.dataDate,
                rows: rows.map { ActivityRow(plane: $0, origin: saved.point, language: language) },
                language: language, source: real.source, estimated: display.isEstimated,
                validUntil: deadline, status: errorStatus == nil ? nil : language.text("Quelle nicht erreichbar"))
            _ = await LiveActivityOperations.update(id: activity.id, state: state, staleDate: state.staleAt)
        }
        RadarDiagnostics.record("widget reload requested by background")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif

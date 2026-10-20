#if os(iOS)
import Foundation
import ActivityKit
import RadarCore

// The UI never sends an Activity reference across an isolation boundary.
// Each operation retrieves its reference locally and only returns value types.
enum LiveActivityOperations {
    static func update(id: String, state: NearbyActivityAttributes.ContentState, staleDate: Date) async -> Bool {
        await LiveActivityQueue.shared.enqueueUpdate(id: id, state: state, staleDate: staleDate)
    }
    static func end(id: String) async -> Bool { await LiveActivityQueue.shared.enqueueEnd(id: id) }
}

private actor LiveActivityQueue {
    static let shared = LiveActivityQueue()
    private var tail: Task<Bool, Never>?
    func enqueueUpdate(id: String, state: NearbyActivityAttributes.ContentState, staleDate: Date) async -> Bool {
        let previous = tail
        let task = Task {
            _ = await previous?.value
            guard !Task.isCancelled else { return false }
            return await Self.update(id: id, state: state, staleDate: staleDate)
        }
        tail = task
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
    func enqueueEnd(id: String) async -> Bool {
        let previous = tail
        let task = Task {
            _ = await previous?.value
            return await Self.end(id: id)
        }
        tail = task
        return await task.value
    }
    @concurrent
    nonisolated static func update(
        id: String,
        state: NearbyActivityAttributes.ContentState,
        staleDate: Date
    ) async -> Bool {
        guard let activity = Activity<NearbyActivityAttributes>.activities.first(where: { $0.id == id }) else {
            RadarDiagnostics.record("live activity unavailable or ended")
            return false
        }
        guard activity.activityState != .ended, activity.activityState != .dismissed else {
            RadarDiagnostics.record("live activity unavailable or ended")
            return false
        }
        guard state.updated >= activity.content.state.updated else { RadarDiagnostics.record("live update rejected older data"); return false }
        RadarDiagnostics.record("live update begin real=\(RadarDiagnostics.stamp(state.updated)) expiry=\(RadarDiagnostics.stamp(staleDate))")
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
        RadarDiagnostics.record("live update returned")
        return true
    }

    @concurrent
    nonisolated static func end(id: String) async -> Bool {
        guard let activity = Activity<NearbyActivityAttributes>.activities.first(where: { $0.id == id }) else {
            RadarDiagnostics.record("live activity unavailable or ended")
            return false
        }
        RadarDiagnostics.record("live end begin")
        await activity.end(nil, dismissalPolicy: .immediate)
        RadarDiagnostics.record("live end returned")
        return true
    }
}
#endif

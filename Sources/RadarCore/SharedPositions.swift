import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Atomic successful-position storage. A suspended writer never blocks a reader.
public struct SharedPositionStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private var file: URL { directory.appendingPathComponent("positions-v1.json") }
    public func load(at now: Date = Date()) -> RadarSnapshot? {
        guard let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(RadarSnapshot.self, from: data),
              (0..<1800).contains(now.timeIntervalSince(value.fetchedAt)),
              value.dataDate <= now.addingTimeInterval(5), !value.isEstimated else { return nil }
        return value
    }
    @discardableResult
    public func save(_ snapshot: RadarSnapshot) throws -> Bool {
        guard !snapshot.isEstimated else { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("positions.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(descriptor, LOCK_UN) }
        if let old = load(), old.dataDate > snapshot.dataDate ||
            (old.dataDate == snapshot.dataDate && old.fetchedAt > snapshot.fetchedAt) { return false }
        var value = snapshot
        value.planes = value.nearest(to: value.center, count: 20).map {
            var plane = $0; plane.photoData = nil; return plane
        }
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        return true
    }
    public static func newest(_ values: [RadarSnapshot?], center: GeoPoint? = nil, at now: Date = Date()) -> RadarSnapshot? {
        values.compactMap { $0 }.filter { value in
            !value.isEstimated && (0..<1800).contains(now.timeIntervalSince(value.fetchedAt)) &&
            value.dataDate <= now.addingTimeInterval(5) &&
            (center.map { value.center.distance(to: $0) < 3 && value.radiusKM >= 460 } ?? true)
        }.max {
            $0.dataDate == $1.dataDate ? $0.fetchedAt < $1.fetchedAt : $0.dataDate < $1.dataDate
        }
    }
}

/// A configured group is optional: signing must actually authorize access on the device.
public enum SharedWidgetStorage {
    public static let group = Bundle.main.object(forInfoDictionaryKey: "SkyNearAppGroup") as? String ?? "group.de.leola.skynear"
    public static let directory: URL? = {
        #if os(iOS)
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let folder = root.appendingPathComponent("SkyNearShared")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let probe = folder.appendingPathComponent("probe-\(UUID().uuidString)")
            let bytes = Data(UUID().uuidString.utf8)
            try bytes.write(to: probe, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            defer { try? FileManager.default.removeItem(at: probe) }
            guard try Data(contentsOf: probe) == bytes else { return nil }
            return folder
        } catch { return nil }
        #else
        return nil
        #endif
    }()
    public static var positions: SharedPositionStore? { directory.map(SharedPositionStore.init) }
    public static func inspect(process: String) -> String {
        guard let directory else { return "unavailable group=\(group)" }
        let peer = process == "app" ? "widget" : "app"
        let own = directory.appendingPathComponent("seen-\(process).txt")
        let other = directory.appendingPathComponent("seen-\(peer).txt")
        do {
            try Data(RadarDiagnostics.stamp(Date()).utf8).write(to: own, options: .atomic)
            let seen = (try? String(contentsOf: other, encoding: .utf8)) ?? "none"
            return "writable group=\(group) peer=\(peer) peerLastSeen=\(seen.prefix(40))"
        } catch { return "probe-failed \(RadarDiagnostics.errorCode(error))" }
    }
    public static func publish(_ snapshot: RadarSnapshot) {
        guard let positions else { return }
        do {
            let saved = try positions.save(snapshot)
            RadarDiagnostics.record("shared positions saved=\(saved) real=\(RadarDiagnostics.stamp(snapshot.dataDate))")
        } catch { RadarDiagnostics.record("shared positions write failed \(RadarDiagnostics.errorCode(error))") }
    }
}

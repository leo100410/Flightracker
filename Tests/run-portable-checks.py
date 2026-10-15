"""Run real model/projection code on Linux, stubbing only unavailable iOS type declarations.
This does not run XCTest, CoreLocation, WidgetKit, ActivityKit, or iPhone behavior.
"""
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
STUBS = r'''
import Foundation
public struct CLLocationCoordinate2D { public var latitude: Double; public var longitude: Double }
public enum RadarDiagnostics {
    public static func record(_ event: String) {}
    public static func errorCode(_ error: any Error) -> String { "test-error" }
    public static func stamp(_ date: Date?) -> String { date.map { String($0.timeIntervalSince1970) } ?? "none" }
}
public actor RadarAPI {
    public static let shared = RadarAPI()
    public func positions(source: PositionSource, center: GeoPoint, radiusKM: Double) async throws -> RadarSnapshot { fatalError("Injected fetch required") }
}
public protocol ActivityAttributes { associatedtype ContentState: Codable, Hashable }
public enum AppLanguage: String, Codable, Sendable {
    case de, en, da
    public var locale: Locale { Locale(identifier: rawValue) }
    public func text(_ value: String) -> String { value }
}
'''
CHECKS = r'''
import Foundation
let now = Date(timeIntervalSince1970: 1_800_000_000)
let raw = try JSONDecoder().decode(LiveAircraft.self, from: Data(#"{"hex":"abc123","t":"A320","lat":0,"lon":179.9,"gs":360,"track":90,"seen_pos":10,"alt_baro":10000}"#.utf8))
let real = raw.plane(responseTime: now, fetchedAt: now)!
let original = RadarSnapshot(fetchedAt: now, center: real.point, radiusKM: 463, planes: [real])
let early = original.displayed(at: now).planes[0]
let later = original.displayed(at: now.addingTimeInterval(60)).planes[0]
precondition(early.isEstimated && later.isEstimated)
precondition(real.point.distance(to: later.point) > real.point.distance(to: early.point))
precondition(later.positionAt == real.positionAt && later.altitudeFeet == real.altitudeFeet && later.speedKnots == real.speedKnots)
precondition(original.planes[0].point == real.point)
precondition(PositionPrediction.plane(later, at: now.addingTimeInterval(100)) == nil)
let crossing = PositionPrediction.destination(from: real.point, speedKnots: 360, course: 90, seconds: 600)!
precondition(crossing.longitude < 0 && abs(real.point.distance(to: crossing) - 111.12) < 0.01)
let dates = PositionPrediction.timelineDates(for: original, from: now)
precondition(dates.count == 16 && dates.contains(now.addingTimeInterval(60)) && dates.last == now.addingTimeInterval(890))
precondition(original.displayed(at: now.addingTimeInterval(890)).planes.isEmpty)
var older = real; older.positionAt = now.addingTimeInterval(-880)
var newer = real; newer.id = "def456"; newer.positionAt = now
let mixed = RadarSnapshot(fetchedAt: now, center: real.point, radiusKM: 463, planes: [older, newer])
precondition(mixed.displayed(at: now.addingTimeInterval(20)).planes.map(\.id) == [newer.id])
precondition(PositionPrediction.timelineDates(for: mixed, from: now).last == now.addingTimeInterval(900))
var ground = real; ground.onGround = true; ground.positionAt = now
precondition(PositionPrediction.displayedPlane(ground, fetchedAt: now, at: now.addingTimeInterval(60))?.isEstimated == false)
precondition(PositionPrediction.displayedPlane(ground, fetchedAt: now, at: now.addingTimeInterval(90)) == nil)
var unknown = real; unknown.track = nil
precondition(PositionPrediction.displayedPlane(unknown, fetchedAt: now, at: now.addingTimeInterval(40))?.isEstimated == false)
var empty = original; empty.planes = []
precondition(empty.displayed(at: now.addingTimeInterval(100)).planes.isEmpty)
let polar = PositionPrediction.destination(from: GeoPoint(latitude: 89.99, longitude: 30), speedKnots: 400, course: 0, seconds: 600)!
precondition(polar.latitude.isFinite && polar.longitude.isFinite)
let behind = GeoPoint(latitude: 0, longitude: 179)
let ahead = GeoPoint(latitude: 0, longitude: -179)
precondition(real.motionLabel(from: behind, language: .en) == "Entfernt sich")
precondition(real.motionLabel(from: ahead, language: .en) == "N\u{00e4}hert sich")
for code in ["B731", "B738", "B38M", "B3XM"] { precondition(AircraftFamily.resolve(code: code) == .b737) }
precondition(AircraftFamily.resolve(code: "A21N") == .a321)
precondition(AircraftFamily.resolve(code: nil, reference: "Airbus A321neo") == .a321)
precondition(AircraftFamily.resolve(code: "A321XYZ") == .generic)
precondition(AircraftFamily.resolve(code: nil, manufacturer: "Boeing") == .boeing)
precondition(AircraftFamily.a319.profile != AircraftFamily.a321.profile)
precondition(AircraftFamily.b717.profile != AircraftFamily.b737.profile)
precondition(real.markerIsGround == later.markerIsGround)
precondition(WidgetRefreshPolicy.canReuse(empty, at: now.addingTimeInterval(59), center: real.point))
precondition(!WidgetRefreshPolicy.canReuse(empty, at: now.addingTimeInterval(60), center: real.point))
precondition(!WidgetRefreshPolicy.canReuse(empty, at: now.addingTimeInterval(-1), center: real.point))
precondition(!WidgetRefreshPolicy.canReuse(empty, at: now, center: behind))
let defaultsKey = "skynear.last-location.v1"
let previousLocation = UserDefaults.standard.data(forKey: defaultsKey)
LocationMemory.save(SavedLocation(point: real.point, measuredAt: Date()))
precondition(LocationMemory.load()?.point == real.point)
LocationMemory.save(SavedLocation(point: GeoPoint(latitude: 91, longitude: 0), measuredAt: Date()))
precondition(LocationMemory.load() == nil)
if let previousLocation { UserDefaults.standard.set(previousLocation, forKey: defaultsKey) }
else { UserDefaults.standard.removeObject(forKey: defaultsKey) }

let activityState = NearbyActivityAttributes.ContentState(updated: now, rows: [], validUntil: now.addingTimeInterval(900))
precondition(activityState.staleAt == now.addingTimeInterval(60))
let shortState = NearbyActivityAttributes.ContentState(updated: now, rows: [], validUntil: now.addingTimeInterval(20))
precondition(shortState.staleAt == now.addingTimeInterval(20))
let storageFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: storageFolder) }
let storage = SharedPositionStore(directory: storageFolder)
let storageNow = Date()
var first = original; first.fetchedAt = storageNow.addingTimeInterval(-20); first.sourceTime = first.fetchedAt
first.planes[0].photoData = Data([1, 2, 3])
let savedFirst = try storage.save(first); precondition(savedFirst)
precondition(storage.load()?.planes.first?.photoData == nil)
var latest = first; latest.fetchedAt = storageNow.addingTimeInterval(-1); latest.sourceTime = latest.fetchedAt; latest.planes = []
let savedLatest = try storage.save(latest); precondition(savedLatest)
let rejectedfirst = try storage.save(first); precondition(!rejectedfirst)
precondition(storage.load()?.planes.isEmpty == true)
precondition(SharedPositionStore.newest([first, latest], center: real.point, at: storageNow)?.planes.isEmpty == true)
precondition(SharedPositionStore.newest([latest], center: behind, at: storageNow) == nil)
precondition(storage.load(at: storageNow.addingTimeInterval(1800)) == nil)
var delayed = latest; delayed.fetchedAt = storageNow; delayed.sourceTime = first.sourceTime
let rejecteddelayed = try storage.save(delayed); precondition(!rejecteddelayed)
var prediction = first; prediction.planes[0].estimatedAt = storageNow
let rejectedprediction = try storage.save(prediction); precondition(!rejectedprediction)
let lockDescriptor = open(storageFolder.appendingPathComponent("positions.lock").path, O_CREAT | O_RDWR, 0o600)
precondition(lockDescriptor >= 0 && flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0)
do { _ = try storage.save(latest); preconditionFailure("Expected nonblocking contention") } catch {}
flock(lockDescriptor, LOCK_UN); close(lockDescriptor)
print("Shared positions passed: newer empty result, measurement ordering, photo stripping, area, expiry, prediction rejection, lock contention.")
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: Double) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}
actor Probe {
    var calls = 0
    func fetch(center: GeoPoint, time: Date) throws -> RadarSnapshot {
        calls += 1
        if calls <= 2 { throw RadarError.http(503) }
        return RadarSnapshot(fetchedAt: time, center: center, radiusKM: 463, planes: [])
    }
}
let testClock = TestClock(now)
let probe = Probe()
let coordinator = PositionCoordinator(persist: false, spacing: 0, clock: { testClock.read() }, fetch: { _, point, _ in
    try await probe.fetch(center: point, time: testClock.read())
})
do {
    _ = try await coordinator.snapshot(center: real.point, radiusKM: 463, minimumInterval: 60)
    preconditionFailure("Expected both sources to fail")
} catch is PositionUnavailable {}
testClock.advance(34) // Source backoff has expired, well before five minutes.
let recovered = try await coordinator.snapshot(center: real.point, radiusKM: 463, minimumInterval: 60)
precondition(recovered.planes.isEmpty)
_ = try await coordinator.snapshot(center: real.point, radiusKM: 463, minimumInterval: 60)
let cachedCalls = await probe.calls
precondition(cachedCalls == 3)
testClock.advance(60)
_ = try await coordinator.snapshot(center: real.point, radiusKM: 463, minimumInterval: 60)
let refreshedCalls = await probe.calls
precondition(refreshedCalls == 4)
print("Refresh regressions passed: model families, stable marker color, 60-second success cache, failed-fetch recovery, empty success, saved location.")
print("Portable Swift regression checks passed: interpolation, original measurements, independent expiry, minute entries, date line, pole, ground, missing course, empty success.")
print("Framework declarations were stubbed. This is NOT an iOS or XCTest runtime test.")
'''

if __name__ == "__main__":
    swift = shutil.which("swiftc")
    if not swift:
        raise SystemExit("swiftc missing from PATH")
    with tempfile.TemporaryDirectory(prefix="skynear-projection-") as directory:
        files = []
        for name in ["Models.swift", "Prediction.swift", "PositionSource.swift", "AircraftFamily.swift", "WidgetRefreshPolicy.swift", "LocationMemory.swift", "SharedPositions.swift", "PositionCoordinator.swift"]:
            source = (ROOT / "Sources/RadarCore" / name).read_text(encoding="utf-8")
            source = source.replace("import CoreLocation\n", "").replace("import ActivityKit\n", "")
            path = pathlib.Path(directory) / name
            path.write_text(source, encoding="utf-8"); files.append(str(path))
        stubs = pathlib.Path(directory) / "PlatformTypes.swift"; stubs.write_text(STUBS, encoding="utf-8")
        main = pathlib.Path(directory) / "main.swift"; main.write_text(CHECKS, encoding="utf-8")
        executable = pathlib.Path(directory) / "checks"
        subprocess.run([swift, "-swift-version", "6", *files, str(stubs), str(main), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

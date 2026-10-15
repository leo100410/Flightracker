import XCTest
@testable import RadarCore

final class SharedPositionsTests: XCTestCase {
    func testNewerEmptyMeasurementSurvivesDelayedResponse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedPositionStore(directory: directory)
        let now = Date()
        let center = GeoPoint(latitude: 50, longitude: 8)
        var old = RadarSnapshot(fetchedAt: now.addingTimeInterval(-20), center: center, radiusKM: 463, planes: [])
        old.sourceTime = old.fetchedAt
        var fresh = old
        fresh.fetchedAt = now.addingTimeInterval(-1); fresh.sourceTime = fresh.fetchedAt
        XCTAssertTrue(try store.save(old))
        XCTAssertTrue(try store.save(fresh))
        var delayed = old; delayed.fetchedAt = now
        XCTAssertFalse(try store.save(delayed))
        XCTAssertEqual(store.load()?.dataDate, fresh.dataDate)
        XCTAssertEqual(store.load()?.planes.count, 0)
        XCTAssertNil(store.load(at: now.addingTimeInterval(1800)))
        XCTAssertNil(SharedPositionStore.newest([fresh], center: GeoPoint(latitude: 51, longitude: 9)))
    }

    func testFreshnessExpiresBeforePrediction() {
        let now = Date()
        let state = NearbyActivityAttributes.ContentState(updated: now, rows: [],
            validUntil: now.addingTimeInterval(900))
        XCTAssertEqual(state.staleAt, now.addingTimeInterval(60))
        let expiring = NearbyActivityAttributes.ContentState(updated: now, rows: [],
            validUntil: now.addingTimeInterval(20))
        XCTAssertEqual(expiring.staleAt, now.addingTimeInterval(20))
    }
}

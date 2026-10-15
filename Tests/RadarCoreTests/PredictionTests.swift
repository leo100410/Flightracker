import XCTest
@testable import RadarCore

final class PredictionTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private func aircraft() throws -> Plane {
        let json = #"{"hex":"abc123","flight":"TEST","t":"A320","lat":0,"lon":179.9,"gs":360,"track":90,"seen_pos":10,"alt_baro":10000}"#
        let raw = try JSONDecoder().decode(LiveAircraft.self, from: Data(json.utf8))
        return try XCTUnwrap(raw.plane(responseTime: time, fetchedAt: time))
    }
    func testProjectionDistanceAndDateLine() throws {
        let origin = GeoPoint(latitude: 0, longitude: 179.9)
        let point = try XCTUnwrap(PositionPrediction.destination(from: origin, speedKnots: 360, course: 90, seconds: 600))
        XCTAssertEqual(origin.distance(to: point), 111.12, accuracy: 0.01)
        XCTAssertLessThan(point.longitude, 0)
        XCTAssertEqual(point.latitude, 0, accuracy: 0.00001)
    }
    func testProjectionNearPoleRemainsFinite() throws {
        let point = try XCTUnwrap(PositionPrediction.destination(from: GeoPoint(latitude: 89.99, longitude: 30),
                                                                speedKnots: 400, course: 0, seconds: 600))
        XCTAssertTrue(point.latitude.isFinite && point.longitude.isFinite)
        XCTAssertTrue((-90...90).contains(point.latitude))
        XCTAssertTrue((-180...180).contains(point.longitude))
    }
    func testOriginalMeasurementAndExpiry() throws {
        let real = try aircraft()
        let first = try XCTUnwrap(PositionPrediction.plane(real, at: time.addingTimeInterval(100)))
        let later = try XCTUnwrap(PositionPrediction.plane(real, at: time.addingTimeInterval(200)))
        XCTAssertEqual(first.positionAt, real.positionAt)
        XCTAssertEqual(later.altitudeFeet, real.altitudeFeet)
        XCTAssertEqual(later.speedKnots, real.speedKnots)
        XCTAssertNil(PositionPrediction.plane(first, at: time.addingTimeInterval(200)))
        XCTAssertNil(PositionPrediction.plane(real, at: time.addingTimeInterval(890)))
        XCTAssertNotNil(PositionPrediction.plane(real, at: time.addingTimeInterval(889)))
        XCTAssertTrue(later.distanceLabel(from: real.point).hasPrefix("~"))
    }
    func testNoGroundUnknownTimeOrInvalidMotionPrediction() throws {
        var real = try aircraft()
        real.onGround = true
        XCTAssertNil(PositionPrediction.plane(real, at: time))
        real.onGround = false; real.positionAt = nil
        XCTAssertNil(PositionPrediction.plane(real, at: time))
        real.positionAt = time; real.track = nil
        XCTAssertNil(PositionPrediction.plane(real, at: time))
        real.track = 90; real.speedKnots = -.infinity
        XCTAssertNil(PositionPrediction.plane(real, at: time))
        real.speedKnots = 100
        XCTAssertNil(PositionPrediction.plane(real, at: time.addingTimeInterval(-1)))
    }
    func testEmptySuccessStaysEmptyDuringOutage() {
        let empty = RadarSnapshot(fetchedAt: time, center: GeoPoint(latitude: 0, longitude: 0), radiusKM: 463, planes: [])
        XCTAssertTrue(empty.predicted(at: time.addingTimeInterval(100)).planes.isEmpty)
    }
    func testNormalPresentationMovesWithoutSourceFailure() throws {
        let real = try aircraft()
        let snapshot = RadarSnapshot(fetchedAt: time, center: real.point, radiusKM: 463, planes: [real])
        let first = try XCTUnwrap(snapshot.displayed(at: time).planes.first)
        let later = try XCTUnwrap(snapshot.displayed(at: time.addingTimeInterval(60)).planes.first)
        XCTAssertTrue(first.isEstimated)
        XCTAssertGreaterThan(real.point.distance(to: later.point), real.point.distance(to: first.point))
        XCTAssertEqual(later.positionAt, real.positionAt)
        XCTAssertEqual(later.altitudeFeet, real.altitudeFeet)
        XCTAssertEqual(snapshot.planes.first?.point, real.point)
    }
    func testEachPlaneExpiresIndependently() throws {
        var first = try aircraft()
        first.positionAt = time.addingTimeInterval(-880)
        var second = try aircraft(); second.id = "def456"; second.positionAt = time
        let snapshot = RadarSnapshot(fetchedAt: time, center: first.point, radiusKM: 463, planes: [first, second])
        let dates = PositionPrediction.timelineDates(for: snapshot, from: time)
        XCTAssertTrue(dates.contains(time.addingTimeInterval(20)))
        XCTAssertEqual(dates.last, time.addingTimeInterval(900))
        XCTAssertEqual(snapshot.displayed(at: time.addingTimeInterval(20)).planes.map(\.id), [second.id])
        XCTAssertTrue(snapshot.displayed(at: time.addingTimeInterval(900)).planes.isEmpty)
    }
    func testGroundAndIncompleteDataAreNeverInterpolated() throws {
        var ground = try aircraft(); ground.onGround = true; ground.positionAt = time
        let snapshot = RadarSnapshot(fetchedAt: time, center: ground.point, radiusKM: 463, planes: [ground])
        XCTAssertEqual(snapshot.displayed(at: time.addingTimeInterval(60)).planes.first?.point, ground.point)
        XCTAssertEqual(snapshot.displayed(at: time.addingTimeInterval(60)).planes.first?.isEstimated, false)
        XCTAssertTrue(snapshot.displayed(at: time.addingTimeInterval(90)).planes.isEmpty)
        var incomplete = ground; incomplete.onGround = false; incomplete.track = nil
        XCTAssertFalse(try XCTUnwrap(PositionPrediction.displayedPlane(incomplete, fetchedAt: time, at: time.addingTimeInterval(60))).isEstimated)
    }
    func testTimelineEndsAtActualPositionDeadline() throws {
        let real = try aircraft()
        let snapshot = RadarSnapshot(fetchedAt: time, center: real.point, radiusKM: 463, planes: [real])
        let dates = PositionPrediction.timelineDates(for: snapshot, from: time)
        XCTAssertEqual(dates.last, time.addingTimeInterval(890))
        XCTAssertTrue(dates.contains(time.addingTimeInterval(60)))
        XCTAssertEqual(dates.count, 16)
        XCTAssertTrue(snapshot.predicted(at: try XCTUnwrap(dates.last)).planes.isEmpty)
        XCTAssertEqual(PositionPrediction.timelineDates(for: snapshot, from: time.addingTimeInterval(900)), [time.addingTimeInterval(900)])
    }
    func testMixedTimeWidgetCohortEndsBeforeFirstPositionExpires() throws {
        let first = try aircraft()
        var second = first; second.id = "abc124"; second.positionAt = time
        let snapshot = RadarSnapshot(fetchedAt: time, center: first.point, radiusKM: 463, planes: [first, second])
        XCTAssertEqual(PositionPrediction.timelineDates(for: snapshot, from: time).last, time.addingTimeInterval(890))
        // App predictions still expire individually; the widget cohort is conservative.
        XCTAssertEqual(snapshot.predicted(at: time.addingTimeInterval(895)).planes.count, 1)
    }
    func testTypeCodeDoesNotComeFromCallsign() throws {
        var real = try aircraft()
        let row = ActivityRow(plane: real, origin: real.point, language: .en)
        XCTAssertEqual(row.typeCode, "A320")
        real.typeCode = nil; real.callsign = "B737123"
        XCTAssertNil(ActivityRow(plane: real, origin: real.point).typeCode)
    }
    func testOldCacheDecodesWithoutPredictionFields() throws {
        let real = try aircraft()
        let snapshot = RadarSnapshot(fetchedAt: time, center: real.point, radiusKM: 463, planes: [real])
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var planes = try XCTUnwrap(object["planes"] as? [[String: Any]])
        planes[0].removeValue(forKey: "positionAt"); planes[0].removeValue(forKey: "estimatedAt")
        object["planes"] = planes
        object.removeValue(forKey: "source"); object.removeValue(forKey: "sourceTime")
        let restored = try JSONDecoder().decode(RadarSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.planes.count, 1)
        XCTAssertNil(restored.planes[0].positionAt)
        XCTAssertTrue(restored.predicted(at: time).planes.isEmpty)
    }
    func testLanguagesAndActivityPayloadSize() throws {
        XCTAssertEqual(AppLanguage.en.text("Geschätzt"), "Estimated")
        XCTAssertEqual(AppLanguage.da.text("Geschätzt"), "Estimeret")
        var real = try aircraft()
        real.callsign = String(repeating: "✈", count: 100)
        let row = ActivityRow(plane: real, origin: real.point, language: .da)
        let state = NearbyActivityAttributes.ContentState(updated: time, rows: Array(repeating: row, count: 5),
                                                          language: .da, source: .adsbFI, estimated: true,
                                                          validUntil: time.addingTimeInterval(900), status: "Estimeret")
        let stateData = try JSONEncoder().encode(state)
        let attributes = try JSONEncoder().encode(NearbyActivityAttributes(title: "SkyNear"))
        XCTAssertLessThan(stateData.count + attributes.count, 4096)
    }
}

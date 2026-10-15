import XCTest
@testable import RadarCore

final class AircraftMarkerTests: XCTestCase {
    func testVariantsAndDistinctFamilies() {
        for code in ["B731", "B732", "B738", "B739", "B37M", "B38M", "B39M", "B3XM"] {
            XCTAssertEqual(AircraftFamily.resolve(code: code), .b737)
        }
        XCTAssertEqual(AircraftFamily.resolve(code: "A21N"), .a321)
        XCTAssertEqual(AircraftFamily.resolve(code: nil, reference: "Airbus A321neo"), .a321)
        XCTAssertEqual(AircraftFamily.resolve(code: "BCS3"), .a220)
        XCTAssertEqual(AircraftFamily.resolve(code: "B712"), .b717)
        XCTAssertEqual(AircraftFamily.resolve(code: "AT76"), .atr72)
        XCTAssertNotEqual(AircraftFamily.a319.profile, AircraftFamily.a321.profile)
        XCTAssertNotEqual(AircraftFamily.b737.profile, AircraftFamily.b757.profile)
    }

    func testUnknownDataDoesNotInventFamily() {
        XCTAssertEqual(AircraftFamily.resolve(code: "A321XYZ"), .generic)
        XCTAssertEqual(AircraftFamily.resolve(code: nil, reference: "Flight B738"), .generic)
        XCTAssertEqual(AircraftFamily.resolve(code: nil, manufacturer: "Boeing"), .boeing)
        XCTAssertEqual(AircraftFamily.resolve(code: nil), .generic)
    }

    func testPredictionKeepsMarkerColorAndMeasurements() throws {
        let now = Date()
        let raw = try JSONDecoder().decode(LiveAircraft.self, from: Data(
            #"{"hex":"abc123","t":"A320","lat":1,"lon":2,"gs":300,"track":90,"seen_pos":0}"#.utf8))
        let real = try XCTUnwrap(raw.plane(responseTime: now, fetchedAt: now))
        let predicted = try XCTUnwrap(PositionPrediction.plane(real, at: now.addingTimeInterval(60)))
        XCTAssertTrue(predicted.isEstimated)
        XCTAssertEqual(real.markerIsGround, predicted.markerIsGround)
        XCTAssertEqual(real.aircraftFamily, predicted.aircraftFamily)
        XCTAssertEqual(real.positionAt, predicted.positionAt)
        XCTAssertTrue(predicted.distanceLabel(from: real.point).hasPrefix("~"))
    }

    func testSuccessReuseBoundaryIncludesAuthoritativeEmptyResponse() {
        let now = Date()
        let center = GeoPoint(latitude: 1, longitude: 2)
        let empty = RadarSnapshot(fetchedAt: now, center: center, radiusKM: 463, planes: [])
        XCTAssertTrue(WidgetRefreshPolicy.canReuse(empty, at: now.addingTimeInterval(59), center: center))
        XCTAssertFalse(WidgetRefreshPolicy.canReuse(empty, at: now.addingTimeInterval(60), center: center))
        XCTAssertFalse(WidgetRefreshPolicy.canReuse(empty, at: now.addingTimeInterval(-1), center: center))
        XCTAssertFalse(WidgetRefreshPolicy.canReuse(empty, at: now, center: GeoPoint(latitude: 2, longitude: 2)))
    }
    func testSavedLocationPreservesMeasurementTimeAndRejectsInvalidCoordinates() {
        let key = "skynear.last-location.v1"
        let original = UserDefaults.standard.data(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let time = Date().addingTimeInterval(-600)
        let point = GeoPoint(latitude: 50, longitude: 8)
        LocationMemory.save(SavedLocation(point: point, measuredAt: time))
        XCTAssertEqual(LocationMemory.load()?.point, point)
        XCTAssertEqual(LocationMemory.load()?.measuredAt, time)
        LocationMemory.save(SavedLocation(point: GeoPoint(latitude: 91, longitude: 0), measuredAt: time))
        XCTAssertNil(LocationMemory.load())
    }

}

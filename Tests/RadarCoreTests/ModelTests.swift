import XCTest
@testable import RadarCore

final class ModelTests: XCTestCase {
    func testGroundAndMissingPosition() throws {
        let json = #"{"ac":[{"hex":"abc123","flight":" TEST12 ","lat":37.8,"lon":-4.7,"alt_baro":"ground","gs":10},{"hex":"abc124"}],"msg":"No error"}"#
        let response = try JSONDecoder().decode(LiveResponse.self, from: Data(json.utf8))
        let planes = try XCTUnwrap(response.ac).compactMap { $0.plane() }
        XCTAssertEqual(planes.count, 1)
        XCTAssertEqual(planes[0].label, "TEST12")
        XCTAssertTrue(planes[0].onGround)
        XCTAssertEqual(planes[0].altitudeLabel, "Am Boden")
        XCTAssertEqual(planes[0].speedLabel, "19 km/h")
    }
    func testUnitConversionAndStalePosition() throws {
        let json = #"{"ac":[{"hex":"a1","lat":1,"lon":2,"alt_baro":10000,"gs":100},{"hex":"a2","lat":1,"lon":2,"seen_pos":95}]}"#
        let response = try JSONDecoder().decode(LiveResponse.self, from: Data(json.utf8))
        let planes = try XCTUnwrap(response.ac).compactMap { $0.plane() }
        XCTAssertEqual(planes.count, 1)
        XCTAssertEqual(planes[0].altitudeLabel, "3048 m")
        XCTAssertEqual(planes[0].speedLabel, "185 km/h")
    }
    func testDistanceAcrossDateLine() {
        let a = GeoPoint(latitude: 0, longitude: 179.9)
        let b = GeoPoint(latitude: 0, longitude: -179.9)
        XCTAssertEqual(a.distance(to: b), 22.24, accuracy: 0.1)
    }
    func testMetadataDecode() throws {
        let json = #"{"aircraft":{"type":"Airbus A320","registered_owner":"Owner"},"flightroute":{"airline":{"name":"Airline"},"origin":{"iata_code":"MAD"},"destination":{"iata_code":"BCN"}}}"#
        let data = try JSONDecoder().decode(Metadata.self, from: Data(json.utf8))
        XCTAssertEqual(data.flightroute?.origin?.label, "MAD")
        XCTAssertEqual(data.aircraft?.type, "Airbus A320")
    }
}

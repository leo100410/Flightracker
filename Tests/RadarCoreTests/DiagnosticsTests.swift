import XCTest
@testable import RadarCore

final class DiagnosticsTests: XCTestCase {
    func testWidgetTransferRoundTripAndBounds() throws {
        let session = UUID()
        let events = (0..<200).map {
            DiagnosticEvent(process: "widget", session: session, build: "6",
                            event: "source success sequence=\($0)", at: Date(timeIntervalSince1970: Double($0)))
        }
        let url = try XCTUnwrap(RadarDiagnostics.transferURL(events: events))
        XCTAssertLessThan(url.absoluteString.count, 9_000)
        let decoded = try RadarDiagnostics.decodedTransfer(url)
        XCTAssertEqual(decoded.available, 200)
        XCTAssertLessThanOrEqual(decoded.events.count, 160)
        XCTAssertEqual(decoded.events.last?.id, events.last?.id)
        XCTAssertEqual(decoded.events.map(\.id), Array(events.suffix(decoded.events.count)).map(\.id))
    }

    func testRejectsForeignAndMalformedTransfers() throws {
        for text in ["https://example.com", "skynear://diagnostics", "skynear://diagnostics?v=2&log=abc",
                     "skynear://diagnostics?v=1&log=invalid", "skynear://diagnostics?v=1&log=" + String(repeating: "a", count: 10_000)] {
            XCTAssertThrowsError(try RadarDiagnostics.decodedTransfer(try XCTUnwrap(URL(string: text))))
        }
        let appEvent = DiagnosticEvent(process: "app", session: UUID(), build: "6", event: "not a widget")
        let url = try XCTUnwrap(RadarDiagnostics.transferURL(events: [appEvent]))
        XCTAssertThrowsError(try RadarDiagnostics.decodedTransfer(url))
    }

    func testFilePersistenceAndImportDeduplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DiagnosticJournal(directory: directory, limit: 4096)
        let event = DiagnosticEvent(process: "widget", session: UUID(), build: "6", event: "provider begin")
        try journal.append(event)
        try journal.merge([event, event])
        XCTAssertEqual(try DiagnosticJournal(directory: directory).read().map(\.id), [event.id])
        for index in 0..<100 {
            try journal.append(DiagnosticEvent(process: "app", session: UUID(), build: "6", event: "event \(index)"))
        }
        XCTAssertEqual(try journal.read().last?.event, "event 99")
        XCTAssertLessThanOrEqual(try Data(contentsOf: directory.appendingPathComponent("events.jsonl")).count, 4096)
    }
}

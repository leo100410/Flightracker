import XCTest
import os
@testable import RadarCore

final class PositionSourceTests: XCTestCase {
    func testSecondsMillisecondsAndInvalidTimes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(PositionTime.date(1_800_000_000, fetchedAt: now), now)
        XCTAssertEqual(PositionTime.date(1_800_000_000_000, fetchedAt: now), now)
        XCTAssertNil(PositionTime.date(nil, fetchedAt: now))
        XCTAssertNil(PositionTime.date(.infinity, fetchedAt: now))
        XCTAssertNil(PositionTime.date(1_800_000_100, fetchedAt: now))
        XCTAssertNil(PositionTime.date(1_799_999_000, fetchedAt: now))
    }
    func testBothResponseEnvelopesAndPositionTime() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for key in ["ac", "aircraft"] {
            let json = "{\"\(key)\":[{\"hex\":\"a1\",\"lat\":1,\"lon\":2,\"seen_pos\":15}],\"now\":1800000000000}"
            let response = try JSONDecoder().decode(LiveResponse.self, from: Data(json.utf8))
            let raw = try XCTUnwrap((response.ac ?? response.aircraft)?.first)
            let plane = try XCTUnwrap(raw.plane(responseTime: PositionTime.date(response.now, fetchedAt: now), fetchedAt: now))
            XCTAssertEqual(plane.positionAt, now.addingTimeInterval(-15))
        }
    }
    func testRetryAfterAndExponentialBackoff() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var cooldown = SourceCooldown()
        cooldown.fail(at: now, code: 503, retryAfter: nil)
        XCTAssertEqual(cooldown.until, now.addingTimeInterval(30))
        cooldown.fail(at: now, code: 503, retryAfter: nil)
        XCTAssertEqual(cooldown.until, now.addingTimeInterval(60))
        cooldown.fail(at: now, code: 429, retryAfter: now.addingTimeInterval(3600))
        XCTAssertEqual(cooldown.until, now.addingTimeInterval(3600))
        XCTAssertEqual(PositionTime.retryAfter("120", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(PositionTime.retryAfter("Wed, 21 Oct 2015 07:28:00 GMT", now: now), Date(timeIntervalSince1970: 1_445_412_480))
        XCTAssertNil(PositionTime.retryAfter("invalid", now: now))
        cooldown.fail(at: now, code: 403, retryAfter: nil)
        XCTAssertGreaterThanOrEqual(cooldown.until, now.addingTimeInterval(900))
    }
    func testFallbackEndpointClampsRadiusAndRoundsCoordinates() {
        let url = PositionSource.adsbFI.url(center: GeoPoint(latitude: 60.31791, longitude: 24.94961), radiusKM: 999)
        XCTAssertEqual(url.absoluteString, "https://opendata.adsb.fi/api/v3/lat/60.318/lon/24.950/dist/250.0")
    }
}

private actor FetchProbe {
    var sources: [PositionSource] = []
    var running = 0
    var maximumRunning = 0
    let failPrimary: Bool
    let failBoth: Bool
    let failPrimaryOnce: Bool
    var primaryFailed = false
    let time: Date
    init(time: Date, failPrimary: Bool = false, failBoth: Bool = false, failPrimaryOnce: Bool = false) {
        self.time = time; self.failPrimary = failPrimary; self.failBoth = failBoth; self.failPrimaryOnce = failPrimaryOnce
    }
    func fetch(_ source: PositionSource, center: GeoPoint, radius: Double) async throws -> RadarSnapshot {
        sources.append(source); running += 1; maximumRunning = max(maximumRunning, running)
        defer { running -= 1 }
        try await Task.sleep(for: .milliseconds(15))
        if source == .adsbLOL, failPrimaryOnce, !primaryFailed {
            primaryFailed = true
            throw RadarError.rateLimited(429, time.addingTimeInterval(3600))
        }
        if failBoth || (failPrimary && source == .adsbLOL) {
            throw RadarError.rateLimited(429, time.addingTimeInterval(3600))
        }
        return RadarSnapshot(fetchedAt: time, center: center, radiusKM: radius, planes: [])
    }
}
final class PositionCoordinatorTests: XCTestCase {
    func testConcurrentSameScopeCoalescesAndCachesEmptySuccess() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let probe = FetchProbe(time: now)
        let coordinator = PositionCoordinator(persist: false, spacing: 0, clock: { now }, fetch: {
            try await probe.fetch($0, center: $1, radius: $2)
        })
        let point = GeoPoint(latitude: 1, longitude: 2)
        async let first = coordinator.snapshot(center: point, radiusKM: 463)
        async let second = coordinator.snapshot(center: point, radiusKM: 463)
        let values = try await (first, second)
        XCTAssertTrue(values.0.planes.isEmpty && values.1.planes.isEmpty)
        _ = try await coordinator.snapshot(center: point, radiusKM: 463)
        let calls = await probe.sources
        XCTAssertEqual(calls, [.adsbLOL])
    }
    func testFallbackHonorsCooldownAcrossDifferentMapScopes() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let probe = FetchProbe(time: now, failPrimary: true)
        let coordinator = PositionCoordinator(persist: false, spacing: 0, clock: { now }, fetch: {
            try await probe.fetch($0, center: $1, radius: $2)
        })
        let first = try await coordinator.snapshot(center: GeoPoint(latitude: 1, longitude: 2), radiusKM: 463)
        let second = try await coordinator.snapshot(center: GeoPoint(latitude: 3, longitude: 4), radiusKM: 463)
        XCTAssertEqual(first.source, .adsbFI)
        XCTAssertEqual(second.sourceIssues?.first?.retryAt, now.addingTimeInterval(3600))
        let calls = await probe.sources
        XCTAssertEqual(calls, [.adsbLOL, .adsbFI, .adsbFI])
    }
    func testBothSourcesFailAndDoNotRetryDuringCooldown() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let probe = FetchProbe(time: now, failBoth: true)
        let coordinator = PositionCoordinator(persist: false, spacing: 0, clock: { now }, fetch: {
            try await probe.fetch($0, center: $1, radius: $2)
        })
        for index in 0..<2 {
            do {
                _ = try await coordinator.snapshot(center: GeoPoint(latitude: Double(index), longitude: 2), radiusKM: 463)
                XCTFail("Expected unavailable sources")
            } catch let failure as PositionUnavailable { XCTAssertEqual(failure.issues.count, 2) }
        }
        let calls = await probe.sources
        XCTAssertEqual(calls, [.adsbLOL, .adsbFI])
    }
    func testDifferentScopesNeverRunInParallel() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let probe = FetchProbe(time: now)
        let coordinator = PositionCoordinator(persist: false, spacing: 0, clock: { now }, fetch: {
            try await probe.fetch($0, center: $1, radius: $2)
        })
        async let first = coordinator.snapshot(center: GeoPoint(latitude: 1, longitude: 2), radiusKM: 463)
        async let second = coordinator.snapshot(center: GeoPoint(latitude: 3, longitude: 4), radiusKM: 463)
        _ = try await (first, second)
        let maximum = await probe.maximumRunning
        XCTAssertEqual(maximum, 1)
    }
    func testPrimaryReturnsAfterCooldown() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = OSAllocatedUnfairLock(initialState: now)
        let probe = FetchProbe(time: now, failPrimaryOnce: true)
        let coordinator = PositionCoordinator(persist: false, spacing: 0, clock: { clock.withLock { $0 } }, fetch: {
            try await probe.fetch($0, center: $1, radius: $2)
        })
        let first = try await coordinator.snapshot(center: GeoPoint(latitude: 1, longitude: 2), radiusKM: 463)
        XCTAssertEqual(first.source, .adsbFI)
        clock.withLock { $0 = now.addingTimeInterval(3601) }
        let recovered = try await coordinator.snapshot(center: GeoPoint(latitude: 1, longitude: 2), radiusKM: 463)
        XCTAssertEqual(recovered.source, .adsbLOL)
        XCTAssertTrue(recovered.sourceIssues?.isEmpty == true)
        let calls = await probe.sources
        XCTAssertEqual(calls, [.adsbLOL, .adsbFI, .adsbLOL])
    }
    func testCancellationDoesNotTriggerFallbackOrInvalidateSharedResult() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let probe = FetchProbe(time: now)
        let coordinator = PositionCoordinator(persist: false, spacing: 0, clock: { now }, fetch: {
            try await probe.fetch($0, center: $1, radius: $2)
        })
        let point = GeoPoint(latitude: 1, longitude: 2)
        let waiter = Task { try await coordinator.snapshot(center: point, radiusKM: 463) }
        while await probe.sources.isEmpty { await Task.yield() }
        waiter.cancel()
        do { _ = try await waiter.value; XCTFail("Cancelled caller must not publish a result") }
        catch is CancellationError { }
        let value = try await coordinator.snapshot(center: point, radiusKM: 463)
        XCTAssertTrue(value.planes.isEmpty)
        let calls = await probe.sources
        XCTAssertEqual(calls, [.adsbLOL])
    }
}

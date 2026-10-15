import Foundation
import CoreLocation
import Combine

@MainActor
public final class AppLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published public private(set) var point: GeoPoint?
    @Published public private(set) var message: String = "Standort noch nicht freigegeben."
    private let manager = CLLocationManager()
    private var active = false
    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
    }
    public func start() {
        active = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted: message = "Standort verweigert. Unter Einstellungen > SkyNear freigeben."
        @unknown default: message = "Standortberechtigung nicht verfügbar."
        }
    }
    public func stop() { active = false; manager.stopUpdatingLocation() }
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if active { start() }
    }
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 120 else { return }
        let measuredPoint = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        point = measuredPoint
        LocationMemory.save(SavedLocation(point: measuredPoint, measuredAt: location.timestamp))
        message = location.horizontalAccuracy > 1000 ? "Ungefährer Standort" : "Standort verfügbar"
    }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        message = "Standortfehler"
    }
}

@MainActor
public final class WidgetLocationRequest: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GeoPoint, any Error>?
    private var timeout: Task<Void, Never>?
    private override init() { super.init(); manager.delegate = self }
    public static func current(timeout seconds: TimeInterval = 6) async throws -> GeoPoint {
        let request = WidgetLocationRequest()
        return try await request.run(timeout: seconds)
    }
    private func run(timeout seconds: TimeInterval) async throws -> GeoPoint {
        guard manager.isAuthorizedForWidgetUpdates else {
            throw RadarError.location("App öffnen, Standort freigeben und die Standortnutzung des Widgets erlauben.")
        }
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError()); return
                }
                self.continuation = continuation
                manager.requestLocation()
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) }
                    catch { return }
                    self?.finish(.failure(RadarError.location("Aktueller Standort nicht verfügbar. App kurz öffnen.")))
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }
    private func finish(_ result: Result<GeoPoint, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 300 else {
            finish(.failure(RadarError.location("Standort ist zu alt."))); return
        }
        let point = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        LocationMemory.save(SavedLocation(point: point, measuredAt: location.timestamp))
        finish(.success(point))
    }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finish(.failure(RadarError.location("Standortfehler")))
    }
}

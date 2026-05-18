import Foundation
import CoreLocation
#if canImport(MapKit)
import MapKit
#endif

/// A compact place fix — what's worth remembering, not raw lat/lon.
struct PlaceFix: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var arrivedAt: Date
    var placemarkSummary: String?  // reverse-geocoded name (e.g. "Coffee Labs, SF")

    /// Human-readable one-liner for the digest.
    var readable: String {
        if let placemarkSummary { return placemarkSummary }
        return String(format: "(%.4f, %.4f)", latitude, longitude)
    }
}

/// Listens to `CLLocationManager` significant-change events so Eidos
/// knows the major places you go — home, work, gym, a friend's
/// neighborhood — without burning your battery.
///
/// Privacy: every fix is summarised via reverse geocoding to a
/// placemark name and stored as memory. Raw lat/lon is kept only
/// until the fix is memorialised; then discarded.
@MainActor
@Observable
final class LocationSource: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    var lastFix: PlaceFix?
    var isMonitoring = false
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200  // metres before next event
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Permission

    /// Requests "when in use" first. Users can upgrade to "always" in
    /// iOS Settings for true background passive monitoring. We never
    /// prompt for "always" ourselves — too invasive for onboarding.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    // MARK: - Monitoring

    /// Starts significant-change monitoring. Safe to call multiple times.
    func startMonitoring() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        guard manager.authorizationStatus.isAuthorized else { return }
        manager.startMonitoringSignificantLocationChanges()
        isMonitoring = true
    }

    func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        isMonitoring = false
    }

    /// One-shot fix for callers that want "where am I right now?" —
    /// e.g. arrived-home dose triggers and ambient-snapshot context.
    func currentFix() async -> PlaceFix? {
        guard manager.authorizationStatus.isAuthorized else { return nil }
        let loc: CLLocation?
        if let cached = manager.location { loc = cached }
        else { loc = await awaitNext() }
        guard let loc else { return nil }
        return await makeFix(from: loc)
    }

    // MARK: - Internals

    private func awaitNext() async -> CLLocation? {
        manager.requestLocation()
        // Short-grain wait. If nothing comes back, we time out.
        for _ in 0..<20 {
            if let loc = manager.location { return loc }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }

    private func makeFix(from location: CLLocation) async -> PlaceFix {
        let summary = await reverseGeocode(location)
        let fix = PlaceFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            arrivedAt: location.timestamp,
            placemarkSummary: summary
        )
        lastFix = fix
        return fix
    }

    /// On-device reverse geocoding. `CLGeocoder` uses Apple's CDN, so
    /// strictly this IS network — but it's to Apple, not us, and only
    /// goes out once per significant change. Trade-off we accept for
    /// readable place names.
    private func reverseGeocode(_ location: CLLocation) async -> String? {
        #if canImport(MapKit)
        guard #available(iOS 26.0, macCatalyst 26.0, *) else {
            return nil
        }
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else {
            return nil
        }
        let mark = item.placemark
        if let name = item.name, name.rangeOfCharacter(from: .decimalDigits) == nil {
            // Prefer a proper name ("Ferry Building") over a street number.
            return name
        }
        return [mark.subThoroughfare, mark.thoroughfare, mark.locality]
            .compactMap { $0 }
            .joined(separator: " ")
        #else
        return nil
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            if status.isAuthorized { self.startMonitoring() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            _ = await self.makeFix(from: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — location failures are common and expected indoors etc.
    }
}

private extension CLAuthorizationStatus {
    /// True when the user has granted any form of location access.
    /// `authorizedWhenInUse` is unavailable on macOS; guard the check.
    var isAuthorized: Bool {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return self == .authorizedAlways || self == .authorizedWhenInUse
        #else
        return self == .authorizedAlways
        #endif
    }
}

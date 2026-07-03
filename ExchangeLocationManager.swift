import CoreLocation
import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class ExchangeLocationManager: NSObject {
    private(set) var latitude: Double?
    private(set) var longitude: Double?
    private(set) var address = ""
    private(set) var statusMessage = "Location has not been captured yet."
    private(set) var isCapturing = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func captureLocation() {
        guard !isCapturing else {
            return
        }

        isCapturing = true
        statusMessage = "Capturing current location..."

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isCapturing = false
            statusMessage = "Location permission is off. You can still save the exchange without GPS."
        @unknown default:
            isCapturing = false
            statusMessage = "Location could not be captured. You can still save the exchange."
        }
    }

    private func updateLocation(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        statusMessage = "Location captured. Looking up address..."

        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                statusMessage = "Location captured."
                isCapturing = false
                return
            }

            request.getMapItems { [weak manager = self] mapItems, _ in
                let address = mapItems?.first?.factTrailAddress ?? ""
                Task { @MainActor [weak manager] in
                    guard let manager else { return }
                    manager.address = address
                    manager.statusMessage = manager.address.isEmpty ? "Location captured." : "Address captured."
                    manager.isCapturing = false
                }
            }
        } else {
            address = ""
            statusMessage = "Location captured. Address lookup requires iOS 26 or newer."
            isCapturing = false
        }
    }
}

extension ExchangeLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                isCapturing = false
                statusMessage = "Location permission is off. You can still save the exchange without GPS."
            case .notDetermined:
                break
            @unknown default:
                isCapturing = false
                statusMessage = "Location could not be captured. You can still save the exchange."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        Task { @MainActor in
            updateLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isCapturing = false
            statusMessage = "Location could not be captured. You can still save the exchange."
        }
    }
}

private extension MKMapItem {
    @available(iOS 26.0, *)
    var factTrailAddress: String {
        if let fullAddress = addressRepresentations?.fullAddress(includingRegion: true, singleLine: true),
           !fullAddress.isEmpty {
            return fullAddress
        }

        if let fullAddress = address?.fullAddress, !fullAddress.isEmpty {
            return fullAddress.replacingOccurrences(of: "\n", with: ", ")
        }

        return name ?? ""
    }
}

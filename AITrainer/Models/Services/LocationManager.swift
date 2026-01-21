//
//  LocationManager.swift
//  AITrainer
//
//  Manages location services for finding nearby gyms
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var placemark: CLPlacemark?

    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Location access denied. Please enable in Settings."
        case .authorizedWhenInUse, .authorizedAlways:
            getCurrentLocation()
        @unknown default:
            break
        }
    }

    func getCurrentLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission()
            return
        }

        isLoading = true
        errorMessage = nil
        locationManager.requestLocation()
    }

    func searchLocation(address: String) {
        isLoading = true
        errorMessage = nil

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.errorMessage = "Could not find location: \(error.localizedDescription)"
                    return
                }

                if let placemark = placemarks?.first,
                   let location = placemark.location {
                    self?.location = location
                    self?.placemark = placemark
                } else {
                    self?.errorMessage = "Could not find location for: \(address)"
                }
            }
        }
    }

    var locationString: String {
        guard let placemark = placemark else {
            if let location = location {
                return "\(location.coordinate.latitude), \(location.coordinate.longitude)"
            }
            return "Unknown Location"
        }

        var components: [String] = []
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }

        return components.joined(separator: ", ")
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isLoading = false

        guard let location = locations.first else { return }
        self.location = location

        // Reverse geocode to get placemark
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    self?.placemark = placemark
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = "Failed to get location: \(error.localizedDescription)"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            getCurrentLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied"
        default:
            break
        }
    }
}
//
//  GymFinderService.swift
//  AITrainer
//
//  Service for finding nearby gyms using Google Places API
//

import Foundation
import Combine
import CoreLocation

class GymFinderService: ObservableObject {
    private let baseURL = "http://localhost:8000"

    @Published var nearbyGyms: [Gym] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    func searchNearbyGyms(location: CLLocation, radius: Int = 5000, keyword: String? = nil) {
        isLoading = true
        errorMessage = nil

        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        var components = URLComponents(string: "\(baseURL)/gyms/nearby")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius", value: String(radius))
        ]
        if let keyword = keyword, !keyword.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "keyword", value: keyword))
        }

        guard let url = components?.url else {
            self.errorMessage = "Invalid URL"
            self.isLoading = false
            return
        }

        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: GymSearchResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to find gyms: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    let results = response.results ?? []
                    if response.status == "OK" {
                        let baseURL = self?.baseURL ?? "http://localhost:8000"
                        self?.nearbyGyms = results.map { $0.toGym(baseURL: baseURL) }
                    } else {
                        let message = response.errorMessage ?? "No gyms found in this area"
                        self?.errorMessage = message
                        self?.nearbyGyms = []
                    }
                }
            )
            .store(in: &cancellables)
    }

    func searchGymsByText(query: String, location: CLLocation?) {
        isLoading = true
        errorMessage = nil

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "\(baseURL)/gyms/search")
        var queryItems = [URLQueryItem(name: "query", value: trimmedQuery)]

        if let location = location {
            let lat = location.coordinate.latitude
            let lng = location.coordinate.longitude
            queryItems.append(URLQueryItem(name: "lat", value: String(lat)))
            queryItems.append(URLQueryItem(name: "lng", value: String(lng)))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            self.errorMessage = "Invalid URL"
            self.isLoading = false
            return
        }

        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: GymSearchResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to search gyms: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    let results = response.results ?? []
                    if response.status == "OK" {
                        let baseURL = self?.baseURL ?? "http://localhost:8000"
                        self?.nearbyGyms = results.map { $0.toGym(baseURL: baseURL) }
                    } else {
                        let message = response.errorMessage ?? "No gyms found matching your search"
                        self?.errorMessage = message
                        self?.nearbyGyms = []
                    }
                }
            )
            .store(in: &cancellables)
    }
}
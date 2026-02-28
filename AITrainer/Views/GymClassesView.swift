//
//  GymClassesView.swift
//  AITrainer
//
//  View for finding local gym classes
//

import SwiftUI
import CoreLocation
import MapKit
import UIKit

struct GymClassesView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var gymFinder = GymFinderService()
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var showLocationSearch = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color.black,
                        Color.blue.opacity(0.28),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Location section
                    locationSection
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)

                    // Content
                    if gymFinder.isLoading {
                        loadingView
                    } else if gymFinder.nearbyGyms.isEmpty && !locationManager.isLoading {
                        emptyStateView
                    } else {
                        gymsListView
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showLocationSearch) {
            LocationSearchView { location in
                locationManager.searchLocation(address: location)
                showLocationSearch = false
            }
        }
        .onAppear {
            locationManager.getCurrentLocation()
        }
        .onChange(of: locationManager.location) { location in
            if let location = location {
                gymFinder.searchNearbyGyms(
                    location: location,
                    keyword: searchText.isEmpty ? nil : searchText
                )
            }
        }
        .onChange(of: searchText) { _ in
            searchTask?.cancel()
            searchTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                searchForGyms()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Local Gyms")
                    .font(.displayMedium)
                    .foregroundColor(.white)

                Text("Find gyms near you")
                    .font(.bodyMedium)
                    .foregroundColor(.white.opacity(0.72))
            }

            Spacer()

            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                // Current location display
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)

                    if locationManager.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Getting location...")
                        }
                    } else {
                        Text(locationManager.locationString)
                            .font(.bodyMedium)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // Change location button
                    Button(action: {
                        showLocationSearch = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }

                // Search and location buttons
                HStack(spacing: 12) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.72))

                        TextField("Search gyms or places...", text: $searchText)
                            .font(.bodyMedium)
                            .foregroundColor(.white)
                            .accentColor(.blue)
                            .onSubmit {
                                searchForGyms()
                            }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)

                    // Search / current location button
                    Button(action: {
                        searchForGyms()
                    }) {
                        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Image(systemName: trimmed.isEmpty ? "location.circle.fill" : "paperplane.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }

                if let errorMessage = locationManager.errorMessage {
                    Text(errorMessage)
                        .font(.captionMedium)
                        .foregroundColor(.red.opacity(0.95))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .fitnessGradientStart))
                .scaleEffect(1.5)

            Text("Finding gyms...")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.fitnessGradientStart.opacity(0.2))
                    .frame(width: 80, height: 80)

                Text("🏋️‍♀️")
                    .font(.system(size: 40))
            }

            VStack(spacing: 8) {
                Text("No gyms found")
                    .font(.headlineMedium)
                    .foregroundColor(.white)

                Text("Try adjusting your location or search terms")
                    .font(.bodyMedium)
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            if let errorMessage = gymFinder.errorMessage ?? locationManager.errorMessage {
                Text(errorMessage)
                    .font(.captionMedium)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button(action: {
                locationManager.requestLocationPermission()
            }) {
                Text("Allow Location Access")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Gyms List View

    private var gymsListView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                ForEach(gymFinder.nearbyGyms) { gym in
                    GymCard(gym: gym, currentLocation: locationManager.location)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Helper Methods

    private func searchForGyms() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if let location = locationManager.location {
                gymFinder.searchNearbyGyms(
                    location: location,
                    keyword: nil
                )
            } else {
                gymFinder.nearbyGyms = []
                gymFinder.errorMessage = "Please enable location access to find nearby gyms."
                locationManager.requestLocationPermission()
            }
            return
        }

        if let location = locationManager.location {
            gymFinder.searchGymsByText(query: trimmed, location: location)
        } else {
            gymFinder.nearbyGyms = []
            gymFinder.errorMessage = "Please enable location access to search for local gyms."
            locationManager.requestLocationPermission()
        }
    }

    private func isLocationQuery(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("university") || lower.contains("college") {
            return true
        }
        if lower.contains("street") || lower.contains("st ") || lower.contains("ave") || lower.contains("road") || lower.contains("rd ") || lower.contains("blvd") {
            return true
        }
        if lower.contains(",") {
            return true
        }
        return lower.rangeOfCharacter(from: .decimalDigits) != nil
    }
}

// MARK: - Gym Card

struct GymCard: View {
    let gym: Gym
    let currentLocation: CLLocation?

    private var distanceText: String? {
        guard let currentLocation = currentLocation else { return nil }
        return gym.distance(from: currentLocation)
    }

    private var openStatusText: String? {
        guard let isOpen = gym.isOpen else { return nil }
        return isOpen ? "Open now" : "Closed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                gymPhoto

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gym.name)
                            .font(.headlineMedium)
                            .foregroundColor(.white)

                        Text(gym.address)
                            .font(.bodyMedium)
                            .foregroundColor(.white.opacity(0.72))
                    }

                    Spacer()

                    if let rating = gym.rating {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f", rating))
                                .font(.bodyMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                }

                HStack(spacing: 12) {
                    if let distanceText = distanceText {
                        Label(distanceText, systemImage: "location")
                            .font(.captionLarge)
                            .foregroundColor(.white.opacity(0.72))
                    }

                    if let openStatusText = openStatusText {
                        Text(openStatusText)
                            .font(.captionLarge)
                            .foregroundColor(gym.isOpen == true ? .green : .red)
                    }
                }

                Button(action: openInMaps) {
                    Text("Open in Maps")
                        .font(.bodyMedium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                }
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var gymPhoto: some View {
        Group {
            if let photoURL = gym.photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                } placeholder: {
                    photoPlaceholder
                }
            } else {
                photoPlaceholder
            }
        }
        .frame(height: 130)
        .clipped()
        .cornerRadius(12)
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.fitnessGradientStart.opacity(0.6),
                    Color.fitnessGradientEnd.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private func openInMaps() {
        let coordinate = CLLocationCoordinate2D(latitude: gym.latitude, longitude: gym.longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = gym.name
        item.openInMaps()
    }
}

// MARK: - Location Search View

struct LocationSearchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    let onLocationSelected: (String) -> Void

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.72))

                    TextField("Enter city, address, or ZIP code", text: $searchText)
                        .font(.bodyMedium)
                        .foregroundColor(.white)
                        .accentColor(.blue)
                        .onSubmit {
                            if !searchText.isEmpty {
                                onLocationSelected(searchText)
                            }
                        }
                }
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .padding()

                Spacer()
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color.blue.opacity(0.22), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .preferredColorScheme(.dark)
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Search") {
                        if !searchText.isEmpty {
                            onLocationSelected(searchText)
                        }
                    }
                    .disabled(searchText.isEmpty)
                }
            }
        }
    }
}

#Preview {
    GymClassesView()
}
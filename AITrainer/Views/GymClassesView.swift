//
//  GymClassesView.swift
//  AITrainer
//
//  View for finding local gym classes
//

import SwiftUI
import CoreLocation
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
                        Color.backgroundGradientStart,
                        Color.backgroundGradientEnd,
                        Color.white.opacity(0.8)
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
        .onChange(of: locationManager.location) { location in
            if let location = location {
                gymFinder.searchNearbyGyms(location: location, keyword: searchText.isEmpty ? nil : searchText)
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
                    .foregroundColor(.textPrimary)

                Text("Find gyms near you")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 44, height: 44)

                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        ModernCard {
            VStack(spacing: 16) {
                // Current location display
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.fitnessGradientStart)

                    if locationManager.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Getting location...")
                        }
                    } else {
                        Text(locationManager.locationString)
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                    }

                    Spacer()

                    // Change location button
                    Button(action: {
                        showLocationSearch = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(.fitnessGradientStart)
                    }
                }

                // Search and location buttons
                HStack(spacing: 12) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textSecondary)

                        TextField("Search gyms or places...", text: $searchText)
                            .font(.bodyMedium)
                            .onSubmit {
                                searchForGyms()
                            }
                    }
                    .padding(12)
                    .background(Color.backgroundGradientStart)
                    .cornerRadius(12)

                    // Current location button
                    Button(action: {
                        locationManager.getCurrentLocation()
                    }) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.fitnessGradientStart)
                    }
                }

                if let errorMessage = locationManager.errorMessage {
                    Text(errorMessage)
                        .font(.captionMedium)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
        }
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
                    .foregroundColor(.textPrimary)

                Text("Try adjusting your location or search terms")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            ModernPrimaryButton(title: "Allow Location Access") {
                locationManager.requestLocationPermission()
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
                gymFinder.searchNearbyGyms(location: location, keyword: nil)
            } else {
                locationManager.requestLocationPermission()
            }
            return
        }

        if isLocationQuery(trimmed) {
            gymFinder.searchGymsByText(query: trimmed, location: nil)
            return
        }

        if let location = locationManager.location {
            gymFinder.searchNearbyGyms(location: location, keyword: trimmed)
        } else {
            gymFinder.searchGymsByText(query: trimmed, location: nil)
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
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                gymPhoto

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gym.name)
                            .font(.headlineMedium)
                            .foregroundColor(.textPrimary)

                        Text(gym.address)
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
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
                                .foregroundColor(.textPrimary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    if let distanceText = distanceText {
                        Label(distanceText, systemImage: "location")
                            .font(.captionLarge)
                            .foregroundColor(.textSecondary)
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
                        .foregroundColor(.fitnessGradientStart)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.fitnessGradientStart, lineWidth: 1)
                        )
                }
            }
            .padding(20)
        }
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
        .frame(height: 160)
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
        let urlString = "http://maps.apple.com/?q=\(gym.name)&ll=\(gym.latitude),\(gym.longitude)"
        if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            UIApplication.shared.open(url)
        }
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
                        .foregroundColor(.textSecondary)

                    TextField("Enter city, address, or ZIP code", text: $searchText)
                        .font(.bodyMedium)
                        .onSubmit {
                            if !searchText.isEmpty {
                                onLocationSelected(searchText)
                            }
                        }
                }
                .padding(12)
                .background(Color.backgroundGradientStart)
                .cornerRadius(12)
                .padding()

                Spacer()
            }
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
//
//  AITrainerApp.swift
//  AITrainer
//
//  AI Fitness Trainer - Main App Entry Point
//

import SwiftUI

@main
struct AITrainerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var notificationManager = NotificationManager()

    init() {
        // Configure app appearance
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(healthKitManager)
                .environmentObject(authManager)
                .environmentObject(notificationManager)
                .onAppear {
                    // Request permissions on app launch
                    healthKitManager.requestAuthorization()
                    notificationManager.requestAuthorization()
                }
        }
    }

    private func configureAppearance() {
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

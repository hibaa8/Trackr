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
    @StateObject private var backendConnector = FrontendBackendConnector.shared

    init() {
        // Configure app appearance
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(backendConnector)
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
        // Configure navigation bar appearance for dark theme
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // Configure tab bar appearance for dark theme
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.black

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}

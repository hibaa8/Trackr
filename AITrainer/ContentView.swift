//
//  ContentView.swift
//  AITrainer
//
//  Main navigation and authentication flow
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var backendConnector = FrontendBackendConnector.shared
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if authManager.hasCompletedOnboarding {
                    MainTabView(coach: Coach.allCoaches[0])
                } else {
                    WelcomeOnboardingView()
                }
            } else {
                WelcomeView()
            }
        }
        .onAppear {
            print("[ContentView] Appeared")
            authManager.checkAuthenticationStatus()
            backendConnector.initializeApp()
        }
        .onChange(of: authManager.hasCompletedOnboarding) { _, newValue in
            print("[ContentView] hasCompletedOnboarding changed -> \(newValue)")
        }
        .onChange(of: authManager.isAuthenticated) { _, newValue in
            print("[ContentView] isAuthenticated changed -> \(newValue)")
        }
        .environmentObject(backendConnector)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager())
        .environmentObject(HealthKitManager())
        .environmentObject(NotificationManager())
}

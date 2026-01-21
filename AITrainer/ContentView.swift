//
//  ContentView.swift
//  AITrainer
//
//  Main navigation and authentication flow
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if authManager.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            } else {
                WelcomeView()
            }
        }
        .onAppear {
            authManager.checkAuthenticationStatus()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager())
        .environmentObject(HealthKitManager())
        .environmentObject(NotificationManager())
}

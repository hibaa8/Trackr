//
//  ContentView.swift
//  AITrainer
//
//  Main navigation and authentication flow
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var appState: AppState
    @StateObject private var backendConnector = FrontendBackendConnector.shared
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if authManager.hasCompletedOnboarding {
                    MainTabView(coach: appState.selectedCoach ?? Coach.allCoaches[0])
                } else {
                    WelcomeOnboardingView()
                }
            } else {
                WelcomeView()
            }
        }
        .onAppear {
            authManager.checkAuthenticationStatus()
            backendConnector.initializeApp()
            loadSelectedCoach()
        }
        .environmentObject(backendConnector)
    }

    private func loadSelectedCoach() {
        let userId = authManager.demoUserId ?? 1
        backendConnector.loadProfile(userId: userId) { result in
            switch result {
            case .success(let profile):
                if let agentName = profile.user?.agent_name {
                    if let coach = Coach.allCoaches.first(where: { $0.name.lowercased() == agentName.lowercased() }) {
                        DispatchQueue.main.async {
                            appState.setSelectedCoach(coach)
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager())
        .environmentObject(HealthKitManager())
        .environmentObject(NotificationManager())
}

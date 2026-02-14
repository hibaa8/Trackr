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
    @State private var isPreparingDashboard = false
    @State private var preparingUserId: Int?
    
    var body: some View {
        Group {
            if authManager.forceLoginOnLaunch {
                WelcomeView()
            } else if authManager.isAuthenticated {
                if authManager.hasCompletedOnboarding {
                    if isPreparingDashboard {
                        DashboardLoadingView(coachName: appState.selectedCoach?.name)
                    } else {
                        MainTabView(coach: appState.selectedCoach ?? Coach.allCoaches[0])
                    }
                } else {
                    WelcomeOnboardingView()
                }
            } else {
                WelcomeView()
            }
        }
        .onAppear {
            authManager.forceShowLoginOnLaunch()
        }
        .onChange(of: authManager.currentUserId) { _, _ in
            prepareDashboardIfNeeded()
        }
        .onChange(of: authManager.demoUserId) { _, _ in
            prepareDashboardIfNeeded()
        }
        .onChange(of: authManager.isAuthenticated) { _, _ in
            prepareDashboardIfNeeded()
        }
        .onChange(of: authManager.hasCompletedOnboarding) { _, _ in
            prepareDashboardIfNeeded()
        }
        .environmentObject(backendConnector)
    }

    private func prepareDashboardIfNeeded() {
        guard authManager.isAuthenticated, authManager.hasCompletedOnboarding else {
            isPreparingDashboard = false
            preparingUserId = nil
            return
        }
        guard let userId = authManager.effectiveUserId else { return }
        if isPreparingDashboard && preparingUserId == userId { return }
        preparingUserId = userId
        isPreparingDashboard = true
        refreshForUser(userId: userId) {
            DispatchQueue.main.async {
                self.isPreparingDashboard = false
            }
        }
    }

    private func refreshForUser(userId: Int, completion: @escaping () -> Void) {
        backendConnector.initializeApp(userId: userId)
        appState.refreshDailyData(for: appState.selectedDate, userId: userId)
        backendConnector.hydrateSession(userId: userId) { result in
            switch result {
            case .success(let hydration):
                if let plan = hydration.today_plan {
                    DispatchQueue.main.async {
                        appState.todayPlan = plan
                    }
                }
                if let agentName = hydration.profile.user?.agent_name,
                   let coach = Coach.allCoaches.first(where: { $0.name.lowercased() == agentName.lowercased() }) {
                    DispatchQueue.main.async {
                        appState.setSelectedCoach(coach)
                    }
                }
                completion()
            case .failure:
                let group = DispatchGroup()
                group.enter()
                backendConnector.loadProfile(userId: userId) { _ in group.leave() }
                group.enter()
                backendConnector.loadProgress(userId: userId) { _ in group.leave() }
                group.notify(queue: .main) {
                    completion()
                }
            }
        }
    }
}

private struct DashboardLoadingView: View {
    let coachName: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                Text("Loading your dashboard...")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text(coachName != nil ? "Preparing data with \(coachName!)." : "Preparing your plan, meals, and progress.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager())
        .environmentObject(HealthKitManager())
        .environmentObject(NotificationManager())
}

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
    @EnvironmentObject var notificationManager: NotificationManager
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
                        MainTabView()
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
            loadCoachesCatalogIfNeeded()
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
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            guard authManager.isAuthenticated, let userId = authManager.effectiveUserId else { return }
            syncReminderNotifications(userId: userId)
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
        syncReminderNotifications(userId: userId)
        backendConnector.hydrateSession(userId: userId) { result in
            switch result {
            case .success(let hydration):
                if let plan = hydration.today_plan {
                    DispatchQueue.main.async {
                        appState.todayPlan = plan
                    }
                }
                let desiredCoachId = hydration.profile.user?.agent_id
                loadCoachesCatalogIfNeeded {
                    if let desiredCoachId,
                       let coach = appState.coaches.first(where: { $0.id == desiredCoachId }) {
                        DispatchQueue.main.async {
                            appState.setSelectedCoach(coach)
                        }
                    } else if appState.selectedCoach == nil, let firstCoach = appState.coaches.first {
                        DispatchQueue.main.async {
                            appState.setSelectedCoach(firstCoach)
                        }
                    }
                    completion()
                }
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

    private func loadCoachesCatalogIfNeeded(completion: (() -> Void)? = nil) {
        if !appState.coaches.isEmpty {
            completion?()
            return
        }
        backendConnector.loadCoaches { result in
            switch result {
            case .success(let coaches):
                DispatchQueue.main.async {
                    appState.coaches = coaches
                    if appState.selectedCoach == nil, let first = coaches.first {
                        appState.setSelectedCoach(first)
                    }
                    completion?()
                }
            case .failure(let error):
                print("Failed to load coaches: \(error)")
                completion?()
            }
        }
    }

    private func syncReminderNotifications(userId: Int) {
        let notificationsEnabled = UserDefaults.standard.object(forKey: "enableNotifications") as? Bool ?? true
        backendConnector.loadReminders(userId: userId) { result in
            switch result {
            case .success(let reminders):
                notificationManager.syncReminders(reminders, notificationsEnabled: notificationsEnabled)
            case .failure(let error):
                print("Failed to sync reminders: \(error)")
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

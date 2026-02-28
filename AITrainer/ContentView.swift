//
//  ContentView.swift
//  AITrainer
//
//  Main navigation and authentication flow
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("enableHealthSync") private var healthSyncEnabled = false
    @StateObject private var backendConnector = FrontendBackendConnector.shared
    @State private var isPreparingDashboard = false
    @State private var preparingUserId: Int?
    @State private var healthSyncCancellables = Set<AnyCancellable>()
    @State private var isAutoHealthSyncRunning = false
    
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
            triggerAutomaticHealthSyncIfNeeded(reason: "onAppear")
        }
        .onChange(of: authManager.currentUserId) { _, _ in
            prepareDashboardIfNeeded()
            triggerAutomaticHealthSyncIfNeeded(reason: "userIdChanged")
        }
        .onChange(of: authManager.demoUserId) { _, _ in
            prepareDashboardIfNeeded()
            triggerAutomaticHealthSyncIfNeeded(reason: "demoUserChanged")
        }
        .onChange(of: authManager.isAuthenticated) { _, _ in
            prepareDashboardIfNeeded()
            triggerAutomaticHealthSyncIfNeeded(reason: "authChanged")
        }
        .onChange(of: authManager.hasCompletedOnboarding) { _, _ in
            prepareDashboardIfNeeded()
            triggerAutomaticHealthSyncIfNeeded(reason: "onboardingChanged")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                triggerAutomaticHealthSyncIfNeeded(reason: "appBecameActive")
            }
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

    private func triggerAutomaticHealthSyncIfNeeded(reason: String) {
        guard healthSyncEnabled else { return }
        guard authManager.isAuthenticated, authManager.hasCompletedOnboarding else { return }
        guard let userId = authManager.effectiveUserId else { return }
        guard !isAutoHealthSyncRunning else { return }

        let todayKey = currentDayKey()
        let lastSyncKey = "healthSyncLastDate_user_\(userId)"
        let defaults = UserDefaults.standard
        if defaults.string(forKey: lastSyncKey) == todayKey {
            return
        }

        isAutoHealthSyncRunning = true
        if !healthKitManager.isAuthorized {
            healthKitManager.requestAuthorization()
        }

        // Syncing a two-day window covers overnight stragglers.
        healthKitManager.collectDailySnapshots(lastDays: 2) { snapshots in
            guard !snapshots.isEmpty else {
                isAutoHealthSyncRunning = false
                return
            }
            let publishers = snapshots.map { snapshot in
                APIService.shared.logHealthActivity(
                    HealthActivityLogRequest(
                        user_id: userId,
                        date: snapshot.date,
                        steps: snapshot.steps,
                        calories_burned: snapshot.caloriesBurned,
                        active_minutes: snapshot.activeMinutes,
                        workouts_summary: snapshot.workoutsSummary,
                        source: "apple_health"
                    )
                )
                .map { _ in true }
                .replaceError(with: false)
                .eraseToAnyPublisher()
            }

            Publishers.MergeMany(publishers)
                .collect()
                .receive(on: DispatchQueue.main)
                .sink { results in
                    let successCount = results.filter { $0 }.count
                    if successCount > 0 {
                        defaults.set(todayKey, forKey: lastSyncKey)
                    }
                    isAutoHealthSyncRunning = false
                    if successCount == 0 {
                        print("Automatic health sync (\(reason)) did not upload any day successfully.")
                    }
                }
                .store(in: &healthSyncCancellables)
        }
    }

    private func currentDayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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

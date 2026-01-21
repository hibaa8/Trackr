//
//  MainTabView.swift
//  AITrainer
//
//  Main tab navigation
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var showMealLogging = false

    var body: some View {
        TabView(selection: $selectedTab) {
            WireframeHomeDashboardView()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Home")
                }
                .tag(0)

            WireframeProgressView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis.circle")
                    Text("Progress")
                }
                .tag(1)

            // Snap tab (placeholder that opens sheet)
            Color.clear
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text("Snap")
                }
                .tag(2)

            CoachView()
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "sparkles" : "sparkles")
                    Text("Coach")
                }
                .tag(3)

            WireframeProfileView()
                .tabItem {
                    Image(systemName: selectedTab == 4 ? "person.fill" : "person")
                    Text("Profile")
                }
                .tag(4)
        }
        .accentColor(.blue)
        .onChange(of: selectedTab) { newValue in
            if newValue == 2 {
                showMealLogging = true
                selectedTab = 0 // Reset to home tab
            }
        }
        .sheet(isPresented: $showMealLogging) {
            MealLoggingView()
                .environmentObject(appState)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(HealthKitManager())
        .environmentObject(AuthenticationManager())
}

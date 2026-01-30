//
//  BackendDemoView.swift
//  AITrainer
//
//  Demo view showing frontend-backend integration
//

import SwiftUI

struct BackendDemoView: View {
    @EnvironmentObject var backendConnector: FrontendBackendConnector
    @State private var testMessage = "Hello AI coach, how should I start my workout today?"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Backend Health Status
                    healthStatusCard

                    // Daily Intake Card
                    dailyIntakeCard

                    // Weekly Calories Chart
                    weeklyCaloriesCard

                    // AI Coach Chat
                    coachChatCard

                    // Quick Actions
                    quickActionsCard

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Backend Demo")
            .navigationBarTitleDisplayMode(.large)
            .foregroundColor(.white)
        }
        .onAppear {
            backendConnector.initializeApp()
        }
    }

    private var healthStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.green)
                Text("Backend Status")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Text("✅ Backend is running and connected")
                .foregroundColor(.green)

            Button("Check Health") {
                backendConnector.checkBackendHealth()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }

    private var dailyIntakeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundColor(.orange)
                Text("Today's Intake")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            if let intake = backendConnector.dailyIntake {
                VStack(alignment: .leading, spacing: 8) {
                    Text("📊 \(intake.total_calories) calories")
                        .foregroundColor(.white)
                    Text("🥩 \(String(format: "%.1f", intake.total_protein_g))g protein")
                        .foregroundColor(.white)
                    Text("🍞 \(String(format: "%.1f", intake.total_carbs_g))g carbs")
                        .foregroundColor(.white)
                    Text("🥑 \(String(format: "%.1f", intake.total_fat_g))g fat")
                        .foregroundColor(.white)
                }
            } else {
                Text("Loading...")
                    .foregroundColor(.gray)
            }

            Button("Refresh Data") {
                backendConnector.loadDailyIntake()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }

    private var weeklyCaloriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Weekly Calories")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            HStack {
                ForEach(0..<7, id: \.self) { index in
                    VStack {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 30, height: CGFloat(backendConnector.weeklyCalories[index]) / 20)
                            .animation(.easeInOut, value: backendConnector.weeklyCalories[index])

                        Text("\\(backendConnector.weeklyCalories[index])")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }

            Button("Load Weekly Data") {
                backendConnector.loadWeeklyCalories()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }

    private var coachChatCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubble.left.fill")
                    .foregroundColor(.purple)
                Text("AI Coach")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            TextField("Ask your coach...", text: $testMessage)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if backendConnector.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Coach is thinking...")
                        .foregroundColor(.gray)
                }
            }

            if !backendConnector.coachResponse.isEmpty {
                Text("🤖 Coach: \\(backendConnector.coachResponse)")
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(8)
            }

            Button("Send Message") {
                backendConnector.sendMessageToCoach(testMessage)
            }
            .buttonStyle(.borderedProminent)
            .disabled(testMessage.isEmpty || backendConnector.isLoading)
        }
        .padding(16)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("Quick Actions")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Button("Load Videos") {
                    backendConnector.loadWorkoutVideos { result in
                        switch result {
                        case .success(let videos):
                            print("✅ Loaded \\(videos.count) videos")
                        case .failure(let error):
                            print("❌ Failed to load videos: \\(error)")
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Get Recipes") {
                    backendConnector.suggestRecipes { result in
                        switch result {
                        case .success(let recipes):
                            print("✅ Got \\(recipes.count) recipe suggestions")
                        case .failure(let error):
                            print("❌ Failed to get recipes: \\(error)")
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Find Gyms") {
                    // Using San Francisco coordinates as example
                    backendConnector.findNearbyGyms(latitude: 37.7749, longitude: -122.4194) { result in
                        switch result {
                        case .success(let gyms):
                            print("✅ Found \\(gyms.count) nearby gyms")
                        case .failure(let error):
                            print("❌ Failed to find gyms: \\(error)")
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Refresh All") {
                    backendConnector.initializeApp()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

#Preview {
    BackendDemoView()
        .environmentObject(FrontendBackendConnector.shared)
}
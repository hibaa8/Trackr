//
//  DashboardView.swift
//  AITrainer
//
//  Main dashboard screen - matches Figma design
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject var healthKitManager: HealthKitManager
    @State private var showAddMenu = false
    @State private var showGymClasses = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack {
                        Text("Cal AI")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("🔥")
                                .font(.title3)
                            Text("\(viewModel.currentStreak)")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Week Date Picker
                    WeekDatePicker(selectedDate: $viewModel.selectedDate)
                        .padding(.horizontal)
                    
                    // Main Calorie Circle
                    MainCalorieRing(
                        consumed: viewModel.caloriesConsumed,
                        target: viewModel.calorieTarget,
                        mealsRemaining: 6 - viewModel.mealsLogged
                    )
                    .frame(height: 300)
                    .padding(.horizontal)
                    
                    // Macro Rings
                    HStack(spacing: 20) {
                        MacroRing(
                            value: Int(viewModel.proteinEaten),
                            total: Int(viewModel.proteinTarget),
                            label: "Protein eaten",
                            gradient: LinearGradient.proteinGradient
                        )

                        MacroRing(
                            value: Int(viewModel.carbsEaten),
                            total: Int(viewModel.carbsTarget),
                            label: "Carbs eaten",
                            gradient: LinearGradient.carbsGradient
                        )

                        MacroRing(
                            value: Int(viewModel.fatEaten),
                            total: Int(viewModel.fatTarget),
                            label: "Fat eaten",
                            gradient: LinearGradient.fatsGradient
                        )
                    }
                    .padding(.horizontal)
                    
                    // Recently uploaded meals
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently uploaded")
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ForEach(viewModel.recentMeals) { meal in
                            ImprovedMealCard(meal: meal)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Calorie remaining message
                    if viewModel.caloriesConsumed < viewModel.calorieTarget {
                        CalorieRemainingMessage(
                            remaining: viewModel.calorieTarget - viewModel.caloriesConsumed
                        )
                        .padding(.horizontal)
                    }
                    
                    // Explore Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Explore")
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                ModernExploreCard(
                                    icon: "📍",
                                    iconColor: Color.blue,
                                    title: "Gym Classes",
                                    subtitle: "Find local sessions"
                                ) {
                                    showGymClasses = true
                                }

                                ModernExploreCard(
                                    icon: "💲",
                                    iconColor: Color.green,
                                    title: "Food Deals",
                                    subtitle: "Save on healthy meals"
                                )
                            }
                            
                            HStack(spacing: 12) {
                                ModernExploreCard(
                                    icon: "▶️",
                                    iconColor: Color.purple,
                                    title: "Workout Videos",
                                    subtitle: "Guided exercises"
                                )

                                ModernExploreCard(
                                    icon: "👥",
                                    iconColor: Color.orange,
                                    title: "Community",
                                    subtitle: "Connect with others"
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.vertical)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            
            .sheet(isPresented: $showAddMenu) {
                AddMenuView()
            }
            .fullScreenCover(isPresented: $showGymClasses) {
                GymClassesView()
            }
        }
        .onAppear {
            viewModel.loadDashboardData()
        }
    }
}
// MARK: - Improved Meal Card

struct ImprovedMealCard: View {
    let meal: FoodLog
    
    var body: some View {
        HStack(spacing: 12) {
            // Meal image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "F5E6D3"))
                .frame(width: 70, height: 70)
                .overlay(
                    Image(systemName: "fork.knife")
                        .foregroundColor(.gray.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(meal.name)
                    .font(.body)
                    .fontWeight(.semibold)
                
                HStack(spacing: 4) {
                    Text("🔥")
                        .font(.caption)
                    Text("\(meal.calories) Calories")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                HStack(spacing: 8) {
                    MacroEmojiLabel(emoji: "🥩", value: Int(meal.protein))
                    MacroEmojiLabel(emoji: "🍞", value: Int(meal.carbs))
                    MacroEmojiLabel(emoji: "🧈", value: Int(meal.fat))
                }
                
                Text(meal.formattedTime)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct MacroEmojiLabel: View {
    let emoji: String
    let value: Int
    
    var body: some View {
        HStack(spacing: 2) {
            Text(emoji)
                .font(.caption)
            Text("\(value)g")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}


// MARK: - Add Menu View

struct AddMenuView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Button(action: {
                    // Navigate to food scanner
                    dismiss()
                }) {
                    Label("Log Food", systemImage: "camera.fill")
                }
                
                Button(action: {
                    // Navigate to workout logger
                    dismiss()
                }) {
                    Label("Log Workout", systemImage: "figure.strengthtraining.traditional")
                }
                
                Button(action: {
                    // Navigate to weight logger
                    dismiss()
                }) {
                    Label("Log Weight", systemImage: "scalemass.fill")
                }
                
                Button(action: {
                    // Navigate to water logger
                    dismiss()
                }) {
                    Label("Log Water", systemImage: "drop.fill")
                }
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    DashboardView()
        .environmentObject(HealthKitManager())
}

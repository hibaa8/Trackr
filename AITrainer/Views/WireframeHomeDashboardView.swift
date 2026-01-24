import SwiftUI

struct WireframeHomeDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showMealLogging = false
    @State private var showDailyMeals = false
    @State private var showGymClasses = false
    @State private var showFoodDeals = false
    @State private var showWorkoutVideos = false
    @State private var showCommunity = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Stunning background gradient
                LinearGradient(
                    colors: [
                        Color.backgroundGradientStart,
                        Color.backgroundGradientEnd,
                        Color.white.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header section with refined spacing
                        headerSection
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // Date selector with elegant margins
                        WeekDatePicker(selectedDate: $appState.selectedDate)
                            .padding(.horizontal, 20)

                        // Hero calorie ring with breathing space
                        MainCalorieRing(
                            consumed: appState.caloriesIn,
                            target: appState.userData?.calorieTarget ?? 2000,
                            mealsRemaining: 6
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)

                        // Macro rings with consistent spacing
                        macroRingsSection
                            .padding(.horizontal, 20)

                        // Recent meals with refined layout
                        recentMealsSection
                            .padding(.horizontal, 20)

                        // Explore section with elegant spacing
                        exploreSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 80)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showMealLogging) {
                MealLoggingView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showDailyMeals) {
                DailyMealsView(meals: appState.meals, date: appState.selectedDate)
            }
            .sheet(isPresented: $showGymClasses) {
                GymClassesView()
            }
            .sheet(isPresented: $showFoodDeals) {
                FoodDealsView()
            }
            .sheet(isPresented: $showWorkoutVideos) {
                WorkoutVideosView()
            }
            .sheet(isPresented: $showCommunity) {
                CommunityView()
            }
            .onChange(of: appState.selectedDate) { newDate in
                appState.refreshDailyData(for: newDate)
            }
        }
    }

    var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Trainer")
                    .font(.displayMedium)
                    .fontWeight(.light)
                    .foregroundColor(.textPrimary)

                Text("Your fitness companion")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Streak indicator with modern design
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Text("🔥")
                        .font(.system(size: 16))
                }

                Text("15")
                    .font(.headlineMedium)
                    .foregroundColor(.orange)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.8))
            )
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    var macroRingsSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Today's Nutrition")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            HStack(spacing: 16) {
                MacroRing(
                    value: appState.proteinCurrent,
                    total: appState.proteinTarget,
                    label: "Protein eaten",
                    gradient: LinearGradient.proteinGradient
                )

                MacroRing(
                    value: appState.carbsCurrent,
                    total: appState.carbsTarget,
                    label: "Carbs eaten",
                    gradient: LinearGradient.carbsGradient
                )

                MacroRing(
                    value: appState.fatsCurrent,
                    total: appState.fatsTarget,
                    label: "Fat eaten",
                    gradient: LinearGradient.fatsGradient
                )
            }
        }
    }

    var recentMealsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Recent Activity")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button(action: { showDailyMeals = true }) {
                    Text("View All")
                        .font(.bodyMedium)
                        .foregroundColor(.fitnessGradientStart)
                }
            }

            if let lastMeal = appState.meals.first {
                ModernCard {
                    HStack(spacing: 20) {
                        // Enhanced meal image
                        ZStack {
                            // Background glow
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.carbsGradientStart.opacity(0.4), Color.carbsGradientEnd.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 88, height: 88)
                                .blur(radius: 12)

                            // Main image container with glassmorphism
                            RoundedRectangle(cornerRadius: 18)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.carbsGradientStart.opacity(0.3), Color.carbsGradientEnd.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )

                            // Food emoji
                            Text("🍽️")
                                .font(.system(size: 28))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(lastMeal.name)
                                .font(.headlineMedium)
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)

                            // Calories with enhanced styling
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.2))
                                        .frame(width: 24, height: 24)

                                    Text("🔥")
                                        .font(.system(size: 12))
                                }

                                Text("\(lastMeal.calories)")
                                    .font(.headlineMedium)
                                    .foregroundColor(.textPrimary)
                                    .fontWeight(.bold)

                                Text("Calories")
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)
                            }

                            // Modern macro display
                            HStack(spacing: 12) {
                                MacroTag(icon: "🥩", value: lastMeal.protein, unit: "g", gradient: LinearGradient.proteinGradient)
                                MacroTag(icon: "🍞", value: lastMeal.carbs, unit: "g", gradient: LinearGradient.carbsGradient)
                                MacroTag(icon: "🧈", value: lastMeal.fats, unit: "g", gradient: LinearGradient.fatsGradient)
                            }

                            Text(timeString(from: lastMeal.timestamp))
                                .font(.captionMedium)
                                .foregroundColor(.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(24)
                }
            }
        }
    }

    var dateSelector: some View {
        HStack(spacing: 0) {
            ModernIconButton(icon: "chevron.left", size: 40, gradient: LinearGradient(colors: [Color.textTertiary.opacity(0.3), Color.textTertiary.opacity(0.2)], startPoint: .leading, endPoint: .trailing)) {}
                .frame(width: 44)

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<7) { index in
                    VStack(spacing: 6) {
                        Text(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][index])
                            .font(.captionMedium)
                            .foregroundColor(index == 3 ? .textPrimary : .textTertiary)

                        Text("\(10 + index)")
                            .font(.bodyMedium)
                            .fontWeight(index == 3 ? .semibold : .regular)
                            .foregroundColor(index == 3 ? .white : .textPrimary)
                            .frame(width: 32, height: 32)
                            .background(
                                index == 3 ?
                                LinearGradient.fitnessGradient :
                                LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        index == 3 ?
                                        Color.clear :
                                        Color.textTertiary.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                    }
                }
            }

            Spacer()

            ModernIconButton(icon: "chevron.right", size: 40, gradient: LinearGradient(colors: [Color.textTertiary.opacity(0.3), Color.textTertiary.opacity(0.2)], startPoint: .leading, endPoint: .trailing)) {}
                .frame(width: 44)
        }
        .padding(.horizontal)
    }
    
    var calorieRing: some View {
        ZStack {
            CircularProgressView(
                value: Double(appState.caloriesIn),
                maxValue: Double(appState.userData?.calorieTarget ?? 2000),
                color: .black,
                lineWidth: 16,
                size: 180
            )
            
            VStack(spacing: 2) {
                Text("\(appState.caloriesIn)")
                    .font(.system(size: 48, weight: .bold))
                Text("/\(appState.userData?.calorieTarget ?? 2000)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Text("Calories eaten")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    
    
    var exploreSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore")
                        .font(.displayMedium)
                        .foregroundColor(.textPrimary)

                    Text("Discover new ways to stay fit")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Button(action: {}) {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.bodyMedium)

                        Image(systemName: "arrow.right")
                            .font(.captionMedium)
                    }
                    .foregroundColor(.fitnessGradientStart)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                EnhancedExploreCard(
                    icon: "🏃‍♂️",
                    iconColor: .blue,
                    title: "Gym Classes",
                    subtitle: "Find local sessions",
                    badge: "12 near you"
                ) {
                    showGymClasses = true
                }

                EnhancedExploreCard(
                    icon: "🍎",
                    iconColor: .green,
                    title: "Food Deals",
                    subtitle: "Save on healthy meals",
                    badge: "20% off"
                ) {
                    showFoodDeals = true
                }

                EnhancedExploreCard(
                    icon: "💪",
                    iconColor: .purple,
                    title: "Workout Videos",
                    subtitle: "Guided exercises",
                    badge: "New"
                ) {
                    showWorkoutVideos = true
                }

                EnhancedExploreCard(
                    icon: "👥",
                    iconColor: .orange,
                    title: "Community",
                    subtitle: "Connect with others",
                    badge: "1.2k online"
                ) {
                    showCommunity = true
                }
            }
        }
    }
    
    func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date)
    }
}

struct DailyMealsView: View {
    let meals: [MealEntry]
    let date: Date

    var body: some View {
        NavigationView {
            List {
                if meals.isEmpty {
                    Text("No meals logged for this day.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(meals) { meal in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meal.name)
                                .font(.headline)
                            Text("\(meal.calories) kcal • P \(meal.protein)g • C \(meal.carbs)g • F \(meal.fats)g")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(dayTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

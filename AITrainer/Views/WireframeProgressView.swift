import SwiftUI

struct WireframeProgressView: View {
    @State private var selectedTimeframe = 0
    let timeframes = ["Week", "Month", "Year"]
    
    // Sample data
    let weeklyCalories = [1800, 2100, 1900, 2200, 1850, 2000, 1950]
    let weeklyWeight = [180.0, 179.5, 179.2, 179.0, 178.8, 178.5, 178.3]
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
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
                    VStack(spacing: 24) {
                        // Modern header section
                        headerSection
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        // Enhanced timeframe selector
                        modernTimeframeSelector
                            .padding(.horizontal, 20)

                        // Weight progress with stunning design
                        weightProgressSection
                            .padding(.horizontal, 20)

                        // Calorie tracking with enhanced charts
                        calorieTrackingSection
                            .padding(.horizontal, 20)

                        // Achievements with modern cards
                        achievementsSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 80)
                    }
                    .padding(.top, 4)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.displayLarge)
                .foregroundColor(.textPrimary)

            Text("Track your fitness journey")
                .font(.bodyLarge)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modernTimeframeSelector: some View {
        ModernCard {
            HStack(spacing: 0) {
                ForEach(0..<timeframes.count, id: \.self) { index in
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedTimeframe = index
                        }
                    }) {
                        Text(timeframes[index])
                            .font(.bodyLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTimeframe == index ? .white : .textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                selectedTimeframe == index ?
                                LinearGradient.fitnessGradient :
                                LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(4)
        }
    }

    private var weightProgressSection: some View {
        VStack(spacing: 24) {
            // Section header
            HStack {
                Text("Weight Journey")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button(action: {}) {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.bodyMedium)
                        Image(systemName: "arrow.right")
                            .font(.captionMedium)
                    }
                    .foregroundColor(.fitnessGradientStart)
                }
            }

            // Weight stats card
            ModernCard {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("178.3 lbs")
                            .font(.displayMedium)
                            .foregroundColor(.textPrimary)

                        Text("Current Weight")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 32, height: 32)

                                Image(systemName: "arrow.down")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.green)
                            }

                            Text("-1.7 lbs")
                                .font(.headlineMedium)
                                .foregroundColor(.green)
                                .fontWeight(.bold)
                        }

                        Text("This week")
                            .font(.captionLarge)
                            .foregroundColor(.textTertiary)
                    }
                }
                .padding(24)
            }

            // Enhanced weight chart
            ModernWeightChartView(data: weeklyWeight, labels: days)
        }
    }

    private var calorieTrackingSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Calorie Insights")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            ModernCalorieChartView(data: weeklyCalories, labels: days)
        }
    }

    private var achievementsSection: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Achievements")
                        .font(.headlineLarge)
                        .foregroundColor(.textPrimary)

                    Text("Your milestones")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ModernAchievementCard(
                    icon: "🔥",
                    title: "15 Day Streak",
                    description: "Keep it going!",
                    gradient: LinearGradient.fitnessGradient
                )

                ModernAchievementCard(
                    icon: "🎯",
                    title: "Goal Met",
                    description: "5 days this week",
                    gradient: LinearGradient.proteinGradient
                )

                ModernAchievementCard(
                    icon: "💪",
                    title: "Workouts",
                    description: "12 completed",
                    gradient: LinearGradient.carbsGradient
                )

                ModernAchievementCard(
                    icon: "📸",
                    title: "Meals Logged",
                    description: "45 total",
                    gradient: LinearGradient.fatsGradient
                )
            }
        }
    }
}

struct ModernWeightChartView: View {
    let data: [Double]
    let labels: [String]

    var body: some View {
        ModernCard {
            VStack(spacing: 20) {
                HStack {
                    Text("Weight Trend")
                        .font(.headlineMedium)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    HStack(spacing: 8) {
                        Circle()
                            .fill(LinearGradient.fitnessGradient)
                            .frame(width: 8, height: 8)

                        Text("Trending Down")
                            .font(.captionLarge)
                            .foregroundColor(.green)
                    }
                }

                GeometryReader { geometry in
                    let maxValue = data.max() ?? 180
                    let minValue = data.min() ?? 178
                    let range = maxValue - minValue
                    let height = geometry.size.height - 40
                    let width = geometry.size.width
                    let stepX = width / CGFloat(data.count - 1)

                    ZStack {
                        // Background grid lines
                        ForEach(0..<4) { index in
                            let y = CGFloat(index) * height / 3
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: width, y: y))
                            }
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        }

                        // Gradient area under the line
                        Path { path in
                            for (index, value) in data.enumerated() {
                                let x = CGFloat(index) * stepX
                                let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                                let y = height - (CGFloat(normalizedValue) * height)

                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: height))
                                    path.addLine(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }

                                if index == data.count - 1 {
                                    path.addLine(to: CGPoint(x: x, y: height))
                                    path.closeSubpath()
                                }
                            }
                        }
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.3), Color.green.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))

                        // Main trend line
                        Path { path in
                            for (index, value) in data.enumerated() {
                                let x = CGFloat(index) * stepX
                                let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                                let y = height - (CGFloat(normalizedValue) * height)

                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )

                        // Data points with glow
                        ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                            let x = CGFloat(index) * stepX
                            let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                            let y = height - (CGFloat(normalizedValue) * height)

                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                    .blur(radius: 4)
                                    .opacity(0.6)

                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 4, height: 4)
                                    )
                            }
                            .position(x: x, y: y)
                        }

                        // Day labels
                        HStack(spacing: 0) {
                            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                                Text(label)
                                    .font(.captionMedium)
                                    .foregroundColor(.textTertiary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .offset(y: height + 20)
                    }
                }
                .frame(height: 180)
            }
            .padding(24)
        }
    }
}

struct ModernCalorieChartView: View {
    let data: [Int]
    let labels: [String]

    var body: some View {
        ModernCard {
            VStack(spacing: 20) {
                HStack {
                    Text("Daily Calories")
                        .font(.headlineMedium)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Avg: \(Int(data.reduce(0, +) / data.count))")
                            .font(.captionLarge)
                            .foregroundColor(.textPrimary)
                            .fontWeight(.semibold)

                        Text("calories/day")
                            .font(.captionMedium)
                            .foregroundColor(.textTertiary)
                    }
                }

                GeometryReader { geometry in
                    let maxValue = CGFloat(data.max() ?? 2200)
                    let height = geometry.size.height - 30
                    let totalSpacing = CGFloat(data.count - 1) * 6
                    let barWidth = (geometry.size.width - totalSpacing) / CGFloat(data.count)

                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottom) {
                                    // Background bar
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(width: barWidth, height: height)

                                    // Progress bar with gradient
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient.fitnessGradient)
                                        .frame(width: barWidth, height: (CGFloat(value) / maxValue) * height)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )

                                    // Value label on hover effect
                                    Text("\(value)")
                                        .font(.captionMedium)
                                        .foregroundColor(.white)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.7))
                                        .cornerRadius(4)
                                        .offset(y: -8)
                                        .opacity((CGFloat(value) / maxValue) > 0.8 ? 1.0 : 0.0)
                                }

                                Text(labels[index])
                                    .font(.captionMedium)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
            .padding(24)
        }
    }
}

struct ModernAchievementCard: View {
    let icon: String
    let title: String
    let description: String
    let gradient: LinearGradient

    @State private var isPressed = false

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(gradient.opacity(0.25))
                            .frame(width: 56, height: 56)
                            .blur(radius: 8)

                        Circle()
                            .fill(gradient.opacity(0.2))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )

                        Text(icon)
                            .font(.system(size: 20))
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headlineMedium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text(description)
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(20)
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                }
            }
        }
    }
}

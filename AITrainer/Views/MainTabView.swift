import SwiftUI

struct MainTabView: View {
    let coach: Coach
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Trainer Tab
            TrainerMainView(coach: coach)
                .tabItem {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("Trainer")
                }
                .tag(0)

            // Progress Tab
            ProgressPageView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Progress")
                }
                .tag(1)

            // Settings Tab
            SettingsPageView(coach: coach)
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(2)
        }
        .accentColor(.blue)
        .preferredColorScheme(.dark)
    }
}

// Progress Page matching screen 10 mockup
struct ProgressPageView: View {
    @State private var selectedPeriod = 0
    private let periods = ["Week", "Month", "Year"]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView

                        // Weight Journey Card
                        weightJourneyCard

                        // Calorie Insights Card
                        calorieInsightsCard

                        // Workout Completion Card
                        workoutCompletionCard

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                }

                // Bottom toolbar
                VStack {
                    Spacer()
                    bottomToolbar
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var headerView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Progress")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }

            // Period selector
            HStack(spacing: 0) {
                ForEach(0..<periods.count, id: \.self) { index in
                    Button(action: {
                        selectedPeriod = index
                    }) {
                        Text(periods[index])
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedPeriod == index ? .white : .white.opacity(0.6))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedPeriod == index ? Color.blue : Color.clear)
                            )
                    }
                }
                Spacer()
            }
        }
        .padding(.top, 60)
    }

    private var weightJourneyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Weight Journey")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("178.3 lbs")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                HStack {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.green)
                    Text("-1.7 lbs")
                        .foregroundColor(.green)
                        .font(.system(size: 14, weight: .medium))
                }
            }

            // Simulated weight chart
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.2))
                    .frame(height: 80)

                // Mock chart line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 40))
                    path.addQuadCurve(to: CGPoint(x: 300, y: 60), control: CGPoint(x: 150, y: 20))
                }
                .stroke(Color.blue, lineWidth: 2)
                .frame(height: 80)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var calorieInsightsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Calorie Insights")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.6))
            }

            // Mock bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    VStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == 3 ? Color.blue : Color.blue.opacity(0.5))
                            .frame(width: 20, height: CGFloat.random(in: 40...80))

                        Text(["S", "M", "T", "W", "T", "F", "S"][index])
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .frame(height: 100)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var workoutCompletionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Workout Completion")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: 0.85)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    Text("85%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(20)), count: 7), spacing: 4) {
                    ForEach(0..<28, id: \.self) { day in
                        Circle()
                            .fill(day % 3 == 0 ? Color.blue : (day % 5 == 0 ? Color.clear : Color.white.opacity(0.3)))
                            .frame(width: 16, height: 16)
                    }
                }
                .frame(width: 140)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Button(action: {}) {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.4))
            }

            Spacer()

            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "camera")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.4))
            }
        }
        .frame(height: 80)
        .padding(.horizontal, 20)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .backdrop(blur: 20)
        )
    }
}

// Settings Page matching screen 11 mockup
struct SettingsPageView: View {
    let coach: Coach
    @State private var notificationsEnabled = true
    @State private var healthSyncEnabled = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView

                        // User Profile Card
                        userProfileCard

                        // Current Coach Card
                        currentCoachCard

                        // Settings List
                        settingsList

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                }

                // Bottom toolbar
                VStack {
                    Spacer()
                    bottomToolbar
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var headerView: some View {
        HStack {
            Text("Setting")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Button(action: {}) {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.top, 60)
    }

    private var userProfileCard: some View {
        HStack(spacing: 16) {
            // Profile image placeholder
            Circle()
                .fill(Color.gray)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Harry Chen")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text("Height: 180 cm | Weight: 75 kg | Age: 28")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var currentCoachCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Coach")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }

            HStack(spacing: 16) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(coach.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)

                    Text(coach.title)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Button("Change Coach") {
                    // Handle coach change
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue, lineWidth: 1)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue, lineWidth: 1)
                .background(Color.clear)
        )
    }

    private var settingsList: some View {
        VStack(spacing: 16) {
            SettingsRow(title: "Notifications", toggle: $notificationsEnabled)
            SettingsRow(title: "Units", value: "Imperial")
            SettingsRow(title: "Language", value: "English")
            SettingsRow(title: "Apple Health Sync", toggle: $healthSyncEnabled)
            SettingsRow(title: "Subscription", value: "Premium", highlight: true)

            Divider()
                .background(Color.white.opacity(0.2))

            SettingsRow(title: "Help & Feedback")
            SettingsRow(title: "Privacy Policy")
            SettingsRow(title: "Log Out", isDestructive: true)
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Button(action: {}) {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.4))
            }

            Spacer()

            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "camera")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.4))
            }
        }
        .frame(height: 80)
        .padding(.horizontal, 20)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .backdrop(blur: 20)
        )
    }
}

struct SettingsRow: View {
    let title: String
    var value: String? = nil
    var toggle: Binding<Bool>? = nil
    var highlight: Bool = false
    var isDestructive: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isDestructive ? .red : .white)

            Spacer()

            if let toggle = toggle {
                Toggle("", isOn: toggle)
                    .labelsHidden()
            } else if let value = value {
                Text(value)
                    .font(.system(size: 16))
                    .foregroundColor(highlight ? .blue : .white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        highlight ? RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.2)) : nil
                    )
            }
        }
        .padding(.vertical, 12)
    }
}

// Extension for backdrop blur
extension View {
    func backdrop(blur radius: CGFloat) -> some View {
        self.background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: radius)
        )
    }
}

#Preview {
    MainTabView(coach: Coach.allCoaches[0])
}
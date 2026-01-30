import SwiftUI
import Combine

struct MainTabView: View {
    let coach: Coach
    @State private var selectedTab = 1 // 0=Progress, 1=Trainer, 2=Settings
    @State private var showVoiceChat = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // Progress Page
                ProgressPageView()
                    .tag(0)

                // Trainer Page (default)
                TrainerMainViewContent(coach: coach)
                    .tag(1)

                // Settings Page
                SettingsPageView(coach: coach)
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .preferredColorScheme(.dark)

            // Global bottom toolbar
            VStack {
                Spacer()
                globalBottomToolbar
            }
        }
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(coach: coach)
        }
    }

    private var globalBottomToolbar: some View {
        HStack(spacing: 0) {
            // Keyboard icon
            Button(action: {}) {
                Image(systemName: "keyboard")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(0.6))
                    )
            }

            Spacer()

            // Voice microphone (main action)
            Button(action: {
                showVoiceChat = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // Camera icon
            Button(action: {}) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(0.6))
                    )
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 24)
        .padding(.bottom, 25)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial.opacity(0.9))
                .background(Color.black.opacity(0.4))
        )
        .padding(.horizontal, 20)
    }
}

// Progress Page matching screen 10 mockup
struct ProgressPageView: View {
    @State private var selectedPeriod = 0
    @State private var weeklyCalories: [Int] = [700, 850, 920, 850, 1100, 1200, 980]
    @State private var dailyIntake: DailyIntakeResponse?
    @State private var cancellables = Set<AnyCancellable>()
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
        .padding(.top, 50)
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
                    .font(.system(size: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("178.3 lbs")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("-1.7 lbs")
                        .foregroundColor(.green)
                        .font(.system(size: 14, weight: .medium))
                }
            }

            // Blue wave chart matching mockup
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 100)

                // Blue wave area
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 60))
                    path.addCurve(to: CGPoint(x: 80, y: 45), control1: CGPoint(x: 20, y: 50), control2: CGPoint(x: 60, y: 40))
                    path.addCurve(to: CGPoint(x: 160, y: 50), control1: CGPoint(x: 100, y: 48), control2: CGPoint(x: 140, y: 52))
                    path.addCurve(to: CGPoint(x: 240, y: 35), control1: CGPoint(x: 180, y: 45), control2: CGPoint(x: 220, y: 30))
                    path.addCurve(to: CGPoint(x: 320, y: 40), control1: CGPoint(x: 260, y: 38), control2: CGPoint(x: 300, y: 42))
                    path.addLine(to: CGPoint(x: 320, y: 100))
                    path.addLine(to: CGPoint(x: 0, y: 100))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Blue line on top
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 60))
                    path.addCurve(to: CGPoint(x: 80, y: 45), control1: CGPoint(x: 20, y: 50), control2: CGPoint(x: 60, y: 40))
                    path.addCurve(to: CGPoint(x: 160, y: 50), control1: CGPoint(x: 100, y: 48), control2: CGPoint(x: 140, y: 52))
                    path.addCurve(to: CGPoint(x: 240, y: 35), control1: CGPoint(x: 180, y: 45), control2: CGPoint(x: 220, y: 30))
                    path.addCurve(to: CGPoint(x: 320, y: 40), control1: CGPoint(x: 260, y: 38), control2: CGPoint(x: 300, y: 42))
                }
                .stroke(Color.blue, lineWidth: 2)
                .frame(height: 100)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.6))
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
                    .font(.system(size: 14))
            }

            // Detailed bar chart matching mockup
            ZStack {
                VStack(spacing: 0) {
                    // Y-axis labels and chart area
                    HStack {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("1500").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Text("1000").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Text("500").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Text("0").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 30)

                        // Bar chart
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(Array(zip([40, 60, 65, 45, 70, 55, 75, 50, 85, 70, 80, 90, 85].indices, [40, 60, 65, 45, 70, 55, 75, 50, 85, 70, 80, 90, 85])), id: \.0) { index, height in
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(index == 9 ? Color.blue : Color.blue.opacity(0.7))
                                        .frame(width: 12, height: CGFloat(height))

                                    if index % 4 == 1 {
                                        Text(["Sun", "Wed", "High"][index / 4])
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                            }
                        }

                        VStack(alignment: .trailing, spacing: 20) {
                            Text("120").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Text("80").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Text("40").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Text("0").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 30)
                    }

                    // Highlight current day value
                    HStack {
                        Spacer()
                        Text("180.3")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .offset(y: -60)
                }
            }
            .frame(height: 120)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.6))
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
                    .font(.system(size: 14))
            }

            HStack(spacing: 24) {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 8)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: 0.85)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))

                    Text("85%")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    // Calendar header
                    HStack(spacing: 8) {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 16)
                        }
                    }

                    // Calendar grid - 4 weeks
                    VStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { week in
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { day in
                                    let dayIndex = week * 7 + day
                                    let isWorkoutDay = [2, 4, 6, 8, 10, 13, 15, 17, 20, 22, 24, 26].contains(dayIndex)
                                    let isToday = dayIndex == 18

                                    Circle()
                                        .fill(isWorkoutDay ? Color.blue : Color.white.opacity(0.2))
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle()
                                                .stroke(isToday ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.6))
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
        .padding(.top, 50)
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
import SwiftUI
import Combine

struct MainTabView: View {
    let coach: Coach
    @State private var selectedTab = 1 // 0=Progress, 1=Trainer, 2=Settings
    @State private var showVoiceChat = false
    @State private var focusChatOnOpen = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Progress Page
            ZStack {
                ProgressPageView()
                VStack {
                    Spacer()
                    globalBottomToolbar
                }
            }
            .tag(0)

            // Trainer Page (default)
            ZStack {
                TrainerMainViewContent(coach: coach)
                VStack {
                    Spacer()
                    globalBottomToolbar
                }
            }
            .tag(1)

            // Settings Page
            ZStack {
                SettingsPageView(coach: coach)
                VStack {
                    Spacer()
                    globalBottomToolbar
                }
            }
            .tag(2)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(coach: coach, autoFocus: focusChatOnOpen)
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
            .onTapGesture {
                focusChatOnOpen = true
                showVoiceChat = true
            }

            Spacer()

            // Voice microphone (main action)
            Button(action: {
                focusChatOnOpen = false
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
    @EnvironmentObject private var backendConnector: FrontendBackendConnector
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var selectedPeriod = 0
    @State private var weeklyCalories: [Int] = Array(repeating: 0, count: 7)
    @State private var progress: ProgressResponse?
    private let periods = ["Week", "Month", "Year"]
    private let calendar = Calendar.current

    private var dayKeyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

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
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadProgressData()
        }
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
                Text(latestWeightText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Image(systemName: weightDeltaIcon)
                        .foregroundColor(weightDeltaColor)
                        .font(.system(size: 12))
                    Text(weightDeltaText)
                        .foregroundColor(weightDeltaColor)
                        .font(.system(size: 14, weight: .medium))
                }

                Text(nextCheckpointText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 100)

                if weightSeries.count >= 2 {
                    GeometryReader { proxy in
                        let rect = CGRect(origin: .zero, size: proxy.size)
                        ZStack {
                            weightAreaPath(in: rect)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            weightLinePath(in: rect)
                                .stroke(Color.blue, lineWidth: 2)
                        }
                    }
                } else {
                    Text("No weight data yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
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
                            let maxValue = max(weeklyCalories.max() ?? 0, 1)
                            ForEach(Array(weeklyCalories.enumerated()), id: \.offset) { index, value in
                                let height = CGFloat(value) / CGFloat(maxValue) * 90
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(index == weeklyCalories.count - 1 ? Color.blue : Color.blue.opacity(0.7))
                                        .frame(width: 12, height: max(6, height))

                                    if index % 3 == 0 {
                                        Text(shortDayLabel(offsetFromToday: weeklyCalories.count - 1 - index))
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
                        Text(latestCaloriesText)
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
                        .trim(from: 0, to: workoutCompletionRatio)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(workoutCompletionRatio * 100))%")
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
                                    let date = calendar.date(byAdding: .day, value: dayIndex - 27, to: Date())
                                    let dateKey = date.map { dayKeyFormatter.string(from: $0) }
                                    let isWorkoutDay = dateKey.map { workoutDateKeys.contains($0) } ?? false
                                    let isToday = dateKey == dayKeyFormatter.string(from: Date())

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

    private func loadProgressData() {
        let userId = authManager.demoUserId ?? 1
        backendConnector.loadProgress(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    progress = response
                    weeklyCalories = buildWeeklyCalories(from: response.meals)
                case .failure:
                    break
                }
            }
        }
    }

    private func buildWeeklyCalories(from meals: [ProgressMealResponse]) -> [Int] {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
        var totals = Array(repeating: 0, count: days.count)
        for meal in meals {
            guard let loggedAt = meal.logged_at else { continue }
            let dayKey = String(loggedAt.prefix(10))
            for (idx, day) in days.enumerated() {
                if dayKeyFormatter.string(from: day) == dayKey {
                    totals[days.count - 1 - idx] += meal.calories ?? 0
                    break
                }
            }
        }
        return totals
    }

    private var sortedCheckins: [ProgressCheckinResponse] {
        (progress?.checkins ?? []).sorted { $0.date < $1.date }
    }

    private var weightSeries: [Double] {
        let values = sortedCheckins.compactMap { $0.weight_kg }.map { $0 * 2.20462 }
        return Array(values.suffix(7))
    }

    private func weightLinePath(in rect: CGRect) -> Path {
        let points = weightChartPoints(in: rect)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func weightAreaPath(in rect: CGRect) -> Path {
        let points = weightChartPoints(in: rect)
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: rect.height))
        for point in points {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: rect.height))
        path.closeSubpath()
        return path
    }

    private func weightChartPoints(in rect: CGRect) -> [CGPoint] {
        let values = weightSeries
        guard values.count >= 2 else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 1)
        return values.enumerated().map { index, value in
            let x = rect.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let y = rect.height - rect.height * CGFloat((value - minValue) / range)
            return CGPoint(x: x, y: y)
        }
    }

    private var latestWeightText: String {
        guard let kg = sortedCheckins.last?.weight_kg else { return "—" }
        return String(format: "%.1f lbs", kg * 2.20462)
    }

    private var weightDeltaText: String {
        guard sortedCheckins.count >= 2,
              let last = sortedCheckins.last?.weight_kg,
              let prev = sortedCheckins.dropLast().last?.weight_kg
        else { return "No recent change" }
        let delta = (last - prev) * 2.20462
        let sign = delta >= 0 ? "+" : ""
        return String(format: "%@%.1f lbs", sign, delta)
    }

    private var weightDeltaIcon: String {
        guard sortedCheckins.count >= 2,
              let last = sortedCheckins.last?.weight_kg,
              let prev = sortedCheckins.dropLast().last?.weight_kg
        else { return "minus" }
        return last <= prev ? "arrow.down" : "arrow.up"
    }

    private var weightDeltaColor: Color {
        guard sortedCheckins.count >= 2,
              let last = sortedCheckins.last?.weight_kg,
              let prev = sortedCheckins.dropLast().last?.weight_kg
        else { return .white.opacity(0.6) }
        return last <= prev ? .green : .red
    }

    private var nextCheckpointText: String {
        guard let checkpoint = progress?.checkpoints.first else {
            return "No checkpoints yet"
        }
        let expected = checkpoint.expected_weight_kg * 2.20462
        let min = checkpoint.min_weight_kg * 2.20462
        let max = checkpoint.max_weight_kg * 2.20462
        return String(format: "Week %d target: %.1f lbs (%.1f–%.1f)", checkpoint.week, expected, min, max)
    }

    private var latestCaloriesText: String {
        guard let latest = weeklyCalories.last else { return "—" }
        return "\(latest) kcal"
    }

    private var workoutCompletionRatio: Double {
        let workouts = progress?.workouts ?? []
        let recent = workouts.filter { workout in
            guard let dateStr = workout.date,
                  let date = dayKeyFormatter.date(from: dateStr)
            else { return false }
            let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            return days <= 6 && (workout.completed ?? false)
        }
        return min(1.0, Double(recent.count) / 7.0)
    }

    private var workoutDateKeys: Set<String> {
        return Set((progress?.workouts ?? []).compactMap { workout in
            guard workout.completed == true, let date = workout.date else { return nil }
            return date
        })
    }

    private func shortDayLabel(offsetFromToday: Int) -> String {
        guard let date = calendar.date(byAdding: .day, value: -offsetFromToday, to: Date()) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// Settings Page matching screen 11 mockup
struct SettingsPageView: View {
    let coach: Coach
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var backendConnector: FrontendBackendConnector
    @State private var notificationsEnabled = true
    @State private var healthSyncEnabled = false
    @State private var profileUser: ProfileUserResponse?

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
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            let userId = authManager.demoUserId ?? 1
            backendConnector.loadProfile(userId: userId) { result in
                if case .success(let response) = result {
                    profileUser = response.user
                }
            }
        }
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
                Text(profileUser?.name?.isEmpty == false ? profileUser?.name ?? "" : "Your Profile")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text(profileStatsText)
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

    private var profileStatsText: String {
        let heightText = profileUser?.height_cm.map { String(format: "%.0f cm", $0) } ?? "--"
        let weightText = profileUser?.weight_kg.map { String(format: "%.0f kg", $0) } ?? "--"
        let ageText = profileAgeText
        return "Height: \(heightText) | Weight: \(weightText) | Age: \(ageText)"
    }

    private var profileAgeText: String {
        guard let birthdate = profileUser?.birthdate else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: birthdate) else {
            return "--"
        }
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
        return years > 0 ? "\(years)" : "--"
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
            SettingsRow(title: "Log Out", isDestructive: true) {
                authManager.signOut()
            }
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
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack {
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

        if let action = action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
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
        .environmentObject(FrontendBackendConnector.shared)
}

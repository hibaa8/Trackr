import SwiftUI
import Combine

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 1 // 0=Progress, 1=Trainer, 2=Explore, 3=Settings

    private var coach: Coach {
        appState.selectedCoach ?? appState.coaches.first ?? Coach.placeholder
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Progress Page
            ProgressPageView()
            .tag(0)
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }

            // Trainer Page (default)
            TrainerMainViewContent(coach: coach)
            .tag(1)
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            // Explore Page
            ExplorePageView(coach: coach)
                .tag(2)
                .tabItem {
                    Label("Explore", systemImage: "safari.fill")
                }

            // Settings Page
            SettingsPageView(coach: coach)
            .tag(3)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .openDashboardTab)) { _ in
            selectedTab = 1
        }
    }
}

struct ExplorePageView: View {
    let coach: Coach
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var showVoiceChat = false
    @State private var chatPrompt: String?
    @State private var showRecipePlanner = false
    @State private var showGymFinder = false
    @State private var showGymLocationPrompt = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Explore")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 22)

                        Text("Discover more ways to improve your fitness.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))
                            .padding(.bottom, 4)

                        exploreButton(
                            title: "Plan Meals",
                            subtitle: "Build meal ideas and calorie-smart menus.",
                            systemImage: "fork.knife.circle.fill"
                        ) {
                            showRecipePlanner = true
                        }

                        exploreButton(
                            title: "Learn Exercise",
                            subtitle: "Get coached on form, progressions, and mistakes.",
                            systemImage: "figure.strengthtraining.functional"
                        ) {
                            chatPrompt = "Teach me an exercise with proper form. Ask which exercise I want to learn, then give setup cues, common mistakes, regressions, and progressions."
                            showVoiceChat = true
                        }

                        exploreButton(
                            title: "Find Gym",
                            subtitle: "Search nearby gyms and classes.",
                            systemImage: "mappin.and.ellipse"
                        ) {
                            showGymLocationPrompt = true
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showVoiceChat) {
            VoiceActiveView(
                coach: coach,
                autoFocus: true,
                startRecording: false,
                initialPrompt: chatPrompt ?? "Teach me an exercise with proper form."
            )
            .environmentObject(appState)
            .environmentObject(authManager)
        }
        .fullScreenCover(isPresented: $showRecipePlanner) {
            RecipeFinderView()
        }
        .fullScreenCover(isPresented: $showGymFinder) {
            GymClassesView()
        }
        .confirmationDialog("Share location to find gyms", isPresented: $showGymLocationPrompt, titleVisibility: .visible) {
            Button("Share Location") {
                showGymFinder = true
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("We use your location to find nearby gyms. Without location, local gym search stays off.")
        }
    }

    private func exploreButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.blue.opacity(0.95))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// Progress Page matching screen 10 mockup
struct ProgressPageView: View {
    @EnvironmentObject private var backendConnector: FrontendBackendConnector
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var selectedPeriod = 0
    @State private var weeklyCalories: [Int] = Array(repeating: 0, count: 7)
    @State private var progress: ProgressResponse?
    @State private var profileUser: ProfileUserResponse?
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
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            loadProgressData()
        }
        .onChange(of: selectedPeriod) { _, _ in
            weeklyCalories = buildPeriodCalories(from: progress?.meals ?? [])
        }
    }

    private var headerView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Progress")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Spacer()
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

                NavigationLink(
                    destination: WorkoutLogsHistoryView(
                        workouts: filteredWorkoutsForSelectedPeriod,
                        periodLabel: periods[selectedPeriod],
                        dayWindow: selectedPeriodDayWindow
                    )
                ) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14))
                }
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

                if weightSeries.count >= 1 {
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
                            if weightSeries.count == 1, let onlyPoint = weightChartPoints(in: rect).first {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .position(onlyPoint)
                            }
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

                NavigationLink(
                    destination: NetCaloriesDetailView(
                        data: netCaloriesSeries,
                        periodLabel: periods[selectedPeriod]
                    )
                ) {
                    HStack(spacing: 6) {
                        Text("Net Details")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
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

                        ScrollView(.horizontal, showsIndicators: false) {
                            // Keep card width fixed; only chart content scrolls on Month/Year.
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
                            .frame(minWidth: max(120, CGFloat(weeklyCalories.count) * 18), alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)

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
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Workout Completion")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                NavigationLink(
                    destination: WorkoutLogsHistoryView(
                        workouts: filteredWorkoutsForSelectedPeriod,
                        periodLabel: periods[selectedPeriod],
                        dayWindow: selectedPeriodDayWindow
                    )
                ) {
                    HStack(spacing: 8) {
                        Text("Show Logs")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 14))
                    }
                }
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
                            workoutWeekRow(week: week)
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

    private func workoutWeekRow(week: Int) -> some View {
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

    private var selectedPeriodDayWindow: Int {
        switch selectedPeriod {
        case 0: return 7
        case 1: return 30
        default: return 256
        }
    }

    private var filteredWorkoutsForSelectedPeriod: [ProgressWorkoutResponse] {
        guard let workouts = progress?.workouts else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let earliest = calendar.date(byAdding: .day, value: -(selectedPeriodDayWindow - 1), to: today) else {
            return workouts
        }
        return workouts
            .filter { workout in
                guard let date = workoutDate(from: workout.date) else { return false }
                let day = calendar.startOfDay(for: date)
                return day >= earliest && day <= today
            }
            .sorted { lhs, rhs in
                (workoutDate(from: lhs.date) ?? .distantPast) > (workoutDate(from: rhs.date) ?? .distantPast)
            }
    }

    private func workoutDate(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let lowered = value.lowercased()
        let calendar = Calendar.current
        if lowered == "today" || lowered == "now" {
            return Date()
        }
        if lowered == "yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: Date())
        }
        if let weekMatch = lowered.range(of: #"^(\d+)\s*week(s)?\s*ago$"#, options: .regularExpression) {
            let token = String(lowered[weekMatch])
            let digits = token.filter(\.isNumber)
            if let weeks = Int(digits) {
                return calendar.date(byAdding: .day, value: -(weeks * 7), to: Date())
            }
        }
        if let dayMatch = lowered.range(of: #"^(\d+)\s*day(s)?\s*ago$"#, options: .regularExpression) {
            let token = String(lowered[dayMatch])
            let digits = token.filter(\.isNumber)
            if let days = Int(digits) {
                return calendar.date(byAdding: .day, value: -days, to: Date())
            }
        }
        let isoFormatter = ISO8601DateFormatter()
        if let isoDate = isoFormatter.date(from: value) {
            return isoDate
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
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
        guard let userId = authManager.effectiveUserId else { return }
        backendConnector.loadProgress(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    progress = response
                    weeklyCalories = buildPeriodCalories(from: response.meals)
                case .failure:
                    break
                }
            }
        }
        backendConnector.loadProfile(userId: userId) { result in
            if case .success(let response) = result {
                profileUser = response.user
            }
        }
    }

    private func buildPeriodCalories(from meals: [ProgressMealResponse]) -> [Int] {
        let calendar = Calendar.current
        let days = (0..<selectedPeriodDayWindow).compactMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
        var totals = Array(repeating: 0, count: days.count)
        for meal in meals {
            guard let loggedAt = meal.logged_at else { continue }
            guard let dayKey = normalizedDayKey(from: loggedAt) else { continue }
            for (idx, day) in days.enumerated() {
                if dayKeyFormatter.string(from: day) == dayKey {
                    totals[days.count - 1 - idx] += meal.calories ?? 0
                    break
                }
            }
        }
        return totals
    }

    private var periodCheckins: [ProgressCheckinResponse] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let earliest = calendar.date(byAdding: .day, value: -(selectedPeriodDayWindow - 1), to: today) else {
            return sortedCheckins
        }
        return sortedCheckins.filter {
            guard let checkinDate = workoutDate(from: $0.date) else { return false }
            let day = calendar.startOfDay(for: checkinDate)
            return day >= earliest && day <= today
        }
    }

    private var sortedCheckins: [ProgressCheckinResponse] {
        (progress?.checkins ?? []).sorted { $0.date < $1.date }
    }

    private var weightSeries: [Double] {
        periodCheckins.compactMap { $0.weight_kg }
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
        guard !values.isEmpty else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = maxValue - minValue
        return values.enumerated().map { index, value in
            let x = rect.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let y: CGFloat
            if range <= 0 {
                y = rect.height * 0.5
            } else {
                y = rect.height - rect.height * CGFloat((value - minValue) / range)
            }
            return CGPoint(x: x, y: y)
        }
    }

    private var latestWeightText: String {
        if let kg = profileUser?.weight_kg {
            return String(format: "%.1f kg", kg)
        }
        if let kg = sortedCheckins.last?.weight_kg {
            return String(format: "%.1f kg", kg)
        }
        return "—"
    }

    private var weightDeltaText: String {
        guard periodCheckins.count >= 2,
              let last = periodCheckins.last?.weight_kg,
              let prev = periodCheckins.dropLast().last?.weight_kg
        else { return "No recent change" }
        let delta = last - prev
        let sign = delta >= 0 ? "+" : ""
        return String(format: "%@%.1f kg", sign, delta)
    }

    private var weightDeltaIcon: String {
        guard periodCheckins.count >= 2,
              let last = periodCheckins.last?.weight_kg,
              let prev = periodCheckins.dropLast().last?.weight_kg
        else { return "minus" }
        return last <= prev ? "arrow.down" : "arrow.up"
    }

    private var weightDeltaColor: Color {
        guard periodCheckins.count >= 2,
              let last = periodCheckins.last?.weight_kg,
              let prev = periodCheckins.dropLast().last?.weight_kg
        else { return .white.opacity(0.6) }
        return last <= prev ? .green : .red
    }

    private var nextCheckpointText: String {
        guard let checkpoint = progress?.checkpoints.first else {
            return "No checkpoints yet"
        }
        let expected = checkpoint.expected_weight_kg
        let min = checkpoint.min_weight_kg
        let max = checkpoint.max_weight_kg
        return String(format: "Week %d target: %.1f kg (%.1f–%.1f)", checkpoint.week, expected, min, max)
    }

    private var latestCaloriesText: String {
        guard let latest = weeklyCalories.last else { return "—" }
        return "\(latest) kcal"
    }

    private var netCaloriesSeries: [(day: String, intake: Int, burned: Int, net: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let days = (0..<selectedPeriodDayWindow).compactMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
        var intakeByDay: [String: Int] = [:]
        var burnedByDay: [String: Int] = [:]

        for meal in progress?.meals ?? [] {
            guard let loggedAt = meal.logged_at else { continue }
            guard let dayKey = normalizedDayKey(from: loggedAt) else { continue }
            intakeByDay[dayKey, default: 0] += meal.calories ?? 0
        }

        for workout in progress?.workouts ?? [] {
            guard workout.completed == true, let rawDate = workout.date else { continue }
            guard let dayKey = normalizedDayKey(from: rawDate) else { continue }
            burnedByDay[dayKey, default: 0] += workout.calories_burned ?? 0
        }

        return days.reversed().map { day in
            let key = formatter.string(from: day)
            let intake = intakeByDay[key, default: 0]
            let burned = burnedByDay[key, default: 0]
            return (day: key, intake: intake, burned: burned, net: intake - burned)
        }
    }

    private var workoutCompletionRatio: Double {
        let workouts = progress?.workouts ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let earliest = calendar.date(byAdding: .day, value: -(selectedPeriodDayWindow - 1), to: today) else {
            return 0
        }
        let recent = workouts.filter { workout in
            guard let date = workoutDate(from: workout.date)
            else { return false }
            let day = calendar.startOfDay(for: date)
            return day >= earliest && day <= today && (workout.completed ?? false)
        }
        return min(1.0, Double(recent.count) / Double(selectedPeriodDayWindow))
    }

    private var workoutDateKeys: Set<String> {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: Date())
        guard let earliest = calendar.date(byAdding: .day, value: -(selectedPeriodDayWindow - 1), to: today) else {
            return []
        }
        return Set((progress?.workouts ?? []).compactMap { workout in
            guard workout.completed == true, let date = workoutDate(from: workout.date) else { return nil }
            let day = calendar.startOfDay(for: date)
            guard day >= earliest && day <= today else { return nil }
            return formatter.string(from: day)
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

    private func normalizedDayKey(from raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.count >= 10 {
            let prefix = String(value.prefix(10))
            if prefix.count == 10 {
                return prefix
            }
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            return dayKeyFormatter.string(from: date)
        }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd"
        if let date = fallback.date(from: value) {
            return dayKeyFormatter.string(from: date)
        }
        return nil
    }
}

struct WorkoutLogsHistoryView: View {
    let workouts: [ProgressWorkoutResponse]
    let periodLabel: String
    let dayWindow: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Workout Logs")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(periodLabel) view - past \(dayWindow) days")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                if workouts.isEmpty {
                    Spacer()
                    Text("No workouts logged in this period.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(workouts.enumerated()), id: \.offset) { _, workout in
                                WorkoutLogSmallCard(workout: workout)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
    }
}

private struct NetCaloriesDetailView: View {
    let data: [(day: String, intake: Int, burned: Int, net: Int)]
    let periodLabel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Net Calories")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(periodLabel) view • intake - burned")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.day)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.82))
                                Spacer()
                                Text("+\(item.intake)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.orange)
                                Text("-\(item.burned)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                                Text("\(item.net) kcal")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(item.net <= 0 ? .green : .white)
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
    }
}

private struct HealthDataImpactView: View {
    let userId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var response: HealthActivityImpactResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if isLoading {
                    ProgressView("Loading Apple Health impact...")
                        .tint(.white)
                        .foregroundColor(.white)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text("Could not load data")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Health Data & Plan Impact")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            Text("Daily view of Apple Health metrics versus plan targets.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.72))

                            ForEach(response?.items ?? []) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(formatDay(item.date))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    HStack {
                                        Text("Steps: \(item.steps)")
                                        Spacer()
                                        Text("Burn: \(item.health_calories_burned) kcal")
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.86))

                                    HStack {
                                        Text("Exercise: \(item.active_minutes) min")
                                        Spacer()
                                        if let intakeTarget = item.meal_target {
                                            Text("Meals: \(item.meal_intake)/\(intakeTarget) kcal")
                                        } else {
                                            Text("Meals: \(item.meal_intake) kcal")
                                        }
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.86))

                                    if let expected = item.workout_expected_burn {
                                        Text("Calorie burn: actual \(item.health_calories_burned) / planned \(expected) kcal")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.78))
                                    } else {
                                        Text("Calorie burn: actual \(item.health_calories_burned) kcal")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.78))
                                    }
                                    if !item.workouts_summary.isEmpty {
                                        Text("Workout source: \(item.workouts_summary)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.72))
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") { load() }
                }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        APIService.shared.getHealthActivityImpact(userId: userId, days: 7)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = String(describing: error)
                    }
                },
                receiveValue: { payload in
                    response = payload
                }
            )
            .store(in: &cancellables)
    }

    private func formatDay(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: value) else { return value }
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

}

private struct WorkoutLogSmallCard: View {
    let workout: ProgressWorkoutResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout.workout_type?.isEmpty == false ? (workout.workout_type ?? "Workout") : "Workout")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text(formattedDateText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 10) {
                if let duration = workout.duration_min {
                    Text("\(duration) min")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue.opacity(0.9))
                }
                if let calories = workout.calories_burned {
                    Text("\(calories) kcal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var parsedDate: Date? {
        guard let value = workout.date?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    private var formattedDateText: String {
        guard let parsedDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: parsedDate)
    }
}

// Settings Page matching screen 11 mockup
struct SettingsPageView: View {
    private let coachChangeCooldownDays = 2
    let coach: Coach
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var backendConnector: FrontendBackendConnector
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(\.openURL) private var openURL
    @AppStorage("enableNotifications") private var notificationsEnabled = true
    @AppStorage("selectedPlanTier") private var selectedPlanTier = "free"
    @AppStorage("enableHealthSync") private var healthSyncEnabled = false
    @State private var profileUser: ProfileUserResponse?
    @State private var showManagePlan = false
    @State private var showHelp = false
    @State private var showPrivacyPolicy = false
    @State private var showEditProfile = false
    @State private var showCoachSelection = false
    @State private var showHealthImpact = false
    @State private var showReminderManager = false
    @State private var isCreatingCheckout = false
    @State private var isConnectingGoogleCalendar = false
    @State private var isGoogleCalendarConnected = false
    @State private var billingErrorMessage: String?
    @State private var healthSyncMessage: String?
    @State private var reminderErrorMessage: String?
    @State private var googleCalendarMessage: String?
    @State private var reminders: [ReminderItemResponse] = []
    @State private var remindersLoading = false
    @State private var reminderBusyIds: Set<Int> = []
    @State private var cancellables = Set<AnyCancellable>()

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
            notificationManager.checkAuthorizationStatus()
            loadProfileData()
            refreshGoogleCalendarConnectionState()
            if let userId = authManager.effectiveUserId {
                loadRemindersForSettings(userId: userId)
            }
        }
        .onReceive(backendConnector.$profile) { response in
            if let response {
                profileUser = response.user
            }
        }
        .onChange(of: notificationsEnabled) { _, isEnabled in
            guard let userId = authManager.effectiveUserId else { return }
            if isEnabled {
                notificationManager.sendToggleOnTestNotification()
                syncReminderNotifications(userId: userId)
            } else {
                notificationManager.cancelReminderNotifications()
            }
        }
        .onChange(of: healthSyncEnabled) { _, isEnabled in
            guard let userId = authManager.effectiveUserId else { return }
            if isEnabled {
                healthKitManager.requestAuthorization()
                syncHealthDataFromHealthKit(userId: userId, days: 7)
            }
        }
        .sheet(isPresented: $showManagePlan) {
            NavigationView {
                ManagePlanView(
                    selectedPlanTier: selectedPlanTier,
                    isLoadingPremiumCheckout: isCreatingCheckout,
                    onChooseFree: {
                        selectedPlanTier = "free"
                        showManagePlan = false
                    },
                    onChoosePremium: {
                        startPremiumCheckout()
                    }
                )
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let userId = authManager.effectiveUserId {
                ProfileEditView(userId: userId, profile: backendConnector.profile) { updated in
                    profileUser = updated.user
                    backendConnector.profile = updated
                }
                .environmentObject(appState)
                .environmentObject(backendConnector)
            }
        }
        .sheet(isPresented: $showCoachSelection) {
            if let userId = authManager.effectiveUserId {
                CoachChangeView(
                    currentCoach: coach,
                    userId: userId,
                    onCoachChanged: { newCoach in
                        appState.selectedCoach = newCoach
                        loadProfileData()
                        showCoachSelection = false
                    }
                )
                .environmentObject(appState)
                .environmentObject(backendConnector)
            }
        }
        .sheet(isPresented: $showHelp) {
            NavigationView {
                helpView
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationView {
                privacyPolicyView
            }
        }
        .sheet(isPresented: $showHealthImpact) {
            if let userId = authManager.effectiveUserId {
                HealthDataImpactView(userId: userId)
            }
        }
        .sheet(isPresented: $showReminderManager) {
            if let userId = authManager.effectiveUserId {
                NavigationView {
                    ReminderManagementView(
                        reminders: reminders,
                        isLoading: remindersLoading,
                        busyReminderIds: reminderBusyIds,
                        notificationsEnabled: notificationsEnabled,
                        onRefresh: {
                            loadRemindersForSettings(userId: userId)
                        },
                        onToggleReminder: { reminder, isEnabled in
                            updateReminderStatus(userId: userId, reminder: reminder, isEnabled: isEnabled)
                        },
                        onDeleteReminder: { reminder in
                            deleteReminder(userId: userId, reminder: reminder)
                        }
                    )
                }
            }
        }
        .alert(
            "Billing Error",
            isPresented: Binding(
                get: { billingErrorMessage != nil },
                set: { if !$0 { billingErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { billingErrorMessage = nil }
            },
            message: {
                Text(billingErrorMessage ?? "Unable to open checkout.")
            }
        )
        .alert(
            "Apple Health Sync",
            isPresented: Binding(
                get: { healthSyncMessage != nil },
                set: { if !$0 { healthSyncMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { healthSyncMessage = nil }
            },
            message: {
                Text(healthSyncMessage ?? "")
            }
        )
        .alert(
            "Reminder Update",
            isPresented: Binding(
                get: { reminderErrorMessage != nil },
                set: { if !$0 { reminderErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { reminderErrorMessage = nil }
            },
            message: {
                Text(reminderErrorMessage ?? "")
            }
        )
        .alert(
            "Google Calendar",
            isPresented: Binding(
                get: { googleCalendarMessage != nil },
                set: { if !$0 { googleCalendarMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { googleCalendarMessage = nil }
            },
            message: {
                Text(googleCalendarMessage ?? "")
            }
        )
    }

    private var headerView: some View {
        HStack {
            Text("Setting")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.top, 50)
    }

    private var userProfileCard: some View {
        Button(action: { showEditProfile = true }) {
            HStack(spacing: 16) {
                if let image = profileImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
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
                    .stroke(Color.blue, lineWidth: 1)
                    .background(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var profileStatsText: String {
        let heightText = profileUser?.height_cm.map { String(format: "%.0f cm", $0) }
            ?? appState.userData?.height
            ?? "--"
        let weightText = profileUser?.weight_kg.map { String(format: "%.1f kg", $0) }
            ?? appState.userData?.weight
            ?? "--"
        let ageText = profileAgeText
        return "Height: \(heightText) | Weight: \(weightText) | Age: \(ageText)"
    }

    private var profileImage: Image? {
        guard let base64 = profileUser?.profile_image_base64,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else {
            return nil
        }
        return Image(uiImage: image)
    }

    private var displayName: String {
        if let name = profileUser?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let stored = UserDefaults.standard.string(forKey: "currentUserName"),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        if let email = authManager.currentUser, !email.isEmpty {
            return email
        }
        if let displayName = appState.userData?.displayName, !displayName.isEmpty {
            return displayName
        }
        return "Your Profile"
    }

    private func loadProfileData() {
        if let userId = authManager.effectiveUserId {
            backendConnector.loadProfile(userId: userId) { result in
                if case .success(let response) = result {
                    profileUser = response.user
                }
            }
            syncReminderNotifications(userId: userId)
            return
        }

        guard let email = authManager.currentUser, !email.isEmpty else { return }
        APIService.shared.getUserId(email: email)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    let userId = response.user_id
                    backendConnector.loadProfile(userId: userId) { result in
                        if case .success(let response) = result {
                            profileUser = response.user
                        }
                    }
                    syncReminderNotifications(userId: userId)
                }
            )
            .store(in: &cancellables)
    }

    private var profileAgeText: String {
        if let ageYears = profileUser?.age_years, ageYears > 0 {
            return "\(ageYears)"
        }
        return "--"
    }

    private var coachChangeCooldownDaysRemaining: Int {
        guard let raw = profileUser?.last_agent_change_at,
              let changedAt = parseISODate(raw) else {
            return 0
        }
        let nextAllowed = changedAt.addingTimeInterval(TimeInterval(coachChangeCooldownDays * 24 * 60 * 60))
        let secondsLeft = nextAllowed.timeIntervalSince(Date())
        if secondsLeft <= 0 {
            return 0
        }
        return max(1, Int(ceil(secondsLeft / 86400)))
    }

    private var canChangeCoach: Bool {
        coachChangeCooldownDaysRemaining == 0
    }

    private var currentCoachCard: some View {
        Button(action: {
            if canChangeCoach {
                showCoachSelection = true
            }
        }) {
            VStack(spacing: 16) {
                HStack {
                    Text("Current Coach")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(canChangeCoach ? "Change" : "Locked")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(canChangeCoach ? .blue : .white.opacity(0.55))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(canChangeCoach ? .blue : .white.opacity(0.55))
                    }
                }

                HStack(spacing: 16) {
                    // Coach avatar with real image or color
                    ZStack {
                        Circle()
                            .fill(Color(coach.primaryColor))
                            .frame(width: 60, height: 60)

                    if let url = coach.imageURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                    }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(coach.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Text(coach.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))

                        // Coach specialty tags
                        HStack(spacing: 6) {
                            ForEach(Array(coach.expertise.prefix(2)), id: \.self) { specialty in
                                Text(specialty)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(coach.primaryColor))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color(coach.primaryColor).opacity(0.2))
                                    )
                            }
                        }

                        if !canChangeCoach {
                            Text("Coach change available in \(coachChangeCooldownDaysRemaining) day(s)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.yellow.opacity(0.9))
                        }
                    }

                    Spacer()
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue, lineWidth: 1)
                    .background(Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canChangeCoach)
        .opacity(canChangeCoach ? 1.0 : 0.9)
    }

    private func parseISODate(_ raw: String) -> Date? {
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFraction.date(from: raw) {
            return date
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return date
        }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fallback.date(from: raw)
    }

    private var settingsList: some View {
        VStack(spacing: 16) {
            SettingsRow(title: "Notifications", toggle: $notificationsEnabled)
            SettingsRow(title: "Units", value: "Imperial")
            SettingsRow(title: "Language", value: "English")
            SettingsRow(title: "Apple Health Sync", toggle: $healthSyncEnabled)
            SettingsRow(
                title: "Connect Google Calendar",
                value: isConnectingGoogleCalendar
                    ? "Connecting..."
                    : (isGoogleCalendarConnected ? "Connected" : "Not Connected"),
                highlight: isGoogleCalendarConnected
            ) {
                connectGoogleCalendarInSettings()
            }
            SettingsRow(title: "Manage Notification Reminders") {
                showReminderManager = true
            }
            SettingsRow(title: "Health Data & Plan Impact") {
                showHealthImpact = true
            }
            SettingsRow(
                title: "Manage Plan",
                value: selectedPlanTier == "premium" ? "$14.99 Premium" : "Free",
                highlight: selectedPlanTier == "premium"
            ) {
                showManagePlan = true
            }

            Divider()
                .background(Color.white.opacity(0.2))

            SettingsRow(title: "Help")
                { showHelp = true }
            SettingsRow(title: "Privacy Policy") {
                showPrivacyPolicy = true
            }
            SettingsRow(title: "Log Out", isDestructive: true) {
                authManager.signOut()
            }
        }
    }

    private func syncHealthDataFromHealthKit(userId: Int, days: Int) {
        healthKitManager.collectDailySnapshots(lastDays: days) { snapshots in
            guard !snapshots.isEmpty else {
                healthSyncMessage = "No Apple Health data available yet."
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
                        healthSyncMessage = "Synced \(successCount)/\(snapshots.count) day(s) from Apple Health."
                    } else {
                        healthSyncMessage = "Sync failed. Please try again."
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func syncReminderNotifications(userId: Int) {
        backendConnector.loadReminders(userId: userId) { result in
            switch result {
            case .success(let reminders):
                self.reminders = reminders
                notificationManager.syncReminders(reminders, notificationsEnabled: notificationsEnabled)
            case .failure(let error):
                print("Failed to load reminders for settings sync: \(error)")
            }
        }
    }

    private func loadRemindersForSettings(userId: Int) {
        remindersLoading = true
        backendConnector.loadReminders(userId: userId) { result in
            remindersLoading = false
            switch result {
            case .success(let items):
                reminders = items.sorted { $0.scheduled_at < $1.scheduled_at }
                notificationManager.syncReminders(items, notificationsEnabled: notificationsEnabled)
            case .failure(let error):
                reminderErrorMessage = "Unable to load reminders: \(readableReminderError(error))"
            }
        }
    }

    private func updateReminderStatus(userId: Int, reminder: ReminderItemResponse, isEnabled: Bool) {
        guard !reminderBusyIds.contains(reminder.id) else { return }
        reminderBusyIds.insert(reminder.id)
        let payload = ReminderUpdateRequest(
            user_id: userId,
            status: isEnabled ? "pending" : "cancelled",
            scheduled_at: nil
        )
        backendConnector.updateReminder(reminderId: reminder.id, payload: payload) { result in
            reminderBusyIds.remove(reminder.id)
            switch result {
            case .success:
                loadRemindersForSettings(userId: userId)
            case .failure(let error):
                if let apiError = error as? APIError,
                   case .serverErrorWithMessage(let code, let message) = apiError,
                   code == 404 {
                    loadRemindersForSettings(userId: userId)
                    reminderErrorMessage = "That reminder was already removed. Refreshed the list."
                    return
                }
                reminderErrorMessage = "Unable to update reminder: \(readableReminderError(error))"
            }
        }
    }

    private func deleteReminder(userId: Int, reminder: ReminderItemResponse) {
        guard !reminderBusyIds.contains(reminder.id) else { return }
        reminderBusyIds.insert(reminder.id)
        backendConnector.deleteReminder(reminderId: reminder.id, userId: userId) { result in
            reminderBusyIds.remove(reminder.id)
            switch result {
            case .success:
                loadRemindersForSettings(userId: userId)
            case .failure(let error):
                reminderErrorMessage = "Unable to delete reminder: \(readableReminderError(error))"
            }
        }
    }

    private func readableReminderError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .serverErrorWithMessage(_, let message):
                return message
            case .serverError(let code):
                return "Server error (HTTP \(code))."
            case .unauthorized:
                return "You are not authorized. Please sign in again."
            case .requestFailed(let wrapped):
                if let urlError = wrapped as? URLError {
                    return readableNetworkError(urlError)
                }
                return "Couldn’t reach the server. Please try again."
            case .invalidURL:
                return "App server URL is invalid."
            case .invalidResponse:
                return "Server returned an invalid response."
            case .decodingFailed:
                return "Couldn’t read reminder data from server."
            default:
                return "Reminder request failed. Please try again."
            }
        }
        if let urlError = error as? URLError {
            return readableNetworkError(urlError)
        }
        return error.localizedDescription
    }

    private func readableNetworkError(_ error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "The request timed out. Make sure the backend is running and reachable."
        case .notConnectedToInternet:
            return "No internet connection."
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
            return "Cannot connect to the backend server."
        default:
            return "Network error: \(error.localizedDescription)"
        }
    }

    private func startPremiumCheckout() {
        guard let userId = authManager.effectiveUserId else { return }
        isCreatingCheckout = true
        backendConnector.createBillingCheckoutSession(userId: userId, planTier: "premium") { result in
            isCreatingCheckout = false
            switch result {
            case .success(let session):
                guard let url = URL(string: session.checkout_url) else {
                    billingErrorMessage = "Invalid checkout URL."
                    return
                }
                openURL(url)
            case .failure(let error):
                if let apiError = error as? APIError {
                    switch apiError {
                    case .serverErrorWithMessage(_, let message):
                        billingErrorMessage = message
                    case .serverError(let code):
                        billingErrorMessage = "Checkout failed (HTTP \(code))."
                    default:
                        billingErrorMessage = "\(apiError)"
                    }
                } else {
                    billingErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func refreshGoogleCalendarConnectionState() {
        isGoogleCalendarConnected = authManager.googleAccessToken != nil
    }

    private func connectGoogleCalendarInSettings() {
        guard !isConnectingGoogleCalendar else { return }
        isConnectingGoogleCalendar = true
        authManager.connectGoogleCalendar { result in
            DispatchQueue.main.async {
                isConnectingGoogleCalendar = false
                refreshGoogleCalendarConnectionState()
                switch result {
                case .success:
                    googleCalendarMessage = "Google Calendar connected successfully. You can now ask the coach to add events."
                case .failure(let error):
                    googleCalendarMessage = "Couldn’t connect Google Calendar: \(error.localizedDescription)"
                }
            }
        }
    }

    private var helpView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Help")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("Common topics")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 10) {
                    helpItem(title: "Account access", detail: "If you can’t sign in, make sure you’re using the same email you signed up with. If needed, try signing up again to create a new account.")
                    helpItem(title: "Backend connection", detail: "If the app can’t reach the server, confirm the backend URL is correct and the server is running.")
                    helpItem(title: "Logging meals & workouts", detail: "Use the Trainer chat or the Today’s Plan detail page to log workouts. Logged meals appear in Calorie Balance after sync.")
                    helpItem(title: "Notifications", detail: "Enable notifications in Settings and allow permissions in iOS Settings > Notifications.")
                }

                Text("Contact")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("Email support at support@vaylo.ai")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showHelp = false }
            }
        }
    }

    private var privacyPolicyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("We respect your privacy. This app only collects the data needed to provide coaching features, including profile details, workout logs, and nutrition logs.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))

                Text("Data usage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 10) {
                    helpItem(title: "Profile data", detail: "Used to personalize plans and recommendations.")
                    helpItem(title: "Health data", detail: "Only accessed with your permission and used to enhance insights.")
                    helpItem(title: "Account data", detail: "Stored securely to enable sign in and sync across devices.")
                }

                Text("Questions?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("Email privacy@vaylo.ai for more details.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showPrivacyPolicy = false }
            }
        }
    }

    private func helpItem(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(detail)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
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

struct ReminderManagementView: View {
    let reminders: [ReminderItemResponse]
    let isLoading: Bool
    let busyReminderIds: Set<Int>
    let notificationsEnabled: Bool
    let onRefresh: () -> Void
    let onToggleReminder: (ReminderItemResponse, Bool) -> Void
    let onDeleteReminder: (ReminderItemResponse) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Text("Notification Reminders")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Close") { dismiss() }
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.top, 8)

                if !notificationsEnabled {
                    Text("Enable Notifications in Settings to receive reminder alerts.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.yellow.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.14)))
                }

                if isLoading {
                    ProgressView("Loading reminders...")
                        .tint(.white)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 30)
                    Spacer()
                } else if reminders.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.6))
                        Text("No reminders set")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 30)
                    Spacer()
                } else {
                    List {
                        ForEach(reminders, id: \.id) { reminder in
                            reminderRow(reminder)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .padding(18)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundColor(.white)
            }
        }
    }

    private func reminderRow(_ reminder: ReminderItemResponse) -> some View {
        let isEnabled = reminder.status.lowercased() != "cancelled"
        let isBusy = busyReminderIds.contains(reminder.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(reminderTitle(reminder.reminder_type))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { onToggleReminder(reminder, $0) }
                ))
                .labelsHidden()
                .disabled(isBusy)
            }

            Text(formattedReminderDate(reminder.scheduled_at))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.72))

            HStack {
                Text(isEnabled ? "Enabled" : "Disabled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isEnabled ? .green.opacity(0.9) : .red.opacity(0.9))
                Spacer()
                Button(role: .destructive) {
                    onDeleteReminder(reminder)
                } label: {
                    Text(isBusy ? "Updating..." : "Delete")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(isBusy)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
        .padding(.vertical, 4)
    }

    private func reminderTitle(_ type: String) -> String {
        let normalized = type.lowercased()
        if normalized.contains("coach_checkin") || normalized.contains("daily_checkin") {
            return "Daily Coach Check-In"
        }
        if normalized.contains("workout") {
            return "Workout Reminder"
        }
        if normalized.contains("meal") {
            return "Meal Reminder"
        }
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formattedReminderDate(_ raw: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            return formatDate(date)
        }
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: raw) {
            return formatDate(date)
        }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = fallback.date(from: raw) {
            return formatDate(date)
        }
        return raw
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ManagePlanView: View {
    let selectedPlanTier: String
    let isLoadingPremiumCheckout: Bool
    let onChooseFree: () -> Void
    let onChoosePremium: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Manage Plan")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                planCard(
                    title: "Free Plan",
                    subtitle: "Core coaching and tracking features.",
                    price: "$0",
                    isSelected: selectedPlanTier == "free",
                    buttonTitle: selectedPlanTier == "free" ? "Current Plan" : "Choose Free",
                    buttonAction: onChooseFree
                )

                planCard(
                    title: "Premium Plan",
                    subtitle: "Advanced coaching tools and premium features.",
                    price: "$14.99 / month + tax",
                    isSelected: selectedPlanTier == "premium",
                    buttonTitle: isLoadingPremiumCheckout ? "Opening Checkout..." : "Choose Premium",
                    buttonAction: onChoosePremium,
                    buttonDisabled: isLoadingPremiumCheckout
                )

                Spacer()
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
    }

    private func planCard(
        title: String,
        subtitle: String,
        price: String,
        isSelected: Bool,
        buttonTitle: String,
        buttonAction: @escaping () -> Void,
        buttonDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.15)))
                }
            }
            Text(price)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            Button(action: buttonAction) {
                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
            }
            .disabled(buttonDisabled)
            .opacity(buttonDisabled ? 0.7 : 1.0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.blue : Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

// MARK: - Coach Change View

struct CoachChangeView: View {
    let currentCoach: Coach
    let userId: Int
    let onCoachChanged: (Coach) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var backendConnector: FrontendBackendConnector
    @State private var selectedCoach: Coach?
    @State private var isUpdating = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Text("Choose Your Coach")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Your coach will guide your fitness journey with personalized advice")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Coach Grid
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(appState.coaches) { coach in
                                CoachChangeCard(
                                    coach: coach,
                                    isSelected: selectedCoach?.id == coach.id,
                                    isCurrent: currentCoach.id == coach.id
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedCoach = coach
                                    }

                                    // Haptic feedback
                                    let selectionFeedback = UISelectionFeedbackGenerator()
                                    selectionFeedback.selectionChanged()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }

                // Floating action button
                if let selectedCoach = selectedCoach, selectedCoach.id != currentCoach.id {
                    VStack {
                        Spacer()
                        changeCoachButton(selectedCoach)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            selectedCoach = currentCoach
        }
        .alert(
            "Unable to Change Coach",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { errorMessage = nil }
            },
            message: {
                Text(errorMessage ?? "Please try again later.")
            }
        )
    }

    private func changeCoachButton(_ coach: Coach) -> some View {
        Button(action: {
            changeCoach(to: coach)
        }) {
            HStack(spacing: 12) {
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(isUpdating ? "Switching Coach..." : "Switch to \(coach.name)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(coach.primaryColor), Color(coach.secondaryColor)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color(coach.primaryColor).opacity(0.4), radius: 8, x: 0, y: 4)
            .scaleEffect(isUpdating ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isUpdating)
        }
        .disabled(isUpdating)
    }

    private func changeCoach(to newCoach: Coach) {
        guard !isUpdating else { return }

        isUpdating = true

        // Call backend API to sync the change
        backendConnector.changeCoach(userId: userId, newCoachId: newCoach.id) { result in
            isUpdating = false
            switch result {
            case .success:
                onCoachChanged(newCoach)
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
                print("✅ Coach change synced with backend")
                dismiss()
            case .failure(let error):
                print("❌ Failed to sync coach change with backend: \(error)")
                if let apiError = error as? APIError {
                    switch apiError {
                    case .serverErrorWithMessage(_, let message):
                        errorMessage = message
                    case .serverError(let code):
                        errorMessage = "Coach change failed (HTTP \(code))."
                    default:
                        errorMessage = "Coach change failed. Please try again."
                    }
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct CoachChangeCard: View {
    let coach: Coach
    let isSelected: Bool
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Coach Image
                ZStack {
                    if let url = coach.imageURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(coach.primaryColor).opacity(0.8),
                                                Color(coach.secondaryColor).opacity(0.6)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(coach.primaryColor).opacity(0.8),
                                        Color(coach.secondaryColor).opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 140)

                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    // Current coach indicator
                    if isCurrent {
                        VStack {
                            HStack {
                                Text("CURRENT")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.green)
                                    )
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(8)
                    }

                    // Selection indicator
                    if isSelected && !isCurrent {
                        VStack {
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                }

                // Coach Info
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coach.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(coach.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    }

                    // Philosophy snippet
                    Text(coach.philosophy)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)

                    // Expertise tags
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(Array(coach.expertise.prefix(2)), id: \.self) { specialty in
                            Text(specialty)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color(coach.primaryColor))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color(coach.primaryColor).opacity(0.2))
                                )
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color(coach.primaryColor) : Color.white.opacity(0.2),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
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
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(FrontendBackendConnector.shared)
}

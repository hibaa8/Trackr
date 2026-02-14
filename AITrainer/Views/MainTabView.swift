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
            ProgressPageView()
            .tag(0)

            // Trainer Page (default)
            TrainerMainViewContent(coach: coach)
                .safeAreaInset(edge: .bottom) {
                    globalBottomToolbar(showVoice: true)
                }
            .tag(1)

            // Settings Page
            SettingsPageView(coach: coach)
            .tag(2)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(coach: coach, autoFocus: focusChatOnOpen)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDashboardTab)) { _ in
            selectedTab = 1
        }
    }

    private func globalBottomToolbar(showVoice: Bool) -> some View {
        HStack(spacing: 0) {
            // Voice microphone (main action)
            if showVoice {
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
            } else {
                Color.clear.frame(width: 64, height: 64)
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
    @State private var profileUser: ProfileUserResponse?
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
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
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
                            workoutWeekRow(
                                week: week,
                                calendar: calendar,
                                formatter: formatter
                            )
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

    private func workoutWeekRow(
        week: Int,
        calendar: Calendar,
        formatter: DateFormatter
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { day in
                let dayIndex = week * 7 + day
                let date = calendar.date(byAdding: .day, value: dayIndex - 27, to: Date())
                let dateKey = date.map { formatter.string(from: $0) }
                let isWorkoutDay = dateKey.map { workoutDateKeys.contains($0) } ?? false
                let isToday = dateKey == formatter.string(from: Date())

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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let days = (0..<selectedPeriodDayWindow).compactMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
        var totals = Array(repeating: 0, count: days.count)
        for meal in meals {
            guard let loggedAt = meal.logged_at else { continue }
            let dayKey = String(loggedAt.prefix(10))
            for (idx, day) in days.enumerated() {
                if formatter.string(from: day) == dayKey {
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
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -offsetFromToday, to: Date()) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
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
    let coach: Coach
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var backendConnector: FrontendBackendConnector
    @EnvironmentObject private var notificationManager: NotificationManager
    @Environment(\.openURL) private var openURL
    @AppStorage("enableNotifications") private var notificationsEnabled = true
    @AppStorage("selectedPlanTier") private var selectedPlanTier = "free"
    @State private var healthSyncEnabled = false
    @State private var profileUser: ProfileUserResponse?
    @State private var showManagePlan = false
    @State private var isCreatingCheckout = false
    @State private var billingErrorMessage: String?

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
            guard let userId = authManager.effectiveUserId else { return }
            backendConnector.loadProfile(userId: userId) { result in
                if case .success(let response) = result {
                    profileUser = response.user
                }
            }
            syncReminderNotifications(userId: userId)
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
        let weightText = profileUser?.weight_kg.map { String(format: "%.1f kg", $0) } ?? "--"
        let ageText = profileAgeText
        return "Height: \(heightText) | Weight: \(weightText) | Age: \(ageText)"
    }

    private var profileAgeText: String {
        if let ageYears = profileUser?.age_years, ageYears > 0 {
            return "\(ageYears)"
        }
        return "--"
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
            SettingsRow(title: "Privacy Policy")
            SettingsRow(title: "Log Out", isDestructive: true) {
                authManager.signOut()
            }
        }
    }

    private func syncReminderNotifications(userId: Int) {
        backendConnector.loadReminders(userId: userId) { result in
            switch result {
            case .success(let reminders):
                notificationManager.syncReminders(reminders, notificationsEnabled: notificationsEnabled)
            case .failure(let error):
                print("Failed to load reminders for settings sync: \(error)")
            }
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

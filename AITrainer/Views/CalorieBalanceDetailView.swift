import SwiftUI

struct CalorieBalanceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var selectedDate = Date()
    @State private var showLogFood = false
    @State private var showVoiceChat = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                dateSelector

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        calorieRing
                        macroSection
                        mealsSection
                        logFoodButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }

            VStack {
                Spacer()
                bottomToolbar
            }
        }
        .onAppear {
            selectedDate = appState.selectedDate
            guard let userId = authManager.effectiveUserId else { return }
            appState.refreshDailyData(for: selectedDate, userId: userId)
        }
        .onChange(of: selectedDate) { _, newValue in
            guard let userId = authManager.effectiveUserId else { return }
            appState.refreshDailyData(for: newValue, userId: userId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            guard let userId = authManager.effectiveUserId else { return }
            appState.refreshDailyData(for: selectedDate, userId: userId)
        }
        .sheet(isPresented: $showLogFood) {
            MealLoggingView()
        }
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(coach: Coach.allCoaches[0])
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }

            Spacer()

            Text("Calorie Balance")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var dateSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visibleDates, id: \.self) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    VStack(spacing: 4) {
                        Text(dayFormatter.string(from: date))
                            .font(.system(size: 11, weight: .semibold))
                        Text(dayNumberFormatter.string(from: date))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.blue : Color.clear)
                    )
                    .onTapGesture {
                        selectedDate = date
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var calorieRing: some View {
        let intake = appState.caloriesIn
        let target = appState.userData?.calorieTarget ?? 2000
        let burned = appState.caloriesOut
        let progress = min(1.0, max(0.0, Double(intake) / Double(max(target, 1))))

        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(red: 0.11, green: 0.11, blue: 0.12), lineWidth: 20)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [Color.blue, Color.cyan]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.blue.opacity(0.5), radius: 16)

                VStack(spacing: 4) {
                    Text("\(intake) kcal")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("/ \(target) kcal target")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.7))
                }
            }

            VStack(spacing: 6) {
                HStack {
                    Text("🍴 Intake: \(intake) kcal")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.8))
                    Spacer()
                    Text("🔥 Burned: \(burned) kcal")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macronutrients")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            MacroProgressRow(
                title: "Protein",
                current: appState.proteinCurrent,
                target: appState.proteinTarget,
                color: .blue
            )
            MacroProgressRow(
                title: "Carbs",
                current: appState.carbsCurrent,
                target: appState.carbsTarget,
                color: Color(red: 0.35, green: 0.78, blue: 0.98)
            )
            MacroProgressRow(
                title: "Fat",
                current: appState.fatsCurrent,
                target: appState.fatsTarget,
                color: Color(red: 0.04, green: 0.52, blue: 1.0)
            )
        }
        .padding(16)
        .background(Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.85))
        .cornerRadius(16)
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meals Today")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            let meals = appState.meals.sorted { $0.timestamp < $1.timestamp }
            if meals.isEmpty {
                Text("No meals logged yet.")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.6))
            } else {
                ForEach(meals.prefix(3)) { meal in
                    MealRow(meal: meal)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.85))
        .cornerRadius(16)
    }

    private var logFoodButton: some View {
        Button(action: { showLogFood = true }) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                Text("Log Food")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue)
            .cornerRadius(12)
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Button(action: {}) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button(action: { showVoiceChat = true }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.blue.opacity(0.6), radius: 16)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            Button(action: { showLogFood = true }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
        }
        .frame(height: 90)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.7))
        )
        .padding(.horizontal, 20)
    }

    private var visibleDates: [Date] {
        let base = Calendar.current.startOfDay(for: selectedDate)
        return (-2...4).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: base) }
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }

    private var dayNumberFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }
}

struct MacroProgressRow: View {
    let title: String
    let current: Int
    let target: Int
    let color: Color

    var body: some View {
        let progress = min(1.0, max(0.0, Double(current) / Double(max(target, 1))))
        let percent = Int(progress * 100)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) \(current)g/\(target)g")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.7))
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.23, green: 0.23, blue: 0.24))
                    .frame(height: 8)
                Capsule()
                    .fill(color)
                    .frame(width: max(8, CGFloat(progress) * 260), height: 8)
            }
        }
    }
}

struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            if let data = meal.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 60, height: 60)
                    Image(systemName: "fork.knife")
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(timeFormatter.string(from: meal.timestamp))
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            Spacer()

            Text("\(meal.calories) kcal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.85))
        .cornerRadius(12)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
}

#Preview {
    CalorieBalanceDetailView()
        .environmentObject(AppState())
        .environmentObject(AuthenticationManager())
}

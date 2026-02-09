import SwiftUI
import Combine

struct TodayPlanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var selectedDate = Date()
    @State private var isLoading = false
    @State private var dayPlan: PlanDayResponse?
    @State private var showVoiceChat = false
    @State private var showLogFood = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var plansByDate: [String: PlanDayResponse] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                dateSelector
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        let dateKey = isoDateFormatter.string(from: selectedDate)
                        let plan = plansByDate[dateKey]
                        let workoutText = (plan?.workout_plan ?? "Workout").trimmingCharacters(in: .whitespacesAndNewlines)
                        let calorieText = plan?.calorie_target ?? 0
                        planCard(
                            title: workoutText.isEmpty ? "Workout" : workoutText,
                            subtitle: calorieText > 0 ? "\(calorieText) kcal target" : "Workout",
                            details: workoutText.isEmpty ? ["Workout"] : [workoutText],
                            primaryButton: "Start Workout"
                        )
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
            loadSelectedPlan()
        }
        .onChange(of: selectedDate) { newValue in
            loadSelectedPlan()
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

            Text("Today's Plan")
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
                        Text(monthDayFormatter.string(from: date))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                        if Calendar.current.isDateInToday(date) {
                            Text("Today")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                        }
                    }
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

    private func planCard(
        title: String,
        subtitle: String,
        details: [String],
        primaryButton: String? = nil,
        secondaryButton: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.7))

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(details, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                }
            }

            if let primaryButton = primaryButton {
                Button(action: {}) {
                    Text(primaryButton)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }

            if let secondaryButton = secondaryButton {
                Button(action: {}) {
                    Text(secondaryButton)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.85))
        .cornerRadius(16)
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

    private var monthDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }

    private var isoDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func loadSelectedPlan() {
        isLoading = true
        let date = selectedDate
        APIService.shared.getTodayPlan(date: date)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        print("Failed to load plan: \(error)")
                    }
                },
                receiveValue: { plan in
                    let key = self.isoDateFormatter.string(from: date)
                    self.plansByDate[key] = plan
                }
            )
            .store(in: &cancellables)
    }
}

#Preview {
    TodayPlanDetailView()
        .environmentObject(AppState())
}

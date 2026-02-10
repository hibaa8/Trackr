import SwiftUI
import Combine

struct TodayPlanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var selectedDate = Date()
    @State private var isLoading = false
    @State private var dayPlan: PlanDayResponse?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var plansByDate: [String: PlanDayResponse] = [:]
    @State private var showFullDetails = false

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
                        let formattedDetails = formatWorkoutDetails(workoutText)
                        planCard(
                            title: workoutTitle(from: workoutText, date: selectedDate),
                            subtitle: calorieText > 0 ? "\(calorieText) kcal target" : "Workout",
                            details: formattedDetails.isEmpty ? ["🏋️ Workout"] : formattedDetails,
                            primaryButton: "Log Workout"
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .onAppear {
            selectedDate = appState.selectedDate
            loadSelectedPlan()
        }
        .onChange(of: selectedDate) { newValue in
            loadSelectedPlan()
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
        let previewItems = Array(details.prefix(2))
        let hasMore = details.count > previewItems.count
        let visibleItems = showFullDetails ? details : previewItems

        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))

            if !visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.blue.opacity(0.8))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(item)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.82))
                                .lineLimit(showFullDetails ? nil : 2)
                        }
                    }
                }
            } else {
                Text("Details will appear once your plan is ready.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            if hasMore {
                Button(action: { showFullDetails.toggle() }) {
                    Text(showFullDetails ? "Show less" : "Show full plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.blue.opacity(0.9))
                }
            }

            if let primaryButton = primaryButton {
                Button(action: {
                    showVoiceChat = true
                }) {
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
        .frame(minHeight: 220)
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
        guard let userId = authManager.effectiveUserId else {
            return
        }
        isLoading = true
        let date = selectedDate
        APIService.shared.getTodayPlan(date: date, userId: userId)
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

    private func workoutTitle(from text: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayLabel = formatter.string(from: date)
        return dayLabel
    }

    private func formatWorkoutDetails(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var rawLines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if rawLines.count == 1 {
            let sentenceLines = rawLines[0]
                .split(separator: ".")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            rawLines = sentenceLines
            if let first = rawLines.first, first.contains(":") {
                let parts = first.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let listItems = parts[1]
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    rawLines.removeFirst()
                    rawLines.insert(contentsOf: listItems, at: 0)
                }
            }
        }
        return rawLines.map { line in
            "• \(line)"
        }
    }
}

#Preview {
    TodayPlanDetailView()
        .environmentObject(AppState())
        .environmentObject(AuthenticationManager())
}

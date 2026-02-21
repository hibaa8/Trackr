import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let dataDidUpdate = Notification.Name("DataDidUpdate")
    static let openDashboardTab = Notification.Name("OpenDashboardTab")
}

class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    @Published var userData: UserData?
    @Published var caloriesIn: Int = 0
    @Published var caloriesOut: Int = 2100
    @Published var workoutCompleted: Bool = true
    @Published var meals: [MealEntry] = []
    @Published var chatMessages: [WireframeChatMessage] = []
    @Published var selectedDate: Date = Date()
    @Published var selectedCoach: Coach?
    @Published var todayPlan: PlanDayResponse?
    @Published var coaches: [Coach] = Coach.allCoaches
    private var coachThreadId: String?
    private var awaitingPlanApproval = false

    // Macros
    @Published var proteinCurrent: Int = 0
    @Published var proteinTarget: Int = 150
    @Published var carbsCurrent: Int = 0
    @Published var carbsTarget: Int = 200
    @Published var fatsCurrent: Int = 0
    @Published var fatsTarget: Int = 65
    @Published var userLevel: Int = 12
    @Published var userXp: Int = 2450
    @Published var userXpGoal: Int = 3000

    init() {
        // Initialize with sample chat messages
        chatMessages = [
            WireframeChatMessage(text: "Hi! I'm your AI fitness coach. How can I help you today?", isFromUser: false, timestamp: Date())
        ]

        // Start with empty meals; load from backend
        meals = []
        updateMacroTargets()
    }

    func completeOnboarding(with data: UserData) {
        self.userData = data
        self.hasCompletedOnboarding = true
        updateMacroTargets()
    }

    func setSelectedCoach(_ coach: Coach) {
        selectedCoach = coach
        coachThreadId = nil
        awaitingPlanApproval = false
        chatMessages = [
            WireframeChatMessage(
                text: "Hi! I'm \(coach.name). How can I help you today?",
                isFromUser: false,
                timestamp: Date()
            )
        ]
    }

    func logMeal(_ meal: MealEntry, userId: Int) {
        meals.insert(meal, at: 0)
        caloriesIn += meal.calories
        proteinCurrent += meal.protein
        carbsCurrent += meal.carbs
        fatsCurrent += meal.fats
        refreshDailyData(for: selectedDate, userId: userId)
    }

    func refreshDailyData(for date: Date, userId: Int) {
        FoodScanService.shared.getDailyIntake(date: date, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let intake):
                    self?.caloriesIn = intake.total_calories
                    self?.proteinCurrent = Int(intake.total_protein_g)
                    self?.carbsCurrent = Int(intake.total_carbs_g)
                    self?.fatsCurrent = Int(intake.total_fat_g)
                    if let target = intake.daily_calorie_target, var data = self?.userData {
                        data.calorieTarget = target
                        self?.userData = data
                        self?.updateMacroTargets()
                    }
                case .failure:
                    break
                }
            }
        }

        FoodScanService.shared.getDailyMeals(date: date, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    let mappedMeals = response.meals.map {
                        MealEntry(
                            name: $0.name,
                            calories: $0.calories,
                            protein: Int($0.protein_g),
                            carbs: Int($0.carbs_g),
                            fats: Int($0.fat_g),
                            timestamp: formatter.date(from: $0.logged_at) ?? Date()
                        )
                    }
                    self?.meals = mappedMeals.sorted { $0.timestamp > $1.timestamp }
                case .failure:
                    break
                }
            }
        }
    }

    private func updateMacroTargets() {
        let calorieTarget = userData?.calorieTarget ?? 2000
        proteinTarget = Int((Double(calorieTarget) * 0.30) / 4.0)
        carbsTarget = Int((Double(calorieTarget) * 0.40) / 4.0)
        fatsTarget = Int((Double(calorieTarget) * 0.30) / 9.0)
    }

    func sendMessage(_ text: String, userId: Int) {
        let userMessage = WireframeChatMessage(text: text, isFromUser: true, timestamp: Date())
        chatMessages.append(userMessage)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if awaitingPlanApproval {
            handlePlanApprovalResponse(trimmed)
            return
        }

        AICoachService.shared.sendMessage(
            trimmed,
            threadId: coachThreadId,
            agentId: selectedCoach?.id,
            userId: userId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.coachThreadId = response.thread_id
                    let replyText = response.reply.isEmpty ? "How can I help you further?" : response.reply
                    self?.chatMessages.append(WireframeChatMessage(text: replyText, isFromUser: false, timestamp: Date()))
                    NotificationCenter.default.post(name: .dataDidUpdate, object: nil)

                    if response.requires_feedback {
                        if let planText = response.plan_text, !planText.isEmpty {
                            self?.chatMessages.append(WireframeChatMessage(text: planText, isFromUser: false, timestamp: Date()))
                        }
                        self?.chatMessages.append(
                            WireframeChatMessage(
                                text: "Would you like me to apply this plan? Reply with 'yes' or 'no'.",
                                isFromUser: false,
                                timestamp: Date()
                            )
                        )
                        self?.awaitingPlanApproval = true
                    }
                case .failure:
                    self?.chatMessages.append(
                        WireframeChatMessage(
                            text: "I couldn’t reach the coach service. Please make sure the backend is running.",
                            isFromUser: false,
                            timestamp: Date()
                        )
                    )
                }
            }
        }
    }

    private func handlePlanApprovalResponse(_ message: String) {
        let lower = message.lowercased()
        let approve: Bool?
        if ["yes", "y", "sure", "ok", "okay"].contains(lower) {
            approve = true
        } else if ["no", "n", "nope", "cancel"].contains(lower) {
            approve = false
        } else {
            chatMessages.append(
                WireframeChatMessage(
                    text: "Please reply with 'yes' or 'no' so I can apply or discard the plan.",
                    isFromUser: false,
                    timestamp: Date()
                )
            )
            return
        }

        guard let threadId = coachThreadId else {
            awaitingPlanApproval = false
            return
        }

        AICoachService.shared.sendFeedback(threadId: threadId, approve: approve ?? false) { [weak self] result in
            DispatchQueue.main.async {
                self?.awaitingPlanApproval = false
                switch result {
                case .success(let response):
                    let replyText = response.reply.isEmpty ? "Plan updated." : response.reply
                    self?.chatMessages.append(WireframeChatMessage(text: replyText, isFromUser: false, timestamp: Date()))
                    NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
                case .failure:
                    self?.chatMessages.append(
                        WireframeChatMessage(
                            text: "I couldn’t submit your decision. Please try again.",
                            isFromUser: false,
                            timestamp: Date()
                        )
                    )
                }
            }
        }
    }

    var remainingCalories: Int {
        (userData?.calorieTarget ?? 2000) - caloriesIn
    }

    var coachMessage: String {
        if caloriesIn < (userData?.calorieTarget ?? 2000) - 200 {
            return "You're doing great with your calorie goals! Consider adding a healthy snack after your workout to maintain energy levels."
        } else {
            return "Fantastic consistency today! Keep up the amazing work. Remember to stay hydrated! 💧"
        }
    }
}
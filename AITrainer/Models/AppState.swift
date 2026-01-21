import Foundation
import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    @Published var userData: UserData?
    @Published var caloriesIn: Int = 1420
    @Published var caloriesOut: Int = 2100
    @Published var workoutCompleted: Bool = true
    @Published var meals: [MealEntry] = []
    @Published var chatMessages: [ChatMessage] = []
    private var coachThreadId: String?
    private var awaitingPlanApproval = false

    // Macros
    @Published var proteinCurrent: Int = 75
    @Published var proteinTarget: Int = 150
    @Published var carbsCurrent: Int = 138
    @Published var carbsTarget: Int = 200
    @Published var fatsCurrent: Int = 35
    @Published var fatsTarget: Int = 65

    init() {
        // Initialize with sample chat messages
        chatMessages = [
            ChatMessage(text: "Hi! I'm your AI fitness coach. How can I help you today?", isFromUser: false, timestamp: Date())
        ]

        // Sample meal entry
        meals = [
            MealEntry(
                name: "Grilled Salmon",
                calories: 550,
                protein: 36,
                carbs: 40,
                fats: 28,
                timestamp: Date()
            )
        ]
    }

    func completeOnboarding(with data: UserData) {
        self.userData = data
        self.hasCompletedOnboarding = true
    }

    func logMeal(_ meal: MealEntry) {
        meals.insert(meal, at: 0)
        caloriesIn += meal.calories
        proteinCurrent += meal.protein
        carbsCurrent += meal.carbs
        fatsCurrent += meal.fats
    }

    func sendMessage(_ text: String) {
        let userMessage = ChatMessage(text: text, isFromUser: true, timestamp: Date())
        chatMessages.append(userMessage)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if awaitingPlanApproval {
            handlePlanApprovalResponse(trimmed)
            return
        }

        AICoachService.shared.sendMessage(trimmed, threadId: coachThreadId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.coachThreadId = response.thread_id
                    let replyText = response.reply.isEmpty ? "How can I help you further?" : response.reply
                    self?.chatMessages.append(ChatMessage(text: replyText, isFromUser: false, timestamp: Date()))

                    if response.requires_feedback {
                        if let planText = response.plan_text, !planText.isEmpty {
                            self?.chatMessages.append(ChatMessage(text: planText, isFromUser: false, timestamp: Date()))
                        }
                        self?.chatMessages.append(
                            ChatMessage(
                                text: "Would you like me to apply this plan? Reply with 'yes' or 'no'.",
                                isFromUser: false,
                                timestamp: Date()
                            )
                        )
                        self?.awaitingPlanApproval = true
                    }
                case .failure:
                    self?.chatMessages.append(
                        ChatMessage(
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
                ChatMessage(
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
                    self?.chatMessages.append(ChatMessage(text: replyText, isFromUser: false, timestamp: Date()))
                case .failure:
                    self?.chatMessages.append(
                        ChatMessage(
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
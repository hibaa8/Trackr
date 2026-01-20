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

        // Simulate AI response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let responses = [
                "That's a great question! Based on your current progress, I'd recommend...",
                "You're doing amazing! Keep up the great work with your nutrition.",
                "I notice you've been consistent with your calorie goals. Consider adding more protein to help with muscle recovery.",
                "Great job staying on track! Remember to stay hydrated throughout the day."
            ]
            let aiMessage = ChatMessage(
                text: responses.randomElement() ?? "How can I assist you further?",
                isFromUser: false,
                timestamp: Date()
            )
            self.chatMessages.append(aiMessage)
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
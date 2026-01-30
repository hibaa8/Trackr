import Foundation
import SwiftUI

// MARK: - User Data Model
struct UserData: Codable {
    var displayName: String
    var age: String
    var height: String
    var weight: String
    var goalWeight: String
    var activityLevel: String
    var dietPreference: String
    var workoutPreference: String
    var calorieTarget: Int
}


// MARK: - Diet Preference
enum DietPreference: String, CaseIterable {
    case omnivore = "Omnivore"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case keto = "Keto"
    case paleo = "Paleo"
}

// MARK: - Workout Preference
enum WorkoutPreference: String, CaseIterable {
    case cardio = "Cardio"
    case strength = "Strength Training"
    case yoga = "Yoga & Flexibility"
    case mixed = "Mixed"
}

// MARK: - Detected Food
struct DetectedFood: Identifiable {
    let id = UUID()
    var name: String
    var category: String?
    var portion: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fats: Int
}

// MARK: - Meal Entry
struct MealEntry: Identifiable {
    let id = UUID()
    var name: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fats: Int
    var timestamp: Date
    var imageData: Data?
}




// MARK: - Community Group
struct CommunityGroup: Identifiable {
    let id = UUID()
    var name: String
    var members: String
    var category: String
    var lastActivity: String
}

// MARK: - Chat Message
struct WireframeChatMessage: Identifiable {
    let id = UUID()
    var text: String
    var isFromUser: Bool
    var timestamp: Date
}
//
//  APIResponseModels.swift
//  AITrainer
//
//  Additional API response models that differ from local models
//
//  This file contains ONLY API-specific response structures that differ
//  from the main model definitions used throughout the app.
//

import Foundation

struct FoodScanItemResponse: Codable {
    let name: String
    let amount: String
    let calories: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let category: String?
    let confidence: Double
}

struct FoodScanResponse: Codable {
    let food_name: String
    let total_calories: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let confidence: Double
    let items: [FoodScanItemResponse]
}

struct DailyIntakeResponse: Codable {
    let date: String
    let total_calories: Int
    let total_protein_g: Double
    let total_carbs_g: Double
    let total_fat_g: Double
    let meals_count: Int
    let daily_calorie_target: Int?
}

struct UserIdResponse: Decodable {
    let user_id: Int
}

struct MealLogItemResponse: Codable {
    let name: String
    let calories: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let logged_at: String
}

struct DailyMealLogsResponse: Codable {
    let date: String
    let meals: [MealLogItemResponse]
}

struct RecipeSuggestionItem: Codable, Identifiable {
    let id: String
    let name: String
    let summary: String
    let calories: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let ingredients: [String]
    let steps: [String]
    let tags: [String]
}

struct RecipeSuggestionResponse: Codable {
    let recipes: [RecipeSuggestionItem]
    let detected_ingredients: [String]
}

struct RecipeSearchResultItem: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let summary: String
    let image_url: String?
    let source: String?
}

struct RecipeSearchResponse: Codable {
    let results: [RecipeSearchResultItem]
    let detected_ingredients: [String]?
}

struct PlanDayResponse: Codable {
    let date: String
    let workout_plan: String
    let rest_day: Bool
    let calorie_target: Int
    let protein_g: Int
    let carbs_g: Int
    let fat_g: Int
}

struct ProfileUserResponse: Codable {
    let id: Int?
    let name: String?
    let birthdate: String?
    let height_cm: Double?
    let weight_kg: Double?
    let gender: String?
    let age_years: Int?
    let agent_name: String?
}

struct ProfilePreferencesResponse: Codable {
    let weekly_weight_change_kg: Double?
    let activity_level: String?
    let goal_type: String?
    let target_weight_kg: Double?
    let dietary_preferences: String?
    let workout_preferences: String?
    let timezone: String?
    let created_at: String?
}

struct ProfileResponse: Codable {
    let user: ProfileUserResponse?
    let preferences: ProfilePreferencesResponse?
}

struct ProgressCheckinResponse: Codable {
    let date: String
    let weight_kg: Double?
    let mood: String?
    let notes: String?
}

struct PlanCheckpointResponse: Codable {
    let week: Int
    let expected_weight_kg: Double
    let min_weight_kg: Double
    let max_weight_kg: Double
}

struct PlanSummaryResponse: Codable {
    let id: Int?
    let start_date: String?
    let end_date: String?
    let daily_calorie_target: Int?
    let protein_g: Int?
    let carbs_g: Int?
    let fat_g: Int?
    let status: String?
}

struct ProgressMealResponse: Codable {
    let id: Int?
    let logged_at: String?
    let description: String?
    let calories: Int?
    let protein_g: Double?
    let carbs_g: Double?
    let fat_g: Double?
    let confidence: Double?
    let confirmed: Bool?
}

struct ProgressWorkoutResponse: Codable {
    let id: Int?
    let date: String?
    let workout_type: String?
    let duration_min: Int?
    let calories_burned: Int?
    let completed: Bool?
    let source: String?
    let details: JSONValue?
}

struct ProgressResponse: Codable {
    let checkins: [ProgressCheckinResponse]
    let checkpoints: [PlanCheckpointResponse]
    let plan: PlanSummaryResponse?
    let meals: [ProgressMealResponse]
    let workouts: [ProgressWorkoutResponse]
}

struct CoachSuggestionResponse: Codable {
    let suggestion_type: String
    let rationale: String
    let suggestion_text: String
    let status: String?
    let created_at: String?
}

struct CoachSuggestionEnvelope: Codable {
    let suggestion: CoachSuggestionResponse?
}

struct ReminderItemResponse: Codable {
    let id: Int
    let reminder_type: String
    let scheduled_at: String
    let status: String
    let channel: String
    let related_plan_override_id: Int?
}

struct GamificationResponse: Codable {
    let points: Int
    let level: Int
    let next_level_points: Int
    let streak_days: Int
    let best_streak_days: Int
    let freeze_streaks: Int
    let unlocked_freeze_streaks: Int
    let used_freeze_streaks: Int
    let share_text: String
}

struct SessionHydrationResponse: Codable {
    let user_id: Int
    let date: String
    let profile: ProfileResponse
    let progress: ProgressResponse
    let today_plan: PlanDayResponse?
    let daily_intake: DailyIntakeResponse
    let gamification: GamificationResponse
    let coach_suggestion: CoachSuggestionResponse?
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

// This file intentionally left minimal to avoid conflicts.
// Most API responses use the same models as defined in:
// - FoodLog.swift
// - Workout.swift
// - AICoaching.swift
// - DailyProgress.swift
// - User.swift


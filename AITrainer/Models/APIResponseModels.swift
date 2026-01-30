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

// This file intentionally left minimal to avoid conflicts.
// Most API responses use the same models as defined in:
// - FoodLog.swift
// - Workout.swift
// - AICoaching.swift
// - DailyProgress.swift
// - User.swift


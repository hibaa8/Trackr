//
//  FoodLog.swift
//  AITrainer
//
//  Food logging and nutrition data models
//

import Foundation
import UIKit

struct FoodLog: Identifiable, Codable {
    let id: UUID
    var userId: UUID
    var name: String
    var calories: Int
    var protein: Double // grams
    var carbs: Double // grams
    var fat: Double // grams
    var ingredients: [FoodIngredient]
    var imageURL: String?
    var mealType: MealType
    var timestamp: Date
    var isVerified: Bool
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        ingredients: [FoodIngredient] = [],
        imageURL: String? = nil,
        mealType: MealType = .other,
        timestamp: Date = Date(),
        isVerified: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.ingredients = ingredients
        self.imageURL = imageURL
        self.mealType = mealType
        self.timestamp = timestamp
        self.isVerified = isVerified
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct FoodIngredient: Identifiable, Codable {
    let id: UUID
    var name: String
    var calories: Int
    var amount: String
    var confidence: Double // 0.0 to 1.0 from AI recognition
    
    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        amount: String,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.amount = amount
        self.confidence = confidence
    }
}

enum MealType: String, Codable, CaseIterable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "leaf.fill"
        case .other: return "fork.knife"
        }
    }
}

// Response from AI food recognition service
struct FoodRecognitionResponse: Codable {
    var foodName: String
    var totalCalories: Int
    var macros: Macros
    var ingredients: [FoodIngredient]
    var confidence: Double
}

struct Macros: Codable {
    var protein: Double
    var carbs: Double
    var fat: Double
    
    init(protein: Double, carbs: Double, fat: Double) {
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
    
    var proteinCalories: Int {
        Int(protein * 4) // 4 calories per gram
    }
    
    var carbsCalories: Int {
        Int(carbs * 4) // 4 calories per gram
    }
    
    var fatCalories: Int {
        Int(fat * 9) // 9 calories per gram
    }
}

//
//  User.swift
//  AITrainer
//
//  User data model
//

import Foundation

struct User: Codable, Identifiable {
    let id: UUID
    var email: String
    var name: String
    var age: Int?
    var heightInches: Double?
    var weightPounds: Double?
    var goalWeightPounds: Double?
    var activityLevel: ActivityLevel
    var fitnessGoal: FitnessGoal
    var dailyCalorieTarget: Int
    var preferences: UserPreferences
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        email: String,
        name: String,
        age: Int? = nil,
        heightInches: Double? = nil,
        weightPounds: Double? = nil,
        goalWeightPounds: Double? = nil,
        activityLevel: ActivityLevel = .moderate,
        fitnessGoal: FitnessGoal = .maintain,
        dailyCalorieTarget: Int = 2000,
        preferences: UserPreferences = UserPreferences(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.age = age
        self.heightInches = heightInches
        self.weightPounds = weightPounds
        self.goalWeightPounds = goalWeightPounds
        self.activityLevel = activityLevel
        self.fitnessGoal = fitnessGoal
        self.dailyCalorieTarget = dailyCalorieTarget
        self.preferences = preferences
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary = "Sedentary"
    case light = "Lightly Active"
    case moderate = "Moderately Active"
    case very = "Very Active"
    case extra = "Extra Active"
    
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .very: return 1.725
        case .extra: return 1.9
        }
    }
}

enum FitnessGoal: String, Codable, CaseIterable {
    case lose = "Lose Weight"
    case maintain = "Maintain Weight"
    case gain = "Gain Weight"
    case muscle = "Build Muscle"
    
    var calorieAdjustment: Int {
        switch self {
        case .lose: return -500
        case .maintain: return 0
        case .gain: return 300
        case .muscle: return 400
        }
    }
}

struct UserPreferences: Codable {
    var enableNotifications: Bool = true
    var enableHealthKitSync: Bool = true
    var enableCalendarIntegration: Bool = false
    var preferredWorkoutTime: String = "morning"
    var dietaryRestrictions: [String] = []
    var dislikedExercises: [String] = []
    var likedExercises: [String] = []
}

//
//  DailyProgress.swift
//  AITrainer
//
//  Daily tracking and progress models
//

import Foundation

struct DailyProgress: Identifiable, Codable {
    let id: UUID
    var userId: UUID
    var date: Date
    var caloriesConsumed: Int
    var caloriesBurned: Int
    var calorieTarget: Int
    var macros: Macros
    var steps: Int
    var weight: Double?
    var workoutsCompleted: Int
    var mealsLogged: Int
    var waterIntake: Double // in ounces
    var sleepHours: Double?
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date = Date(),
        caloriesConsumed: Int = 0,
        caloriesBurned: Int = 0,
        calorieTarget: Int = 2000,
        macros: Macros = Macros(protein: 0, carbs: 0, fat: 0),
        steps: Int = 0,
        weight: Double? = nil,
        workoutsCompleted: Int = 0,
        mealsLogged: Int = 0,
        waterIntake: Double = 0,
        sleepHours: Double? = nil
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.caloriesConsumed = caloriesConsumed
        self.caloriesBurned = caloriesBurned
        self.calorieTarget = calorieTarget
        self.macros = macros
        self.steps = steps
        self.weight = weight
        self.workoutsCompleted = workoutsCompleted
        self.mealsLogged = mealsLogged
        self.waterIntake = waterIntake
        self.sleepHours = sleepHours
    }
    
    var netCalories: Int {
        caloriesConsumed - caloriesBurned
    }
    
    var calorieProgress: Double {
        Double(caloriesConsumed) / Double(calorieTarget)
    }
    
    var isOnTrack: Bool {
        caloriesConsumed <= calorieTarget
    }
}

struct WeeklyProgress: Identifiable, Codable {
    let id: UUID
    var startDate: Date
    var endDate: Date
    var dailyProgress: [DailyProgress]
    
    init(id: UUID = UUID(), startDate: Date, endDate: Date, dailyProgress: [DailyProgress]) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.dailyProgress = dailyProgress
    }
    
    var averageCalories: Int {
        guard !dailyProgress.isEmpty else { return 0 }
        let total = dailyProgress.reduce(0) { $0 + $1.caloriesConsumed }
        return total / dailyProgress.count
    }
    
    var totalWorkouts: Int {
        dailyProgress.reduce(0) { $0 + $1.workoutsCompleted }
    }
    
    var averageSteps: Int {
        guard !dailyProgress.isEmpty else { return 0 }
        let total = dailyProgress.reduce(0) { $0 + $1.steps }
        return total / dailyProgress.count
    }
}

struct Streak: Codable {
    var workoutStreak: Int
    var mealLoggingStreak: Int
    var lastWorkoutDate: Date?
    var lastMealLogDate: Date?
    
    init(
        workoutStreak: Int = 0,
        mealLoggingStreak: Int = 0,
        lastWorkoutDate: Date? = nil,
        lastMealLogDate: Date? = nil
    ) {
        self.workoutStreak = workoutStreak
        self.mealLoggingStreak = mealLoggingStreak
        self.lastWorkoutDate = lastWorkoutDate
        self.lastMealLogDate = lastMealLogDate
    }
}

struct Achievement: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var icon: String
    var points: Int
    var unlockedAt: Date?
    var isUnlocked: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        icon: String,
        points: Int,
        unlockedAt: Date? = nil,
        isUnlocked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.icon = icon
        self.points = points
        self.unlockedAt = unlockedAt
        self.isUnlocked = isUnlocked
    }
}

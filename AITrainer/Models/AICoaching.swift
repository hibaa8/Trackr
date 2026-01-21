//
//  AICoaching.swift
//  AITrainer
//
//  AI coaching and suggestions models
//

import Foundation

struct AISuggestion: Identifiable, Codable {
    let id: UUID
    var userId: UUID
    var type: SuggestionType
    var title: String
    var description: String
    var reasoning: String // Why this suggestion is being made
    var priority: Priority
    var createdAt: Date
    var status: SuggestionStatus
    var acceptedAt: Date?
    var snoozedUntil: Date?
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        type: SuggestionType,
        title: String,
        description: String,
        reasoning: String,
        priority: Priority = .medium,
        createdAt: Date = Date(),
        status: SuggestionStatus = .pending,
        acceptedAt: Date? = nil,
        snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.description = description
        self.reasoning = reasoning
        self.priority = priority
        self.createdAt = createdAt
        self.status = status
        self.acceptedAt = acceptedAt
        self.snoozedUntil = snoozedUntil
    }
}

enum SuggestionType: String, Codable {
    case increaseCalories = "Increase Calories"
    case decreaseCalories = "Decrease Calories"
    case adjustMacros = "Adjust Macros"
    case addWorkout = "Add Workout"
    case reduceWorkout = "Reduce Workout"
    case changeExercise = "Change Exercise"
    case restDay = "Take Rest Day"
    case increaseProtein = "Increase Protein"
    case hydration = "Increase Water"
    case sleep = "Improve Sleep"
    
    var icon: String {
        switch self {
        case .increaseCalories, .decreaseCalories: return "fork.knife"
        case .adjustMacros: return "chart.pie.fill"
        case .addWorkout, .reduceWorkout: return "figure.strengthtraining.traditional"
        case .changeExercise: return "arrow.triangle.2.circlepath"
        case .restDay: return "bed.double.fill"
        case .increaseProtein: return "flame.fill"
        case .hydration: return "drop.fill"
        case .sleep: return "moon.stars.fill"
        }
    }
}

enum Priority: String, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

enum SuggestionStatus: String, Codable {
    case pending = "Pending"
    case accepted = "Accepted"
    case rejected = "Rejected"
    case snoozed = "Snoozed"
}

struct CoachingSession: Identifiable, Codable {
    let id: UUID
    var userId: UUID
    var messages: [CoachingMessage]
    var startedAt: Date
    var endedAt: Date?
    var topic: String
    var outcome: String?
}

struct CoachingMessage: Identifiable, Codable {
    let id: UUID
    var content: String
    var isFromUser: Bool
    var timestamp: Date
    var suggestions: [AISuggestion]?
}

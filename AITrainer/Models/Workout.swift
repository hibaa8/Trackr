//
//  Workout.swift
//  AITrainer
//
//  Workout and exercise data models
//

import Foundation

struct Workout: Identifiable, Codable {
    let id: UUID
    var userId: UUID
    var name: String
    var type: WorkoutType
    var exercises: [Exercise]
    var duration: TimeInterval // in seconds
    var caloriesBurned: Int
    var timestamp: Date
    var isCompleted: Bool
    var notes: String?
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        type: WorkoutType,
        exercises: [Exercise] = [],
        duration: TimeInterval = 0,
        caloriesBurned: Int = 0,
        timestamp: Date = Date(),
        isCompleted: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.exercises = exercises
        self.duration = duration
        self.caloriesBurned = caloriesBurned
        self.timestamp = timestamp
        self.isCompleted = isCompleted
        self.notes = notes
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        return "\(minutes) min"
    }
}

enum WorkoutType: String, Codable, CaseIterable {
    case strength = "Strength Training"
    case cardio = "Cardio"
    case hiit = "HIIT"
    case yoga = "Yoga"
    case sports = "Sports"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .hiit: return "flame.fill"
        case .yoga: return "figure.mind.and.body"
        case .sports: return "sportscourt.fill"
        case .other: return "figure.walk"
        }
    }
}

struct Exercise: Identifiable, Codable {
    let id: UUID
    var name: String
    var sets: [ExerciseSet]
    var videoURL: String?
    var thumbnailURL: String?
    var instructions: String?
    var targetMuscles: [String]
    var isLiked: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        sets: [ExerciseSet] = [],
        videoURL: String? = nil,
        thumbnailURL: String? = nil,
        instructions: String? = nil,
        targetMuscles: [String] = [],
        isLiked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.instructions = instructions
        self.targetMuscles = targetMuscles
        self.isLiked = isLiked
    }
}

struct ExerciseSet: Identifiable, Codable {
    let id: UUID
    var reps: Int
    var weight: Double? // in pounds
    var duration: TimeInterval? // for time-based exercises
    var isCompleted: Bool
    
    init(
        id: UUID = UUID(),
        reps: Int = 0,
        weight: Double? = nil,
        duration: TimeInterval? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.duration = duration
        self.isCompleted = isCompleted
    }
}

struct WorkoutPlan: Identifiable, Codable {
    let id: UUID
    var userId: UUID
    var name: String
    var description: String
    var workouts: [Workout]
    var daysPerWeek: Int
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        description: String,
        workouts: [Workout] = [],
        daysPerWeek: Int = 3,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.description = description
        self.workouts = workouts
        self.daysPerWeek = daysPerWeek
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
    }
}

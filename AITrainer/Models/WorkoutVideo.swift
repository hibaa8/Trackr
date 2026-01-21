//
//  WorkoutVideo.swift
//  AITrainer
//
//  Models for workout videos from Python backend
//

import Foundation

struct WorkoutVideo: Identifiable, Codable {
    let id: String
    let title: String
    let instructor: String
    let duration: Int // minutes
    let formattedDuration: String
    let difficulty: String
    let thumbnailURL: String
    let embedURL: String
    let youtubeURL: String
    let viewCount: Int
    let description: String

    var difficultyEnum: WorkoutDifficulty {
        WorkoutDifficulty(rawValue: difficulty.lowercased()) ?? .intermediate
    }

    var difficultyColor: String {
        switch difficultyEnum {
        case .beginner:
            return "green"
        case .intermediate:
            return "orange"
        case .advanced:
            return "red"
        }
    }

    // For backward compatibility with existing UI
    var category: WorkoutCategory {
        .cardio // Default, will be determined by which endpoint we called
    }

    var videoSource: VideoSource {
        .youtube(id: id)
    }
}

enum WorkoutDifficulty: String, CaseIterable, Codable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"

    var displayName: String {
        switch self {
        case .beginner:
            return "Beginner"
        case .intermediate:
            return "Intermediate"
        case .advanced:
            return "Advanced"
        }
    }
}

enum WorkoutCategory: String, CaseIterable, Codable {
    case all = "all"
    case cardio = "cardio"
    case strength = "strength"
    case yoga = "yoga"
    case hiit = "hiit"

    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .cardio:
            return "Cardio"
        case .strength:
            return "Strength"
        case .yoga:
            return "Yoga"
        case .hiit:
            return "HIIT"
        }
    }

    var emoji: String {
        switch self {
        case .all:
            return "🏃‍♂️"
        case .cardio:
            return "❤️"
        case .strength:
            return "💪"
        case .yoga:
            return "🧘‍♀️"
        case .hiit:
            return "⚡"
        }
    }
}

enum VideoSource: Codable {
    case youtube(id: String)
    case vimeo(id: String)
    case direct(url: String)

    var youtubeId: String? {
        if case .youtube(let id) = self {
            return id
        }
        return nil
    }

    var embedURL: String {
        switch self {
        case .youtube(let id):
            return "https://www.youtube-nocookie.com/embed/\(id)"
        case .vimeo(let id):
            return "https://player.vimeo.com/video/\(id)"
        case .direct(let url):
            return url
        }
    }
}

// Response models for Python backend
struct VideoResponse: Codable {
    let category: String
    let total: Int
    let videos: [WorkoutVideo]
}

struct CategoryResponse: Codable {
    let categories: [Category]
}

struct Category: Codable {
    let key: String
    let name: String
    let emoji: String
}
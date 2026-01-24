//
//  Gym.swift
//  AITrainer
//
//  Models for gyms and fitness classes
//

import Foundation
import CoreLocation

struct Gym: Identifiable, Codable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double?
    let priceLevel: Int?
    let photoReference: String?
    let photoURL: String?
    let placeId: String
    let isOpen: Bool?
    let phoneNumber: String?
    let website: String?
    let types: [String]

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var formattedRating: String {
        guard let rating = rating else { return "No rating" }
        return String(format: "%.1f", rating)
    }

    var priceDescription: String {
        guard let priceLevel = priceLevel else { return "Price not available" }
        return String(repeating: "$", count: priceLevel)
    }

    func distance(from location: CLLocation) -> String {
        let distance = location.distance(from: self.location)
        if distance < 1000 {
            return String(format: "%.0f m away", distance)
        } else {
            return String(format: "%.1f mi away", distance * 0.000621371)
        }
    }
}

struct GymClass: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: ClassType
    let instructor: String
    let gymName: String
    let time: Date
    let duration: Int // minutes
    let spotsLeft: Int
    let totalSpots: Int
    let rating: Double
    let price: Double?

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: time)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(time) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(time) {
            return "Tomorrow"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: time)
        }
    }

    var formattedDuration: String {
        if duration >= 60 {
            let hours = duration / 60
            let minutes = duration % 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        } else {
            return "\(duration) min"
        }
    }

    var formattedPrice: String? {
        guard let price = price else { return nil }
        return String(format: "$%.0f", price)
    }

    var availability: String {
        if spotsLeft == 0 {
            return "Fully booked"
        } else {
            return "\(spotsLeft) spots left"
        }
    }
}

enum ClassType: String, CaseIterable, Codable {
    case hiit = "HIIT"
    case yoga = "Yoga"
    case spinning = "Cycling"
    case strength = "Strength"
    case cardio = "Cardio"
    case pilates = "Pilates"
    case boxing = "Boxing"
    case dance = "Dance"

    var emoji: String {
        switch self {
        case .hiit:
            return "⚡"
        case .yoga:
            return "🧘‍♀️"
        case .spinning:
            return "🚴‍♀️"
        case .strength:
            return "💪"
        case .cardio:
            return "❤️"
        case .pilates:
            return "🤸‍♀️"
        case .boxing:
            return "🥊"
        case .dance:
            return "💃"
        }
    }

    var color: String {
        switch self {
        case .hiit:
            return "orange"
        case .yoga:
            return "green"
        case .spinning:
            return "blue"
        case .strength:
            return "red"
        case .cardio:
            return "pink"
        case .pilates:
            return "purple"
        case .boxing:
            return "gray"
        case .dance:
            return "yellow"
        }
    }
}

// MARK: - Google Places API Response Models

struct GymSearchResponse: Codable {
    let results: [GymResult]?
    let status: String
    let nextPageToken: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case results
        case status
        case nextPageToken = "next_page_token"
        case errorMessage = "error_message"
    }
}

struct GymResult: Codable {
    let placeId: String
    let name: String
    let geometry: PlaceGeometry
    let vicinity: String?
    let formattedAddress: String?
    let rating: Double?
    let priceLevel: Int?
    let photos: [PlacePhoto]?
    let openingHours: OpeningHours?
    let types: [String]
    let businessStatus: String?

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name
        case geometry
        case vicinity
        case formattedAddress = "formatted_address"
        case rating
        case priceLevel = "price_level"
        case photos
        case openingHours = "opening_hours"
        case types
        case businessStatus = "business_status"
    }

    func toGym(baseURL: String) -> Gym {
        let reference = photos?.first?.photoReference
        let encodedRef = reference?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        let photoURL = encodedRef.map { "\(baseURL)/gyms/photo?ref=\($0)&maxwidth=400" }

        return Gym(
            id: placeId,
            name: name,
            address: formattedAddress ?? vicinity ?? "Address not available",
            latitude: geometry.location.lat,
            longitude: geometry.location.lng,
            rating: rating,
            priceLevel: priceLevel,
            photoReference: reference,
            photoURL: photoURL,
            placeId: placeId,
            isOpen: openingHours?.openNow,
            phoneNumber: nil, // Will be fetched with place details if needed
            website: nil,
            types: types
        )
    }
}

struct PlaceGeometry: Codable {
    let location: PlaceLocation
}

struct PlaceLocation: Codable {
    let lat: Double
    let lng: Double
}

struct PlacePhoto: Codable {
    let photoReference: String
    let height: Int
    let width: Int

    enum CodingKeys: String, CodingKey {
        case photoReference = "photo_reference"
        case height
        case width
    }
}

struct OpeningHours: Codable {
    let openNow: Bool

    enum CodingKeys: String, CodingKey {
        case openNow = "open_now"
    }
}
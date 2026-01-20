//
//  APIService.swift
//  AITrainer
//
//  Backend API communication service
//

import Foundation
import Combine

enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(Error)
    case serverError(Int)
    case unauthorized
}

class APIService {
    static let shared = APIService()
    
    private let baseURL = "https://api.trackr.app" // Replace with your actual backend URL
    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Generic Request Method
    
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String]? = nil
    ) -> AnyPublisher<T, APIError> {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add auth token if available
        if let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 401 {
                        throw APIError.unauthorized
                    }
                    throw APIError.serverError(httpResponse.statusCode)
                }
                
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error in
                if let apiError = error as? APIError {
                    return apiError
                } else if error is DecodingError {
                    return APIError.decodingFailed(error)
                } else {
                    return APIError.requestFailed(error)
                }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Authentication
    
    func signIn(email: String, password: String) -> AnyPublisher<User, APIError> {
        let body = ["email": email, "password": password]
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        return request(endpoint: "/auth/signin", method: "POST", body: jsonData)
    }
    
    func signUp(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        let body = ["email": email, "password": password, "name": name]
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        return request(endpoint: "/auth/signup", method: "POST", body: jsonData)
    }
    
    // MARK: - Food Logging
    
    func analyzeFoodImage(imageData: Data) -> AnyPublisher<FoodRecognitionResponse, APIError> {
        // In production, upload image to Google Vision API + Gemini API
        // For now, return mock data
        let mockIngredient = FoodIngredient(
            name: "Sample Ingredient",
            calories: 100,
            amount: "1 cup",
            confidence: 0.85
        )
        
        let mockResponse = FoodRecognitionResponse(
            foodName: "Sample Food",
            totalCalories: 300,
            macros: Macros(protein: 10, carbs: 30, fat: 15),
            ingredients: [mockIngredient],
            confidence: 0.85
        )
        
        return Just(mockResponse)
            .setFailureType(to: APIError.self)
            .eraseToAnyPublisher()
    }
    
    func saveFoodLog(_ foodLog: FoodLog) -> AnyPublisher<FoodLog, APIError> {
        guard let jsonData = try? JSONEncoder().encode(foodLog) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        return request(endpoint: "/food-logs", method: "POST", body: jsonData)
    }
    
    func getFoodLogs(date: Date) -> AnyPublisher<[FoodLog], APIError> {
        let dateString = ISO8601DateFormatter().string(from: date)
        return request(endpoint: "/food-logs?date=\(dateString)")
    }
    
    // MARK: - Workouts
    
    func saveWorkout(_ workout: Workout) -> AnyPublisher<Workout, APIError> {
        guard let jsonData = try? JSONEncoder().encode(workout) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        return request(endpoint: "/workouts", method: "POST", body: jsonData)
    }
    
    func getWorkoutPlan() -> AnyPublisher<WorkoutPlan, APIError> {
        return request(endpoint: "/workout-plan")
    }
    
    // MARK: - Progress
    
    func getDailyProgress(date: Date) -> AnyPublisher<DailyProgress, APIError> {
        let dateString = ISO8601DateFormatter().string(from: date)
        return request(endpoint: "/progress/daily?date=\(dateString)")
    }
    
    func getWeeklyProgress(startDate: Date) -> AnyPublisher<WeeklyProgress, APIError> {
        let dateString = ISO8601DateFormatter().string(from: startDate)
        return request(endpoint: "/progress/weekly?start=\(dateString)")
    }
    
    // MARK: - AI Coaching
    
    func getAISuggestions() -> AnyPublisher<[AISuggestion], APIError> {
        return request(endpoint: "/ai/suggestions")
    }
    
    func respondToSuggestion(suggestionId: UUID, response: SuggestionStatus) -> AnyPublisher<AISuggestion, APIError> {
        let body = ["status": response.rawValue]
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        return request(endpoint: "/ai/suggestions/\(suggestionId.uuidString)", method: "PATCH", body: jsonData)
    }
    
    func sendCoachingMessage(_ message: String) -> AnyPublisher<CoachingMessage, APIError> {
        let body = ["message": message]
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        return request(endpoint: "/ai/chat", method: "POST", body: jsonData)
    }
    
    // MARK: - User Profile
    
    func updateUserProfile(_ user: User) -> AnyPublisher<User, APIError> {
        guard let jsonData = try? JSONEncoder().encode(user) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        return request(endpoint: "/users/profile", method: "PUT", body: jsonData)
    }
    
    func getUserProfile() -> AnyPublisher<User, APIError> {
        return request(endpoint: "/users/profile")
    }
    
    // MARK: - Helper Methods
    
    private func getAuthToken() -> String? {
        // Retrieve from Keychain or UserDefaults
        return UserDefaults.standard.string(forKey: "authToken")
    }
    
    func saveAuthToken(_ token: String) {
        // Save to Keychain in production
        UserDefaults.standard.set(token, forKey: "authToken")
    }
    
    func clearAuthToken() {
        UserDefaults.standard.removeObject(forKey: "authToken")
    }
}

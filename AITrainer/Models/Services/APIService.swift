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
    case serverErrorWithMessage(Int, String)
    case unauthorized
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server."
        case .decodingFailed:
            return "Failed to parse server response."
        case .serverErrorWithMessage(_, let message):
            return message
        case .serverError(let code):
            return "Server error (HTTP \(code))."
        case .unauthorized:
            return "You are not authorized. Please sign in again."
        }
    }
}

class APIService {
    static let shared = APIService()
    
    private struct APIErrorEnvelope: Decodable {
        let detail: String?
        let error: String?
        let message: String?
    }
    
    private var baseURL: String { BackendConfig.baseURL }
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
                    let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
                    let message = decoded?.detail ?? decoded?.error ?? decoded?.message
                    if let message, !message.isEmpty {
                        throw APIError.serverErrorWithMessage(httpResponse.statusCode, message)
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
        struct SignInRequest: Codable {
            let email: String
            let password: String
        }

        let body = SignInRequest(email: email, password: password)
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/auth/signin", method: "POST", body: jsonData)
    }

    func signUp(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        struct SignUpRequest: Codable {
            let email: String
            let password: String
            let name: String
        }

        let body = SignUpRequest(email: email, password: password, name: name)
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/auth/signup", method: "POST", body: jsonData)
    }
    
    // MARK: - Food Logging
    
    func analyzeFoodImage(imageData: Data) -> AnyPublisher<FoodScanResponse, APIError> {
        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"food.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let headers = ["Content-Type": "multipart/form-data; boundary=\(boundary)"]

        return request(endpoint: "/food/scan", method: "POST", body: body, headers: headers)
    }
    
    func saveFoodLog(_ foodLog: FoodLog) -> AnyPublisher<FoodLog, APIError> {
        guard let jsonData = try? JSONEncoder().encode(foodLog) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/food/logs", method: "POST", body: jsonData)
    }

    func getFoodLogs(date: Date, userId: Int) -> AnyPublisher<DailyMealLogsResponse, APIError> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return request(endpoint: "/food/logs?day=\(dateString)&user_id=\(userId)")
    }

    func getDailyIntake(date: Date, userId: Int) -> AnyPublisher<DailyIntakeResponse, APIError> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return request(endpoint: "/food/intake?day=\(dateString)&user_id=\(userId)")
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

    // MARK: - Plans

    func getTodayPlan(date: Date = Date(), userId: Int) -> AnyPublisher<PlanDayResponse, APIError> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return request(endpoint: "/plans/today?day=\(dateString)&user_id=\(userId)")
    }

    func getUserId(email: String) -> AnyPublisher<UserIdResponse, APIError> {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return request(endpoint: "/api/user-id?email=\(encoded)")
    }
    
    // MARK: - AI Coaching
    
    func getAISuggestions() -> AnyPublisher<[AISuggestion], APIError> {
        return request(endpoint: "/ai/suggestions")
    }
    
    func respondToSuggestion(suggestionId: UUID, response: SuggestionStatus) -> AnyPublisher<AISuggestion, APIError> {
        struct SuggestionResponse: Codable {
            let status: String
        }

        let body = SuggestionResponse(status: response.rawValue)
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/ai/suggestions/\(suggestionId.uuidString)", method: "PATCH", body: jsonData)
    }
    
    func sendCoachingMessage(_ message: String, userId: Int) -> AnyPublisher<CoachChatResponse, APIError> {
        struct ChatRequest: Codable {
            let message: String
            let user_id: Int
        }

        let body = ChatRequest(message: message, user_id: userId)
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/coach/chat", method: "POST", body: jsonData)
    }

    func getCoachSuggestion(userId: Int) -> AnyPublisher<CoachSuggestionEnvelope, APIError> {
        return request(endpoint: "/api/coach-suggestion?user_id=\(userId)")
    }

    // MARK: - Videos

    func getCategories() -> AnyPublisher<[String], APIError> {
        return request(endpoint: "/categories")
    }

    func getVideos(category: String? = nil, limit: Int = 10) -> AnyPublisher<[WorkoutVideo], APIError> {
        var endpoint = "/videos?limit=\(limit)"
        if let category = category {
            endpoint += "&category=\(category)"
        }
        return request(endpoint: endpoint)
    }

    func getVideo(videoId: String) -> AnyPublisher<WorkoutVideo, APIError> {
        return request(endpoint: "/video/\(videoId)")
    }

    // MARK: - Gyms

    func getNearbyGyms(latitude: Double, longitude: Double, radius: Int = 5000) -> AnyPublisher<[Gym], APIError> {
        let endpoint = "/gyms/nearby?lat=\(latitude)&lng=\(longitude)&radius=\(radius)"
        return (request(endpoint: endpoint) as AnyPublisher<GymSearchResponse, APIError>)
            .tryMap { response in
                guard response.status == "OK" else {
                    throw APIError.serverError(400)
                }
                return (response.results ?? []).map { $0.toGym(baseURL: self.baseURL) }
            }
            .mapError { error in
                if let apiError = error as? APIError {
                    return apiError
                }
                return APIError.requestFailed(error)
            }
            .eraseToAnyPublisher()
    }
    
    func searchGyms(query: String, latitude: Double, longitude: Double) -> AnyPublisher<[Gym], APIError> {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = "/gyms/search?query=\(encodedQuery)&lat=\(latitude)&lng=\(longitude)"
        return (request(endpoint: endpoint) as AnyPublisher<GymSearchResponse, APIError>)
            .tryMap { response in
                guard response.status == "OK" else {
                    throw APIError.serverError(400)
                }
                return (response.results ?? []).map { $0.toGym(baseURL: self.baseURL) }
            }
            .mapError { error in
                if let apiError = error as? APIError {
                    return apiError
                }
                return APIError.requestFailed(error)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Recipes

    func suggestRecipes(
        ingredients: String = "",
        cuisine: String? = nil,
        flavor: String? = nil,
        dietary: [String] = [],
        userId: Int
    ) -> AnyPublisher<RecipeSuggestionResponse, APIError> {
        struct RecipeSuggestRequest: Codable {
            let user_id: Int
            let ingredients: String
            let cuisine: String?
            let flavor: String?
            let dietary: [String]
        }

        let body = RecipeSuggestRequest(
            user_id: userId,
            ingredients: ingredients,
            cuisine: cuisine,
            flavor: flavor,
            dietary: dietary
        )

        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/recipes/suggest", method: "POST", body: jsonData)
    }

    func searchRecipes(query: String, maxResults: Int = 10) -> AnyPublisher<RecipeSearchResponse, APIError> {
        struct RecipeSearchRequest: Codable {
            let query: String
            let max_results: Int
        }

        let body = RecipeSearchRequest(query: query, max_results: maxResults)
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/recipes/search", method: "POST", body: jsonData)
    }
    
    // MARK: - User Profile
    
    func updateProfile(_ payload: ProfileUpdateRequest) -> AnyPublisher<ProfileResponse, APIError> {
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/profile", method: "PUT", body: jsonData)
    }

    func getProfile(userId: Int) -> AnyPublisher<ProfileResponse, APIError> {
        return request(endpoint: "/api/profile?user_id=\(userId)")
    }

    func getProgress(userId: Int) -> AnyPublisher<ProgressResponse, APIError> {
        return request(endpoint: "/api/progress?user_id=\(userId)")
    }

    func getCoaches() -> AnyPublisher<[Coach], APIError> {
        return request(endpoint: "/api/coaches")
    }

    func getReminders(userId: Int) -> AnyPublisher<[ReminderItemResponse], APIError> {
        return request(endpoint: "/api/reminders?user_id=\(userId)")
    }

    func createReminder(_ payload: ReminderCreateRequest) -> AnyPublisher<ReminderItemResponse, APIError> {
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/reminders", method: "POST", body: jsonData)
    }

    func updateReminder(reminderId: Int, payload: ReminderUpdateRequest) -> AnyPublisher<ReminderItemResponse, APIError> {
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/reminders/\(reminderId)", method: "PUT", body: jsonData)
    }

    func deleteReminder(reminderId: Int, userId: Int) -> AnyPublisher<ReminderDeleteResponse, APIError> {
        return request(endpoint: "/api/reminders/\(reminderId)?user_id=\(userId)", method: "DELETE")
    }

    func createBillingCheckoutSession(userId: Int, planTier: String = "premium") -> AnyPublisher<BillingCheckoutSessionResponse, APIError> {
        struct CheckoutRequest: Codable {
            let user_id: Int
            let plan_tier: String
        }
        guard let jsonData = try? JSONEncoder().encode(CheckoutRequest(user_id: userId, plan_tier: planTier)) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/billing/checkout-session", method: "POST", body: jsonData)
    }

    func getGamification(userId: Int) -> AnyPublisher<GamificationResponse, APIError> {
        return request(endpoint: "/api/gamification?user_id=\(userId)")
    }

    func notifyAppOpen(userId: Int) -> AnyPublisher<AppOpenStreakResponse, APIError> {
        return request(endpoint: "/api/gamification/app-open?user_id=\(userId)", method: "POST")
    }

    func submitStreakDecision(userId: Int, useFreeze: Bool) -> AnyPublisher<AppOpenStreakResponse, APIError> {
        let payload = StreakDecisionRequest(user_id: userId, use_freeze: useFreeze)
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/gamification/streak-decision", method: "POST", body: jsonData)
    }

    func getSessionHydration(userId: Int, date: Date = Date()) -> AnyPublisher<SessionHydrationResponse, APIError> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return request(endpoint: "/api/session/hydrate?user_id=\(userId)&day=\(dateString)")
    }

    func logHealthActivity(_ payload: HealthActivityLogRequest) -> AnyPublisher<HealthActivityLogResponse, APIError> {
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/health-activity/log", method: "POST", body: jsonData)
    }

    func getHealthActivityImpact(
        userId: Int,
        startDay: Date? = nil,
        endDay: Date = Date(),
        days: Int = 7
    ) -> AnyPublisher<HealthActivityImpactResponse, APIError> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let end = formatter.string(from: endDay)
        var endpoint = "/api/health-activity/impact?user_id=\(userId)&end_day=\(end)&days=\(days)"
        if let startDay {
            endpoint += "&start_day=\(formatter.string(from: startDay))"
        }
        return request(endpoint: endpoint)
    }

    func getLocalWorkoutVideos() -> AnyPublisher<[LocalWorkoutVideoResponse], APIError> {
        return request(endpoint: "/api/workout-local-videos")
    }

    func useFreezeStreak(userId: Int) -> AnyPublisher<GamificationResponse, APIError> {
        struct UseFreezePayload: Codable {
            let user_id: Int
        }
        guard let jsonData = try? JSONEncoder().encode(UseFreezePayload(user_id: userId)) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/gamification/use-freeze", method: "POST", body: jsonData)
    }

    func changeUserCoach(userId: Int, newCoachId: Int) -> AnyPublisher<CoachChangeResponse, APIError> {
        struct CoachChangeRequest: Codable {
            let user_id: Int
            let new_coach_id: Int
        }

        let body = CoachChangeRequest(user_id: userId, new_coach_id: newCoachId)
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }

        return request(endpoint: "/api/change-coach", method: "POST", body: jsonData)
    }

    // MARK: - Onboarding

    func completeOnboarding(payload: OnboardingCompletePayload) -> AnyPublisher<OnboardingCompleteResponse, APIError> {
        guard let jsonData = try? JSONEncoder().encode(payload) else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        return request(endpoint: "/api/onboarding/complete", method: "POST", body: jsonData)
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

struct OnboardingCompletePayload: Codable {
    let user_id: Int?
    let goal_type: String?
    let target_weight_kg: Double?
    let weekly_weight_change_kg: Double?
    let activity_level: String?
    let storyline: String?
    let trainer_id: Int?
    let personality: String?
    let voice: String?
    let timeframe_weeks: Int?
    let current_weight_kg: Double?
    let height_cm: Double?
    let age: Int?
    let fitness_background: String?
    let full_name: String?
    let workout_preference: String?
    let muscle_group_preferences: String?
    let sports_preferences: String?
    let allergies: String?
    let preferred_workout_time: String?
    let menstrual_cycle_notes: String?
    let location_context: String?
    let connect_google_calendar: Bool?
    let location_shared: Bool?
    let location_latitude: Double?
    let location_longitude: Double?

    init(
        user_id: Int?,
        goal_type: String?,
        target_weight_kg: Double?,
        weekly_weight_change_kg: Double?,
        activity_level: String?,
        storyline: String?,
        trainer_id: Int?,
        personality: String?,
        voice: String?,
        timeframe_weeks: Int?,
        current_weight_kg: Double?,
        height_cm: Double?,
        age: Int?,
        fitness_background: String?,
        full_name: String?,
        workout_preference: String? = nil,
        muscle_group_preferences: String? = nil,
        sports_preferences: String? = nil,
        allergies: String? = nil,
        preferred_workout_time: String? = nil,
        menstrual_cycle_notes: String? = nil,
        location_context: String? = nil,
        connect_google_calendar: Bool? = nil,
        location_shared: Bool? = nil,
        location_latitude: Double? = nil,
        location_longitude: Double? = nil
    ) {
        self.user_id = user_id
        self.goal_type = goal_type
        self.target_weight_kg = target_weight_kg
        self.weekly_weight_change_kg = weekly_weight_change_kg
        self.activity_level = activity_level
        self.storyline = storyline
        self.trainer_id = trainer_id
        self.personality = personality
        self.voice = voice
        self.timeframe_weeks = timeframe_weeks
        self.current_weight_kg = current_weight_kg
        self.height_cm = height_cm
        self.age = age
        self.fitness_background = fitness_background
        self.full_name = full_name
        self.workout_preference = workout_preference
        self.muscle_group_preferences = muscle_group_preferences
        self.sports_preferences = sports_preferences
        self.allergies = allergies
        self.preferred_workout_time = preferred_workout_time
        self.menstrual_cycle_notes = menstrual_cycle_notes
        self.location_context = location_context
        self.connect_google_calendar = connect_google_calendar
        self.location_shared = location_shared
        self.location_latitude = location_latitude
        self.location_longitude = location_longitude
    }
}

struct OnboardingCompleteResponse: Decodable {
    let ok: Bool?
    let error: String?
}

struct CoachChangeResponse: Decodable {
    let success: Bool
    let message: String?
    let next_change_available_at: String?
    let retry_after_days: Int?
}

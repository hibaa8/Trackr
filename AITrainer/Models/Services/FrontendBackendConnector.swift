//
//  FrontendBackendConnector.swift
//  AITrainer
//
//  Service to connect frontend components to backend services
//

import Foundation
import Combine
import SwiftUI

class FrontendBackendConnector: ObservableObject {
    static let shared = FrontendBackendConnector()

    @Published var dailyIntake: DailyIntakeResponse?
    @Published var weeklyCalories: [Int] = [0, 0, 0, 0, 0, 0, 0] // Sun-Sat
    @Published var coachResponse: String = ""
    @Published var profile: ProfileResponse?
    @Published var progress: ProgressResponse?
    @Published var coachSuggestion: CoachSuggestionResponse?
    @Published var isLoading = false
    private var currentUserId: Int?

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Food & Nutrition

    func loadDailyIntake(for date: Date = Date(), userId: Int) {
        isLoading = true
        APIService.shared.getDailyIntake(date: date, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    switch completion {
                    case .failure(let error):
                        print("❌ Failed to load daily intake: \(error)")
                    case .finished:
                        print("✅ Daily intake loaded successfully")
                    }
                },
                receiveValue: { [weak self] intake in
                    self?.dailyIntake = intake
                }
            )
            .store(in: &cancellables)
    }

    func loadWeeklyCalories(userId: Int) {
        let calendar = Calendar.current

        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()

            APIService.shared.getDailyIntake(date: date, userId: userId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("❌ Failed to load calories for day \(dayOffset): \(error)")
                        }
                    },
                    receiveValue: { [weak self] intake in
                        // Store calories in reverse order (most recent first)
                        self?.weeklyCalories[6 - dayOffset] = intake.total_calories
                        print("📊 Loaded \(intake.total_calories) calories for day \(dayOffset)")
                    }
                )
                .store(in: &cancellables)
        }
    }

    func sendFoodLog(_ foodLog: FoodLog) {
        APIService.shared.saveFoodLog(foodLog)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        print("❌ Failed to save food log: \(error)")
                    case .finished:
                        print("✅ Food log saved successfully")
                    }
                },
                receiveValue: { savedLog in
                    print("💾 Food log saved: \(savedLog.name)")
                    // Refresh daily intake after logging food
                    if let userId = self.currentUserId {
                        self.loadDailyIntake(userId: userId)
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - AI Coach Chat

    func sendMessageToCoach(_ message: String) {
        isLoading = true
        coachResponse = ""

        guard let userId = currentUserId else {
            isLoading = false
            coachResponse = "Missing user session. Please sign in again."
            return
        }

        APIService.shared.sendCoachingMessage(message, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    switch completion {
                    case .failure(let error):
                        print("❌ Failed to send message to coach: \(error)")
                        self?.coachResponse = "Sorry, I'm having trouble connecting right now. Please try again."
                    case .finished:
                        print("✅ Coach message sent successfully")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.coachResponse = response.reply
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Coach Suggestion

    func loadCoachSuggestion(userId: Int, completion: @escaping (Result<CoachSuggestionResponse?, Error>) -> Void) {
        APIService.shared.getCoachSuggestion(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { [weak self] response in
                    self?.coachSuggestion = response.suggestion
                    completion(.success(response.suggestion))
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Recipes

    func suggestRecipes(completion: @escaping (Result<[RecipeSuggestionItem], Error>) -> Void) {
        guard let userId = currentUserId else {
            completion(.failure(URLError(.userAuthenticationRequired)))
            return
        }
        APIService.shared.suggestRecipes(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { response in
                    completion(.success(response.recipes))
                }
            )
            .store(in: &cancellables)
    }

    func searchRecipes(query: String, completion: @escaping (Result<[RecipeSearchResultItem], Error>) -> Void) {
        APIService.shared.searchRecipes(query: query)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { response in
                    completion(.success(response.results))
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Videos

    func loadWorkoutVideos(completion: @escaping (Result<[WorkoutVideo], Error>) -> Void) {
        APIService.shared.getVideos()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { videos in
                    completion(.success(videos))
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Gyms

    func findNearbyGyms(latitude: Double, longitude: Double, completion: @escaping (Result<[Gym], Error>) -> Void) {
        APIService.shared.getNearbyGyms(latitude: latitude, longitude: longitude)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { gyms in
                    completion(.success(gyms))
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Profile & Progress

    func loadProfile(userId: Int, completion: @escaping (Result<ProfileResponse, Error>) -> Void) {
        APIService.shared.getProfile(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { [weak self] response in
                    self?.profile = response
                    completion(.success(response))
                }
            )
            .store(in: &cancellables)
    }

    func loadProgress(userId: Int, completion: @escaping (Result<ProgressResponse, Error>) -> Void) {
        APIService.shared.getProgress(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { [weak self] response in
                    self?.progress = response
                    completion(.success(response))
                }
            )
            .store(in: &cancellables)
    }

    func loadReminders(userId: Int, completion: @escaping (Result<[ReminderItemResponse], Error>) -> Void) {
        APIService.shared.getReminders(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { reminders in
                    completion(.success(reminders))
                }
            )
            .store(in: &cancellables)
    }

    func hydrateSession(userId: Int, date: Date = Date(), completion: @escaping (Result<SessionHydrationResponse, Error>) -> Void) {
        APIService.shared.getSessionHydration(userId: userId, date: date)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { [weak self] response in
                    self?.profile = response.profile
                    self?.progress = response.progress
                    self?.dailyIntake = response.daily_intake
                    self?.coachSuggestion = response.coach_suggestion
                    completion(.success(response))
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Health Check

    func checkBackendHealth() {
        // Simple health check to ensure backend is running
        let url = URL(string: "\(BackendConfig.baseURL)/health")!
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Backend health check failed: \(error)")
                } else {
                    print("✅ Backend is healthy and running")
                }
            }
        }.resume()
    }

    // MARK: - Initialize

    func initializeApp(userId: Int) {
        print("🚀 Initializing app with backend connection...")
        checkBackendHealth()
        currentUserId = userId
        hydrateSession(userId: userId) { [weak self] _ in
            self?.loadWeeklyCalories(userId: userId)
        }
    }
}
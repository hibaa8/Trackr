//
//  ViewModels.swift
//  AITrainer
//
//  View models for managing view state and business logic
//

import Foundation
import SwiftUI
import Combine
import PhotosUI
import AVFoundation

// MARK: - Dashboard ViewModel
class DashboardViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published var caloriesConsumed = 1250
    @Published var calorieTarget = 2500
    @Published var proteinEaten: Double = 75
    @Published var proteinTarget: Double = 150
    @Published var carbsEaten: Double = 138
    @Published var carbsTarget: Double = 275
    @Published var fatEaten: Double = 35
    @Published var fatTarget: Double = 70
    @Published var currentStreak = 15
    @Published var mealsLogged = 1
    @Published var recentMeals: [FoodLog] = []
    @Published var todaySuggestion: AISuggestion?
    @Published var showAICoach = false
    
    private var cancellables = Set<AnyCancellable>()
    private let backendConnector = FrontendBackendConnector.shared
    
    func loadDashboardData(userId: Int) {
        loadRecentMeals(userId: userId)
        loadTodaySuggestion(userId: userId)
        updateDailyTotals(userId: userId)
    }
    
    private func loadRecentMeals(userId: Int) {
        FoodScanService.shared.getDailyMeals(date: selectedDate, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    let mapped = response.meals.map { meal -> FoodLog in
                        FoodLog(
                            userId: UUID(),
                            name: meal.name,
                            calories: meal.calories,
                            protein: meal.protein_g,
                            carbs: meal.carbs_g,
                            fat: meal.fat_g,
                            ingredients: [],
                            imageURL: nil,
                            mealType: .other,
                            timestamp: formatter.date(from: meal.logged_at) ?? Date(),
                            isVerified: true
                        )
                    }
                    self?.recentMeals = mapped.prefix(5).map { $0 }
                    self?.mealsLogged = mapped.count
                case .failure:
                    break
                }
            }
        }

        // Listen for new food logs
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewFoodLog),
            name: NSNotification.Name("FoodLogAdded"),
            object: nil
        )
    }

    @objc private func handleNewFoodLog(_ notification: Notification) {
        if let foodLog = notification.object as? FoodLog {
            DispatchQueue.main.async {
                self.recentMeals.insert(foodLog, at: 0)
                // Keep only recent meals
                if self.recentMeals.count > 5 {
                    self.recentMeals = Array(self.recentMeals.prefix(5))
                }

                // Update daily totals
                // Uses the currently logged-in user id only.
                // Caller will trigger full refresh with explicit userId.
            }
        }
    }

    private func updateDailyTotals(userId: Int) {
        FoodScanService.shared.getDailyIntake(date: selectedDate, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let intake):
                    self?.caloriesConsumed = intake.total_calories
                    self?.proteinEaten = intake.total_protein_g
                    self?.carbsEaten = intake.total_carbs_g
                    self?.fatEaten = intake.total_fat_g
                    self?.mealsLogged = intake.meals_count
                case .failure:
                    break
                }
            }
        }
    }
    
    private func loadTodaySuggestion(userId: Int) {
        backendConnector.loadCoachSuggestion(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let suggestion):
                    self?.todaySuggestion = self?.mapSuggestion(suggestion)
                case .failure:
                    break
                }
            }
        }
    }

    private func mapSuggestion(_ suggestion: CoachSuggestionResponse?) -> AISuggestion? {
        guard let suggestion = suggestion else { return nil }
        let type = SuggestionType(rawValue: suggestion.suggestion_type) ?? .adjustMacros
        return AISuggestion(
            userId: UUID(),
            type: type,
            title: suggestion.suggestion_type.replacingOccurrences(of: "_", with: " ").capitalized,
            description: suggestion.suggestion_text,
            reasoning: suggestion.rationale,
            priority: .medium
        )
    }
}

// MARK: - Food Scanner ViewModel
class FoodScannerViewModel: NSObject, ObservableObject {
    @Published var isAnalyzing = false
    @Published var detectedIngredients: [String] = []
    @Published var recognitionResult: FoodRecognitionResponse?
    @Published var showNutritionDetails = false
    @Published var capturedImage: UIImage?
    
    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var cancellables = Set<AnyCancellable>()
    
    func startCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            // Add camera input
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                return
            }
            
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }
            
            // Add photo output
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }
    
    func stopCamera() {
        captureSession.stopRunning()
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func handlePhotoSelection(_ photoItem: PhotosPickerItem) {
        Task {
            if let data = try? await photoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.capturedImage = image
                    self.analyzeFood(image: image)
                }
            }
        }
    }

    private func analyzeFood(image: UIImage) {
        isAnalyzing = true

        // Simulate AI analysis - in production, call Google Vision API + Gemini API
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.detectedIngredients = ["Lettuce", "Parmesan", "Cherry Tomatoes", "Croutons"]

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.recognitionResult = FoodRecognitionResponse(
                    foodName: "Caesar Salad with Cherry Tomatoes",
                    totalCalories: 330,
                    macros: Macros(protein: 8, carbs: 20, fat: 18),
                    ingredients: [
                        FoodIngredient(name: "Lettuce", calories: 20, amount: "1.5 cups", confidence: 0.95),
                        FoodIngredient(name: "Parmesan", calories: 110, amount: "2 tbsp", confidence: 0.90),
                        FoodIngredient(name: "Cherry Tomatoes", calories: 30, amount: "10 pieces", confidence: 0.92),
                        FoodIngredient(name: "Croutons", calories: 120, amount: "1/2 cup", confidence: 0.88)
                    ],
                    confidence: 0.91
                )

                self?.isAnalyzing = false
                self?.showNutritionDetails = true
            }
        }
    }
}

extension FoodScannerViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
            self?.analyzeFood(image: image)
        }
    }
}

// MARK: - Nutrition Details ViewModel
class NutritionDetailsViewModel: ObservableObject {
    @Published var foodName: String
    @Published var totalCalories: Int
    @Published var protein: Int
    @Published var carbs: Int
    @Published var fat: Int
    @Published var ingredients: [FoodIngredient]
    @Published var quantity: Int = 1
    @Published var selectedMealType: MealType = .other
    @Published var showEditMode = false
    @Published var showAddIngredient = false
    @Published var showMealTypeSelection = false
    
    let foodImage: UIImage?
    private let baseCalories: Int
    private let baseMacros: Macros
    
    var currentTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
    
    init(recognition: FoodRecognitionResponse, image: UIImage? = nil) {
        self.foodName = recognition.foodName
        self.baseCalories = recognition.totalCalories
        self.totalCalories = recognition.totalCalories
        self.baseMacros = recognition.macros
        self.protein = Int(recognition.macros.protein)
        self.carbs = Int(recognition.macros.carbs)
        self.fat = Int(recognition.macros.fat)
        self.ingredients = recognition.ingredients
        self.foodImage = image

        // Auto-detect meal type based on current time
        self.selectedMealType = detectMealType()
    }
    
    func increaseQuantity() {
        quantity += 1
        updateNutrition()
    }
    
    func decreaseQuantity() {
        if quantity > 1 {
            quantity -= 1
            updateNutrition()
        }
    }
    
    private func updateNutrition() {
        totalCalories = baseCalories * quantity
        protein = Int(baseMacros.protein) * quantity
        carbs = Int(baseMacros.carbs) * quantity
        fat = Int(baseMacros.fat) * quantity
    }
    
    private func detectMealType() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5...10:
            return .breakfast
        case 11...15:
            return .lunch
        case 16...22:
            return .dinner
        default:
            return .snack
        }
    }

    func addIngredient(_ ingredient: FoodIngredient) {
        ingredients.append(ingredient)
        // Recalculate totals
        let additionalCalories = ingredient.calories * quantity
        totalCalories += additionalCalories
        // Note: In a real app, you'd also update macros based on ingredient composition
    }

    func removeIngredient(at index: Int) {
        guard index < ingredients.count else { return }
        let ingredient = ingredients[index]
        let removedCalories = ingredient.calories * quantity
        totalCalories -= removedCalories
        ingredients.remove(at: index)
    }

    func saveFoodLog() {
        // Create FoodLog object
        let foodLog = FoodLog(
            userId: UUID(), // In real app, get from current user
            name: foodName,
            calories: totalCalories,
            protein: Double(protein),
            carbs: Double(carbs),
            fat: Double(fat),
            ingredients: ingredients,
            mealType: selectedMealType,
            timestamp: Date(),
            isVerified: true
        )

        // Save photo if available
        if let image = foodImage {
            saveFoodImage(image, for: foodLog.id)
        }

        // In a real app, save to Core Data, API, or other persistence layer
        saveFoodLogToStorage(foodLog)

        print("✅ Saved food log: \(foodName), \(totalCalories) cal, \(selectedMealType.rawValue)")
    }

    private func saveFoodImage(_ image: UIImage, for foodLogId: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagePath = documentsPath.appendingPathComponent("food_\(foodLogId.uuidString).jpg")

        try? data.write(to: imagePath)
    }

    private func saveFoodLogToStorage(_ foodLog: FoodLog) {
        // Load existing logs
        var existingLogs: [FoodLog] = []
        if let data = UserDefaults.standard.data(forKey: "savedFoodLogs"),
           let logs = try? JSONDecoder().decode([FoodLog].self, from: data) {
            existingLogs = logs
        }

        // Add new log
        existingLogs.append(foodLog)

        // Save back to UserDefaults
        if let data = try? JSONEncoder().encode(existingLogs) {
            UserDefaults.standard.set(data, forKey: "savedFoodLogs")
        }

        // Post notification for dashboard update
        NotificationCenter.default.post(name: NSNotification.Name("FoodLogAdded"), object: foodLog)
    }
}

// MARK: - Onboarding ViewModel
class OnboardingViewModel: ObservableObject {
    @Published var currentStep = 1
    @Published var age = ""
    @Published var height = ""
    @Published var weight = ""
    @Published var goalWeight = ""
    @Published var selectedGoal: FitnessGoal?
    @Published var selectedActivityLevel: ActivityLevel?
    @Published var enableNotifications = true
    @Published var enableHealthKit = true
    @Published var enableCalendar = false
    
    var canContinue: Bool {
        switch currentStep {
        case 1:
            return !age.isEmpty && !height.isEmpty && !weight.isEmpty
        case 2:
            return selectedGoal != nil && !goalWeight.isEmpty
        case 3:
            return selectedActivityLevel != nil
        default:
            return true
        }
    }
    
    var calculatedCalories: Int {
        guard let ageInt = Int(age),
              let heightDouble = Double(height),
              let weightDouble = Double(weight),
              let activityLevel = selectedActivityLevel,
              let goal = selectedGoal else {
            return 2000
        }
        
        // Mifflin-St Jeor Equation (simplified for male)
        let bmr = (10 * weightDouble * 0.453592) + (6.25 * heightDouble * 2.54) - (5 * Double(ageInt)) + 5
        let tdee = bmr * activityLevel.multiplier
        let targetCalories = Int(tdee) + goal.calorieAdjustment
        
        return targetCalories
    }
    
    var recommendedWorkouts: Int {
        switch selectedActivityLevel {
        case .sedentary: return 2
        case .light: return 3
        case .moderate: return 4
        case .very: return 5
        case .extra: return 6
        default: return 3
        }
    }
    
    func nextStep() {
        if currentStep < 6 {
            withAnimation {
                currentStep += 1
            }
        }
    }
    
    func previousStep() {
        if currentStep > 1 {
            withAnimation {
                currentStep -= 1
            }
        }
    }
    
    func completeOnboarding() {
        // Save user data
        print("Onboarding complete")
    }
}


import AVFoundation

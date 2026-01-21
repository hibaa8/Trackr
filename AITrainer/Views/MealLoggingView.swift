import SwiftUI
import PhotosUI

struct MealLoggingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var showCamera = false
    @State private var detectedFoods: [DetectedFood] = []
    @State private var mealName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if currentStep == 0 {
                    cameraView
                } else if currentStep == 1 {
                    reviewView
                }
            }
            .navigationBarItems(
                leading: Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                },
                trailing: Text("AI Trainer")
                    .font(.system(size: 16, weight: .medium))
            )
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { newPhoto in
            if newPhoto != nil {
                simulateCapture()
            }
        }
    }
    
    var cameraView: some View {
        VStack(spacing: 0) {
            // Camera placeholder + controls
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black)

                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Camera Preview")
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 120)

                // Capture + Photo Library (inside the dark area)
                HStack(spacing: 32) {
                    Button(action: simulateCapture) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 70, height: 70)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        }
                    }

                    Button(action: { showPhotoPicker = true }) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                                    .frame(width: 56, height: 56)

                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Text("Photos")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .accessibilityLabel("Choose from Photos")
                }
                .padding(.bottom, 24)
            }
            
            // Instructions
            VStack(spacing: 8) {
                Text("AI Food Detection")
                    .font(.system(size: 16, weight: .semibold))
                Text("Position your food in the frame and tap to capture")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)
        }
    }
    
    var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Detected foods header
                Text("Detected Foods")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal)
                    .padding(.top)
                
                // Food items
                ForEach(detectedFoods) { food in
                    FoodItemCard(food: food)
                }
                .padding(.horizontal)
                
                // Total calories
                VStack(spacing: 8) {
                    HStack {
                        Text("Total Calories")
                            .font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Text("\(totalCalories)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        MacroLabel(emoji: "🥩", value: totalProtein, label: "Protein")
                        MacroLabel(emoji: "🍞", value: totalCarbs, label: "Carbs")
                        MacroLabel(emoji: "🧈", value: totalFats, label: "Fats")
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Meal name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal Name (Optional)")
                        .font(.system(size: 14, weight: .medium))
                    TextField("e.g., Lunch, Dinner", text: $mealName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                
                // Confirm button
                Button(action: logMeal) {
                    Text("Log Meal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding()
            }
        }
    }
    
    var totalCalories: Int {
        detectedFoods.reduce(0) { $0 + $1.calories }
    }
    
    var totalProtein: Int {
        detectedFoods.reduce(0) { $0 + $1.protein }
    }
    
    var totalCarbs: Int {
        detectedFoods.reduce(0) { $0 + $1.carbs }
    }
    
    var totalFats: Int {
        detectedFoods.reduce(0) { $0 + $1.fats }
    }
    
    func simulateCapture() {
        // Simulate AI detection
        detectedFoods = [
            DetectedFood(name: "Grilled Chicken Breast", portion: "6 oz", calories: 280, protein: 52, carbs: 0, fats: 6),
            DetectedFood(name: "Brown Rice", portion: "1 cup", calories: 218, protein: 5, carbs: 46, fats: 2),
            DetectedFood(name: "Steamed Broccoli", portion: "1 cup", calories: 55, protein: 4, carbs: 11, fats: 1)
        ]
        withAnimation {
            currentStep = 1
        }
    }
    
    func logMeal() {
        let meal = MealEntry(
            name: mealName.isEmpty ? "Meal" : mealName,
            calories: totalCalories,
            protein: totalProtein,
            carbs: totalCarbs,
            fats: totalFats,
            timestamp: Date()
        )
        appState.logMeal(meal)
        dismiss()
    }
}

struct FoodItemCard: View {
    let food: DetectedFood
    
    var body: some View {
        HStack(spacing: 12) {
            // Food icon
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text("🍽️")
                        .font(.system(size: 24))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(food.portion)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text("\(food.calories) cal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                    Text("P: \(food.protein)g")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("C: \(food.carbs)g")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("F: \(food.fats)g")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

struct MacroLabel: View {
    let emoji: String
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(emoji)
            Text("\(value)g")
                .font(.system(size: 16, weight: .semibold))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

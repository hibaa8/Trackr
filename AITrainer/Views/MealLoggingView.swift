import SwiftUI
import PhotosUI
import UIKit

struct MealLoggingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var showCamera = false
    @State private var detectedFoods: [DetectedFood] = []
    @State private var mealName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCameraCapture = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var scanResponse: FoodScanResponse?
    
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
            if let newPhoto = newPhoto {
                Task {
                    if let data = try? await newPhoto.loadTransferable(type: Data.self) {
                        analyzeImageData(data)
                    } else {
                        errorMessage = "Could not load photo data."
                    }
                }
            }
        }
        .sheet(isPresented: $showCameraCapture) {
            CameraImagePicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    analyzeImageData(data)
                } else {
                    errorMessage = "Could not process captured photo."
                }
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
                    Button(action: openCameraOrLibrary) {
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
            .overlay(
                Group {
                    if isAnalyzing {
                        ZStack {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                                Text("Analyzing food...")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(20)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(16)
                        }
                    }
                }
            )
            
            // Instructions
            VStack(spacing: 8) {
                Text("AI Food Detection")
                    .font(.system(size: 16, weight: .semibold))
                Text(isAnalyzing ? "Analyzing your meal..." : "Position your food in the frame and tap to capture")
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
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                // Detected foods header
                Text("Detected Foods")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal)
                    .padding(.top)
                
                // Food items (editable)
                ForEach($detectedFoods) { $food in
                    EditableFoodItemCard(food: $food, onRemove: {
                        removeFoodItem(id: food.id)
                    })
                }
                .padding(.horizontal)

                Button(action: addFoodItem) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add item")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
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
    
    func openCameraOrLibrary() {
        errorMessage = nil
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCameraCapture = true
        } else {
            showPhotoPicker = true
        }
    }

    func analyzeImageData(_ data: Data) {
        isAnalyzing = true
        errorMessage = nil
        FoodScanService.shared.scanFood(imageData: data) { result in
            DispatchQueue.main.async {
                isAnalyzing = false
                switch result {
                case .success(let response):
                    scanResponse = response
                    detectedFoods = response.items.map {
                        DetectedFood(
                            name: $0.name,
                            portion: $0.amount,
                            calories: $0.calories,
                            protein: Int($0.protein_g),
                            carbs: Int($0.carbs_g),
                            fats: Int($0.fat_g)
                        )
                    }
                    withAnimation {
                        currentStep = 1
                    }
                case .failure:
                    errorMessage = "Failed to analyze this photo. Please try another image."
                }
            }
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
        let payload = buildScanPayload()
        FoodScanService.shared.logMeal(payload, nameOverride: mealName.isEmpty ? nil : mealName) { _ in
            DispatchQueue.main.async {
                appState.refreshDailyData(for: appState.selectedDate)
            }
        }
        dismiss()
    }

    private func addFoodItem() {
        detectedFoods.append(
            DetectedFood(
                name: "New item",
                portion: "1 serving",
                calories: 0,
                protein: 0,
                carbs: 0,
                fats: 0
            )
        )
    }

    private func removeFoodItem(id: UUID) {
        detectedFoods.removeAll { $0.id == id }
    }

    private func buildScanPayload() -> FoodScanResponse {
        let foodName = mealName.isEmpty ? "Meal" : mealName
        let items = detectedFoods.map {
            FoodScanItemResponse(
                name: $0.name,
                amount: $0.portion,
                calories: $0.calories,
                protein_g: Double($0.protein),
                carbs_g: Double($0.carbs),
                fat_g: Double($0.fats),
                confidence: 0.7
            )
        }
        return FoodScanResponse(
            food_name: foodName,
            total_calories: totalCalories,
            protein_g: Double(totalProtein),
            carbs_g: Double(totalCarbs),
            fat_g: Double(totalFats),
            confidence: 0.7,
            items: items
        )
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct EditableFoodItemCard: View {
    @Binding var food: DetectedFood
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Food icon
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text("🍽️")
                            .font(.system(size: 24))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Food name", text: $food.name)
                        .font(.system(size: 16, weight: .semibold))
                    TextField("Amount", text: $food.portion)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Remove item")
            }

            HStack(spacing: 10) {
                NutrientField(label: "Cal", value: $food.calories)
                NutrientField(label: "P", value: $food.protein)
                NutrientField(label: "C", value: $food.carbs)
                NutrientField(label: "F", value: $food.fats)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

struct NutrientField: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            TextField("0", text: bindingString)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)
        }
    }

    private var bindingString: Binding<String> {
        Binding(
            get: { String(value) },
            set: { newValue in
                value = Int(newValue.filter { $0.isNumber }) ?? 0
            }
        )
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

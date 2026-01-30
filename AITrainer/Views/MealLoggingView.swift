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
    @State private var pulseScan = false
    @State private var isFlashOn = false

    private let foodCategoryIcons: [String: String] = [
        "protein": "🍗",
        "vegetable": "🥗",
        "fruit": "🍎",
        "grain": "🍚",
        "dairy": "🥛",
        "nuts": "🥜",
        "dessert": "🍰",
        "beverage": "🥤",
        "fast_food": "🍕",
        "soup": "🍜",
        "mixed": "🥙",
        "other": "❓"
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if currentStep == 0 {
                    cameraView
                } else if currentStep == 1 {
                    reviewView
                }
            }
            .navigationBarHidden(true)
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
        ZStack {
            Rectangle()
                .fill(Color.black)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                ZStack {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Camera Preview")
                            .foregroundColor(.white.opacity(0.7))
                    }

                    ScanGridOverlay()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 80)

                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.7), lineWidth: 3)
                                .frame(width: 80, height: 80)
                                .scaleEffect(pulseScan ? 1.15 : 0.85)
                                .opacity(pulseScan ? 0.15 : 0.6)
                                .animation(
                                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                    value: pulseScan
                                )
                        }
                        Text("Position food in frame and tap to capture.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(maxHeight: .infinity)

                VStack(spacing: 16) {
                    HStack {
                        Button(action: { showPhotoPicker = true }) {
                            Image(systemName: "photo")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                        }

                        Spacer()

                        Button(action: openCameraOrLibrary) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 80, height: 80)
                                    .shadow(color: Color.blue.opacity(0.6), radius: 20)
                                Circle()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 3)
                                    .frame(width: 88, height: 88)
                            }
                        }

                        Spacer()

                        Button(action: { showCameraCapture = true }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                        }
                    }
                    .padding(.horizontal, 40)

                    bottomInputBar
                }
                .padding(.bottom, 16)
            }
            .onAppear {
                pulseScan = true
            }

            if isAnalyzing {
                ZStack {
                    Color.black.opacity(0.4)
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
    }

    private var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }

            Spacer()

            Text("Log Food")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button(action: { isFlashOn.toggle() }) {
                Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var bottomInputBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "keyboard")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, height: 50)

            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.blue))

            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, height: 50)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.65))
        )
        .padding(.horizontal, 20)
    }

    private var reviewBottomInputBar: some View {
        HStack(spacing: 0) {
            Button(action: { dismiss() }) {
                Image(systemName: "keyboard")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 50, height: 50)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.blue))
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 50, height: 50)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    var reviewView: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.04)
                .ignoresSafeArea()

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
                    .foregroundColor(.white)
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
                            .foregroundColor(.white)
                        Text("Add item")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color.blue)
                    .cornerRadius(24)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                
                // Total calories
                VStack(spacing: 8) {
                    HStack {
                        Text("Total Calories")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(totalCalories)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        MacroLabel(emoji: "🥩", value: totalProtein, label: "Protein")
                        MacroLabel(emoji: "🍞", value: totalCarbs, label: "Carbs")
                        MacroLabel(emoji: "🧈", value: totalFats, label: "Fats")
                    }
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Meal name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal Name (Optional)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    TextField("e.g., Lunch, Dinner", text: $mealName)
                        .foregroundColor(.white)
                        .padding(16)
                        .background(Color(red: 0.16, green: 0.16, blue: 0.16))
                        .cornerRadius(12)
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
                .padding(.bottom, 80)
            }
        }

            VStack {
                Spacer()
                reviewBottomInputBar
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
                            category: $0.category ?? categorizeFood($0.name),
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
                category: "other",
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
                category: $0.category ?? categorizeFood($0.name),
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
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 6)
                .cornerRadius(3)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Food name", text: $food.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        TextField("1 serving", text: $food.portion)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.6))
                    }

                    Spacer()

                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Remove item")
                }

                LazyVGrid(columns: macroColumns, alignment: .leading, spacing: 12) {
                    MacroValueField(label: "Calories", value: $food.calories, suffix: "kcal")
                    MacroValueField(label: "Protein", value: $food.protein, suffix: "g")
                    MacroValueField(label: "Carbs", value: $food.carbs, suffix: "g")
                    MacroValueField(label: "Fats", value: $food.fats, suffix: "g")
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color(red: 0.13, green: 0.13, blue: 0.14))
        .cornerRadius(16)
    }

    private var macroColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4)
    }
}

struct MacroValueField: View {
    let label: String
    @Binding var value: Int
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.65))
            HStack(spacing: 4) {
                TextField("0", text: bindingString)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .keyboardType(.numberPad)
                    .frame(width: 40, alignment: .leading)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }
        }
    }

    private var bindingString: Binding<String> {
        Binding(
            get: { String(value) },
            set: { newValue in
                let digits = newValue.filter { $0.isNumber }
                value = Int(digits) ?? 0
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
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScanGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            Path { path in
                let thirdWidth = width / 3
                let thirdHeight = height / 3

                for i in 1..<3 {
                    let x = thirdWidth * CGFloat(i)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }

                for i in 1..<3 {
                    let y = thirdHeight * CGFloat(i)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        }
    }
}

private func iconForCategory(_ category: String?) -> String {
    let key = category?.lowercased() ?? "other"
    let map: [String: String] = [
        "protein": "🍗",
        "vegetable": "🥗",
        "fruit": "🍎",
        "grain": "🍚",
        "dairy": "🥛",
        "nuts": "🥜",
        "dessert": "🍰",
        "beverage": "🥤",
        "fast_food": "🍕",
        "soup": "🍜",
        "mixed": "🥙",
        "other": "❓"
    ]
    return map[key] ?? "❓"
}

private func categorizeFood(_ foodName: String) -> String {
    let name = foodName.lowercased()
    if name.contains("chicken") || name.contains("beef") || name.contains("fish") || name.contains("egg") || name.contains("pork") {
        return "protein"
    }
    if name.contains("salad") || name.contains("lettuce") || name.contains("broccoli") || name.contains("spinach") {
        return "vegetable"
    }
    if name.contains("apple") || name.contains("banana") || name.contains("orange") || name.contains("berry") {
        return "fruit"
    }
    if name.contains("rice") || name.contains("bread") || name.contains("pasta") || name.contains("noodle") {
        return "grain"
    }
    if name.contains("milk") || name.contains("yogurt") || name.contains("cheese") {
        return "dairy"
    }
    if name.contains("nut") || name.contains("almond") || name.contains("peanut") {
        return "nuts"
    }
    if name.contains("cake") || name.contains("cookie") || name.contains("dessert") {
        return "dessert"
    }
    if name.contains("coffee") || name.contains("tea") || name.contains("juice") || name.contains("soda") {
        return "beverage"
    }
    if name.contains("burger") || name.contains("pizza") || name.contains("fries") {
        return "fast_food"
    }
    if name.contains("soup") || name.contains("broth") {
        return "soup"
    }
    if name.contains("bowl") || name.contains("plate") || name.contains("mix") {
        return "mixed"
    }
    return "other"
}

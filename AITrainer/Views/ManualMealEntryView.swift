import SwiftUI

struct ManualMealEntryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss

    @State private var mealName = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fats = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Meal")) {
                    TextField("Meal name (optional)", text: $mealName)
                        .textInputAutocapitalization(.words)
                }

                Section(header: Text("Macros")) {
                    numberField(title: "Calories", text: $calories)
                    numberField(title: "Protein (g)", text: $protein)
                    numberField(title: "Carbs (g)", text: $carbs)
                    numberField(title: "Fat (g)", text: $fats)
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(isSaving ? "Saving..." : "Log Meal") {
                        logMeal()
                    }
                    .disabled(isSaving || caloriesValue == 0)
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var caloriesValue: Int {
        Int(calories.filter { $0.isNumber }) ?? 0
    }

    private var proteinValue: Int {
        Int(protein.filter { $0.isNumber }) ?? 0
    }

    private var carbsValue: Int {
        Int(carbs.filter { $0.isNumber }) ?? 0
    }

    private var fatsValue: Int {
        Int(fats.filter { $0.isNumber }) ?? 0
    }

    private func numberField(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    private func logMeal() {
        guard let userId = authManager.effectiveUserId else { return }
        let safeName = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemName = safeName.isEmpty ? "Manual entry" : safeName

        let item = FoodScanItemResponse(
            name: itemName,
            amount: "1 serving",
            calories: caloriesValue,
            protein_g: Double(proteinValue),
            carbs_g: Double(carbsValue),
            fat_g: Double(fatsValue),
            category: "other",
            confidence: 1.0
        )

        let payload = FoodScanResponse(
            food_name: itemName,
            total_calories: caloriesValue,
            protein_g: Double(proteinValue),
            carbs_g: Double(carbsValue),
            fat_g: Double(fatsValue),
            confidence: 1.0,
            items: [item]
        )

        isSaving = true
        errorMessage = nil
        FoodScanService.shared.logMeal(payload, userId: userId, nameOverride: safeName.isEmpty ? nil : safeName) { result in
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success:
                    self.appState.refreshDailyData(for: self.appState.selectedDate, userId: userId)
                    NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
                    self.dismiss()
                case .failure:
                    self.errorMessage = "Could not log your meal. Please try again."
                }
            }
        }
    }
}

#Preview {
    ManualMealEntryView()
        .environmentObject(AppState())
        .environmentObject(AuthenticationManager())
}

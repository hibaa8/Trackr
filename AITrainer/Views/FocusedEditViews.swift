//
//  FocusedEditViews.swift
//  AITrainer
//
//  Focused edit screens for individual profile fields
//

import SwiftUI

// MARK: - Generic Field Edit View

struct FieldEditView: View {
    let title: String
    let icon: String
    let color: Color
    let unit: String?
    @Binding var value: String
    @Environment(\.dismiss) var dismiss

    @State private var tempValue: String = ""

    init(title: String, icon: String, color: Color, value: Binding<String>, unit: String? = nil) {
        self.title = title
        self.icon = icon
        self.color = color
        self.unit = unit
        self._value = value
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.backgroundGradientStart,
                        Color.backgroundGradientEnd,
                        Color.white.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    // Header with icon
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.2))
                                .frame(width: 80, height: 80)

                            Image(systemName: icon)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(color)
                        }

                        Text(title)
                            .font(.headlineLarge)
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.top, 40)

                    // Input field
                    ModernCard {
                        VStack(spacing: 16) {
                            HStack {
                                TextField("Enter \(title.lowercased())", text: $tempValue)
                                    .font(.headlineMedium)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .keyboardType(isNumericField ? .decimalPad : .default)

                                if let unit = unit {
                                    Text(unit)
                                        .font(.bodyMedium)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.backgroundGradientStart)
                            )
                        }
                        .padding(24)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Edit \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        value = tempValue
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(tempValue.isEmpty)
                }
            }
        }
        .onAppear {
            tempValue = value
        }
    }

    private var isNumericField: Bool {
        ["Age", "Height", "Current Weight", "Goal Weight"].contains(title)
    }
}

// MARK: - Specific Edit Views

struct AgeEditView: View {
    @Binding var age: String

    var body: some View {
        FieldEditView(
            title: "Age",
            icon: "person.fill",
            color: .blue,
            value: $age,
            unit: "years"
        )
    }
}

struct HeightEditView: View {
    @Binding var height: String

    var body: some View {
        FieldEditView(
            title: "Height",
            icon: "ruler.fill",
            color: .green,
            value: $height,
            unit: "inches"
        )
    }
}

struct WeightEditView: View {
    @Binding var weight: String

    var body: some View {
        FieldEditView(
            title: "Current Weight",
            icon: "scalemass.fill",
            color: .purple,
            value: $weight,
            unit: "lbs"
        )
    }
}

struct GoalWeightEditView: View {
    @Binding var goalWeight: String

    var body: some View {
        FieldEditView(
            title: "Goal Weight",
            icon: "target",
            color: .orange,
            value: $goalWeight,
            unit: "lbs"
        )
    }
}

// MARK: - Setup Prompt View

struct SetupPromptView: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        ModernCard {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(color)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)

                    Text(description)
                        .font(.captionLarge)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: action) {
                    HStack(spacing: 8) {
                        Text("Set up now")
                            .font(.captionLarge)
                            .fontWeight(.semibold)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(color)
                }
            }
            .padding(24)
        }
    }
}

#Preview {
    @State var age = "25"
    return AgeEditView(age: $age)
}
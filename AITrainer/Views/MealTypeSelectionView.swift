//
//  MealTypeSelectionView.swift
//  AITrainer
//
//  View for selecting meal type
//

import SwiftUI

struct MealTypeSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selection: MealType

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Text("When did you eat this?")
                                .font(.headlineLarge)
                                .foregroundColor(.textPrimary)

                            Text("Select the meal type to help track your daily nutrition")
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                        // Meal type options
                        LazyVStack(spacing: 12) {
                            ForEach(MealType.allCases, id: \.rawValue) { mealType in
                                MealTypeCard(
                                    mealType: mealType,
                                    isSelected: selection == mealType
                                ) {
                                    selection = mealType
                                    dismiss()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Meal Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MealTypeCard: View {
    let mealType: MealType
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    private var timeDescription: String {
        switch mealType {
        case .breakfast:
            return "5:00 AM - 11:00 AM"
        case .lunch:
            return "11:00 AM - 3:00 PM"
        case .dinner:
            return "4:00 PM - 10:00 PM"
        case .snack:
            return "Anytime"
        case .other:
            return "Custom timing"
        }
    }

    private var cardGradient: LinearGradient {
        if isSelected {
            return LinearGradient.fitnessGradient
        } else {
            return LinearGradient(
                colors: [Color.backgroundGradientStart],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var body: some View {
        Button(action: action) {
            ModernCard {
                HStack(spacing: 16) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.2) : mealTypeColor.opacity(0.2))
                            .frame(width: 56, height: 56)

                        Image(systemName: mealType.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(isSelected ? .white : mealTypeColor)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mealType.rawValue)
                            .font(.headlineMedium)
                            .foregroundColor(isSelected ? .white : .textPrimary)

                        Text(timeDescription)
                            .font(.bodyMedium)
                            .foregroundColor(isSelected ? Color.white.opacity(0.8) : .textSecondary)
                    }

                    Spacer()

                    // Selection indicator
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color.textTertiary.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(20)
                .background(cardGradient)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var mealTypeColor: Color {
        switch mealType {
        case .breakfast:
            return .orange
        case .lunch:
            return .blue
        case .dinner:
            return .purple
        case .snack:
            return .green
        case .other:
            return .gray
        }
    }
}

#Preview {
    MealTypeSelectionView(selection: .constant(.breakfast))
}
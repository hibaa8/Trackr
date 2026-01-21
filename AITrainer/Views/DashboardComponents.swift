//
//  DashboardComponents.swift
//  AITrainer
//
//  Reusable components for the Dashboard
//

import SwiftUI

// MARK: - Week Date Picker

struct WeekDatePicker: View {
    @Binding var selectedDate: Date
    @State private var currentWeekOffset: Int = 0

    private let calendar = Calendar.current
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let shortWeekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var weekDates: [Date] {
        let today = Date()
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
            return []
        }

        guard let weekStart = calendar.date(byAdding: .weekOfYear, value: currentWeekOffset, to: startOfWeek) else {
            return []
        }

        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }

    var body: some View {
        ModernCard {
            VStack(spacing: 20) {
                // Stunning month header with gradient text
                HStack {
                    ModernIconButton(
                        icon: "chevron.left",
                        size: 36,
                        gradient: LinearGradient(
                            colors: [Color.textSecondary.opacity(0.6), Color.textSecondary.opacity(0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    ) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            moveWeek(by: -1)
                        }
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text(monthText)
                            .font(.headlineLarge)
                            .foregroundColor(.textPrimary)

                        Text(yearText)
                            .font(.captionLarge)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    ModernIconButton(
                        icon: "chevron.right",
                        size: 36,
                        gradient: LinearGradient(
                            colors: [Color.textSecondary.opacity(0.6), Color.textSecondary.opacity(0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    ) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            moveWeek(by: 1)
                        }
                    }
                }

                // Modern week layout
                VStack(spacing: 16) {
                    // Weekday labels
                    HStack(spacing: 0) {
                        ForEach(Array(shortWeekdays.enumerated()), id: \.offset) { index, day in
                            Text(day)
                                .font(.captionMedium)
                                .foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Date buttons with stunning effects
                    HStack(spacing: 8) {
                        ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                            DateButton(
                                date: date,
                                isSelected: isSelected(date),
                                isToday: isToday(date)
                            ) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    selectedDate = date
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: weekDates.first ?? Date())
    }

    private var yearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: weekDates.first ?? Date())
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: Date())
    }

    private func moveWeek(by weeks: Int) {
        currentWeekOffset += weeks
    }
}

struct DateButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Background effects
                    if isSelected {
                        // Outer glow
                        Circle()
                            .fill(LinearGradient.fitnessGradient)
                            .frame(width: 48, height: 48)
                            .blur(radius: 8)

                        // Main circle
                        Circle()
                            .fill(LinearGradient.fitnessGradient)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    } else if isToday {
                        Circle()
                            .fill(Color.backgroundGradientEnd)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(LinearGradient.fitnessGradient, lineWidth: 2)
                            )
                    } else {
                        Circle()
                            .fill(Color.backgroundGradientStart)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.textTertiary.opacity(0.2), lineWidth: 1)
                            )
                    }

                    // Date text
                    Text("\(calendar.component(.day, from: date))")
                        .font(.bodyMedium)
                        .fontWeight(isSelected ? .bold : .medium)
                        .foregroundColor(
                            isSelected ? .white :
                            isToday ? .textPrimary :
                            .textSecondary
                        )
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Main Calorie Ring

struct MainCalorieRing: View {
    let consumed: Int
    let target: Int
    let mealsRemaining: Int

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(consumed) / Double(target), 1.0)
    }

    var remaining: Int {
        max(0, target - consumed)
    }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                .frame(width: 200, height: 200)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(LinearGradient.fitnessGradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.0), value: progress)

            // Center content
            VStack(spacing: 8) {
                Text("\(consumed)")
                    .font(.numericLarge)
                    .foregroundColor(.textPrimary)

                Text("of \(target) cal")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)

                if progress >= 1.0 {
                    Text("Goal reached!")
                        .font(.captionLarge)
                        .foregroundColor(.fitnessGradientStart)
                        .fontWeight(.semibold)
                        .padding(.top, 4)
                } else {
                    Text("\(remaining) left")
                        .font(.captionLarge)
                        .foregroundColor(.textSecondary)
                        .padding(.top, 4)
                }
            }

            // Progress dot
            if progress > 0 {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(Color.fitnessGradientEnd)
                            .frame(width: 12, height: 12)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .offset(
                        x: cos(.pi * 2 * progress - .pi / 2) * 100,
                        y: sin(.pi * 2 * progress - .pi / 2) * 100
                    )
                    .animation(.easeInOut(duration: 1.0), value: progress)
            }
        }
        .frame(height: 280)
        .modernCardShadow()
    }
}

// MARK: - Macro Ring

struct MacroRing: View {
    let value: Int
    let total: Int
    let label: String
    let gradient: LinearGradient

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(Double(value) / Double(total), 1.0)
    }

    var body: some View {
        ModernCard {
            VStack(spacing: 20) {
                ringView
                labelView
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private var ringView: some View {
        ZStack {
            backgroundRing
            progressRing
            centerContent
            if progress > 0 { progressDot }
        }
    }

    private var backgroundRing: some View {
        Circle()
            .stroke(Color.gray.opacity(0.08), lineWidth: 8)
            .frame(width: 100, height: 100)
    }

    private var progressRing: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            .frame(width: 100, height: 100)
            .rotationEffect(.degrees(-90))
            .animation(.spring(response: 1.5, dampingFraction: 0.7), value: progress)
    }

    private var centerContent: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)

            Text("/ \(total)g")
                .font(.captionMedium)
                .foregroundColor(.textSecondary)
        }
    }

    private var progressDot: some View {
        let angle = .pi * 2 * progress - .pi / 2
        let xOffset = cos(angle) * 50
        let yOffset = sin(angle) * 50

        return Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .offset(x: xOffset, y: yOffset)
            .animation(.spring(response: 1.5, dampingFraction: 0.7), value: progress)
    }

    private var labelView: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.bodyMedium)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            progressBadge
        }
    }

    private var progressBadge: some View {
        HStack(spacing: 8) {
            Text("\(Int(progress * 100))%")
                .font(.captionLarge)
                .foregroundColor(.textPrimary)
                .fontWeight(.semibold)

            if progress >= 1.0 {
                Text("✓")
                    .font(.captionLarge)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.gray.opacity(0.1)))
        .overlay(Capsule().stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Macro Tag Component

struct MacroTag: View {
    let icon: String
    let value: Int
    let unit: String
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
                .font(.captionMedium)

            Text("\(value)\(unit)")
                .font(.captionLarge)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(gradient.opacity(0.15))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(gradient.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Week Date Picker") {
    WeekDatePicker(selectedDate: .constant(Date()))
        .padding()
}

#Preview("Main Calorie Ring") {
    MainCalorieRing(consumed: 1420, target: 2000, mealsRemaining: 6)
        .padding()
}

#Preview("Macro Rings") {
    HStack(spacing: 20) {
        MacroRing(value: 120, total: 150, label: "Protein eaten", gradient: LinearGradient.proteinGradient)
        MacroRing(value: 180, total: 200, label: "Carbs eaten", gradient: LinearGradient.carbsGradient)
        MacroRing(value: 45, total: 65, label: "Fat eaten", gradient: LinearGradient.fatsGradient)
    }
    .padding()
}

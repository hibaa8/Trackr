//
//  ExactDashboardView.swift
//  AITrainer
//
//  Exact replica of AI Trainer homepage design
//

import SwiftUI

struct ExactDashboardView: View {
    @State private var selectedDate = Date()
    @State private var streakDays = 15
    @State private var caloriesEaten = 1420
    @State private var caloriesGoal = 2500
    @State private var proteinEaten = 75
    @State private var carbsEaten = 138
    @State private var fatEaten = 35
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("AI Trainer")
                            .font(.system(size: 20, weight: .semibold))
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("🔥")
                                .font(.system(size: 18))
                            Text("\(streakDays)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    
                    Divider()
                    
                    // Week Calendar
                    WeekCalendarScrollView(selectedDate: $selectedDate)
                        .padding(.vertical, 16)
                    
                    Divider()
                    
                    // Large Calorie Circle
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                            .frame(width: 240, height: 240)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(caloriesEaten) / CGFloat(caloriesGoal))
                            .stroke(Color.black, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .frame(width: 240, height: 240)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 4) {
                            Text("\(caloriesEaten)")
                                .font(.system(size: 56, weight: .bold))
                            
                            Text("/\(caloriesGoal)")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                            
                            Text("Calories eaten")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 32)
                    
                    Divider()
                    
                    // Macro Circles
                    HStack(spacing: 40) {
                        MacroCircle(
                            value: proteinEaten,
                            label: "Protein eaten",
                            color: .red,
                            total: 150
                        )
                        
                        MacroCircle(
                            value: carbsEaten,
                            label: "Carbs eaten",
                            color: .orange,
                            total: 250
                        )
                        
                        MacroCircle(
                            value: fatEaten,
                            label: "Fat eaten",
                            color: .blue,
                            total: 70
                        )
                    }
                    .padding(.vertical, 32)
                    
                    Divider()
                    
                    // Recently uploaded
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recently uploaded")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        
                        RecentFoodItem(
                            name: "Grilled Salmon",
                            calories: 550,
                            protein: 36,
                            carbs: 40,
                            fat: 28,
                            time: "12:37pm"
                        )
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Explore
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Explore")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.top, 32)
                        
                        VStack(spacing: 16) {
                            HStack(spacing: 16) {
                                ModernExploreCard(
                                    icon: "📍",
                                    iconColor: Color.blue,
                                    title: "Gym Classes",
                                    subtitle: "Find local sessions"
                                )
                                
                                ModernExploreCard(
                                    icon: "💵",
                                    iconColor: Color.green,
                                    title: "Food Deals",
                                    subtitle: "Save on healthy meals"
                                )
                            }
                            
                            HStack(spacing: 16) {
                                ModernExploreCard(
                                    icon: "▶️",
                                    iconColor: Color.purple,
                                    title: "Workout Videos",
                                    subtitle: "Guided exercises"
                                )
                                
                                ModernExploreCard(
                                    icon: "👥",
                                    iconColor: Color.orange,
                                    title: "Community",
                                    subtitle: "Connect with others"
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 120)
                }
            }
            
            // Floating Add Button
            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 100)
        }
        .background(Color.white)
    }
}

// MARK: - Week Calendar

private struct WeekCalendarScrollView: View {
    @Binding var selectedDate: Date
    private let calendar = Calendar.current
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(weekDates, id: \.self) { date in
                    DayButton(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        action: { selectedDate = date }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var weekDates: [Date] {
        let today = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }
}

private struct DayButton: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(dayName)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                Text("\(dayNumber)")
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .black)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.blue : Color.clear)
                    .clipShape(Circle())
            }
        }
    }
    
    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var dayNumber: Int {
        calendar.component(.day, from: date)
    }
}

// MARK: - Macro Circle

private struct MacroCircle: View {
    let value: Int
    let label: String
    let color: Color
    let total: Int
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: CGFloat(value) / CGFloat(total))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(value)")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("g")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Recent Food Item

private struct RecentFoodItem: View {
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let time: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Food image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.96, green: 0.91, blue: 0.76))
                .frame(width: 80, height: 80)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: 18, weight: .semibold))
                
                HStack(spacing: 4) {
                    Text("🔥")
                        .font(.system(size: 14))
                    Text("\(calories) Calories")
                        .font(.system(size: 16, weight: .semibold))
                }
                
                HStack(spacing: 12) {
                    SimpleMacroTag(emoji: "🥩", value: "\(protein)g")
                    SimpleMacroTag(emoji: "🍞", value: "\(carbs)g")
                    SimpleMacroTag(emoji: "🥑", value: "\(fat)g")
                }
                
                Text(time)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

private struct SimpleMacroTag: View {
    let emoji: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Explore Card

#Preview {
    ExactDashboardView()
}

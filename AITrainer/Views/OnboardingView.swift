import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var currentStep = 0
    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var goalWeight = ""
    @State private var selectedActivity = ActivityLevel.moderate
    @State private var selectedDiet = DietPreference.omnivore
    @State private var selectedWorkout = WorkoutPreference.mixed
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Modern progress indicator with gradient
                HStack(spacing: 8) {
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(
                                index <= currentStep ?
                                LinearGradient.fitnessGradient :
                                LinearGradient(
                                    colors: [Color.textTertiary.opacity(0.3), Color.textTertiary.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 6)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentStep)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Modern header with better typography
                        VStack(spacing: 12) {
                            Text(stepTitle)
                                .font(.displayMedium)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.center)

                            Text(stepDescription)
                                .font(.bodyLarge)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .padding(.top, 24)
                        .padding(.horizontal, 24)

                        // Modern content in cards
                        stepContent
                            .padding(.horizontal, 24)
                    }
                }
                
                // Modern navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        ModernSecondaryButton(title: "Back") {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentStep -= 1
                            }
                        }
                    }

                    ModernPrimaryButton(title: currentStep == 3 ? "Complete Setup" : "Continue") {
                        handleNext()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationBarHidden(true)
        }
    }
    
    var stepTitle: String {
        switch currentStep {
        case 0: return "Personal Info"
        case 1: return "Current & Goal Weight"
        case 2: return "Activity & Diet"
        case 3: return "Workout Preference"
        default: return ""
        }
    }
    
    var stepDescription: String {
        switch currentStep {
        case 0: return "Tell us about yourself"
        case 1: return "Where are you and where do you want to be?"
        case 2: return "Help us personalize your plan"
        case 3: return "What type of exercise do you prefer?"
        default: return ""
        }
    }
    
    @ViewBuilder
    var stepContent: some View {
        switch currentStep {
        case 0:
            VStack(spacing: 20) {
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Age")
                            .font(.captionLarge)
                            .foregroundColor(.textSecondary)

                        TextField("Enter your age", text: $age)
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .background(Color.backgroundGradientStart)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.textTertiary.opacity(0.2), lineWidth: 1)
                            )
                            .keyboardType(.numberPad)
                    }
                    .padding(24)
                }

                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Height (inches)")
                            .font(.captionLarge)
                            .foregroundColor(.textSecondary)

                        TextField("e.g., 68", text: $height)
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .background(Color.backgroundGradientStart)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.textTertiary.opacity(0.2), lineWidth: 1)
                            )
                            .keyboardType(.decimalPad)
                    }
                    .padding(24)
                }
            }
            
        case 1:
            VStack(spacing: 20) {
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Current Weight (lbs)")
                            .font(.captionLarge)
                            .foregroundColor(.textSecondary)

                        TextField("e.g., 180", text: $weight)
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .background(Color.backgroundGradientStart)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.textTertiary.opacity(0.2), lineWidth: 1)
                            )
                            .keyboardType(.decimalPad)
                    }
                    .padding(24)
                }

                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Goal Weight (lbs)")
                            .font(.captionLarge)
                            .foregroundColor(.textSecondary)

                        TextField("e.g., 160", text: $goalWeight)
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .background(Color.backgroundGradientStart)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.textTertiary.opacity(0.2), lineWidth: 1)
                            )
                            .keyboardType(.decimalPad)
                    }
                    .padding(24)
                }
            }
            
        case 2:
            VStack(spacing: 32) {
                // Activity Level Section
                ModernCard {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Activity Level")
                            .font(.headlineMedium)
                            .foregroundColor(.textPrimary)

                        VStack(spacing: 12) {
                            ForEach(ActivityLevel.allCases, id: \.self) { level in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedActivity = level
                                    }
                                }) {
                                    HStack(spacing: 16) {
                                        Text(level.rawValue)
                                            .font(.bodyLarge)
                                            .foregroundColor(.textPrimary)

                                        Spacer()

                                        if selectedActivity == level {
                                            ZStack {
                                                Circle()
                                                    .fill(LinearGradient.fitnessGradient)
                                                    .frame(width: 24, height: 24)

                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        } else {
                                            Circle()
                                                .stroke(Color.textTertiary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                                    .background(
                                        selectedActivity == level ?
                                        Color.fitnessGradientStart.opacity(0.1) :
                                        Color.backgroundGradientStart
                                    )
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                selectedActivity == level ?
                                                Color.fitnessGradientStart.opacity(0.3) :
                                                Color.textTertiary.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(24)
                }

                // Diet Preference Section
                ModernCard {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Diet Preference")
                            .font(.headlineMedium)
                            .foregroundColor(.textPrimary)

                        VStack(spacing: 12) {
                            ForEach(DietPreference.allCases, id: \.self) { diet in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedDiet = diet
                                    }
                                }) {
                                    HStack(spacing: 16) {
                                        Text(diet.rawValue)
                                            .font(.bodyLarge)
                                            .foregroundColor(.textPrimary)

                                        Spacer()

                                        if selectedDiet == diet {
                                            ZStack {
                                                Circle()
                                                    .fill(LinearGradient.fitnessGradient)
                                                    .frame(width: 24, height: 24)

                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        } else {
                                            Circle()
                                                .stroke(Color.textTertiary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                                    .background(
                                        selectedDiet == diet ?
                                        Color.fitnessGradientStart.opacity(0.1) :
                                        Color.backgroundGradientStart
                                    )
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                selectedDiet == diet ?
                                                Color.fitnessGradientStart.opacity(0.3) :
                                                Color.textTertiary.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(24)
                }
            }
            
        case 3:
            ModernCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Workout Preference")
                        .font(.headlineMedium)
                        .foregroundColor(.textPrimary)

                    VStack(spacing: 12) {
                        ForEach(WorkoutPreference.allCases, id: \.self) { workout in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedWorkout = workout
                                }
                            }) {
                                HStack(spacing: 16) {
                                    Text(workout.rawValue)
                                        .font(.bodyLarge)
                                        .foregroundColor(.textPrimary)
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    if selectedWorkout == workout {
                                        ZStack {
                                            Circle()
                                                .fill(LinearGradient.fitnessGradient)
                                                .frame(width: 24, height: 24)

                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    } else {
                                        Circle()
                                            .stroke(Color.textTertiary.opacity(0.3), lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 20)
                                .background(
                                    selectedWorkout == workout ?
                                    Color.fitnessGradientStart.opacity(0.1) :
                                    Color.backgroundGradientStart
                                )
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            selectedWorkout == workout ?
                                            Color.fitnessGradientStart.opacity(0.3) :
                                            Color.textTertiary.opacity(0.2),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(24)
            }
            
        default:
            EmptyView()
        }
    }
    
    func handleNext() {
        if currentStep < 3 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentStep += 1
            }
        } else {
            completeOnboarding()
        }
    }
    
    func completeOnboarding() {
        let weightVal = Double(weight) ?? 0
        let ageVal = Double(age) ?? 0
        let heightVal = Double(height) ?? 0
        let goalWeightVal = Double(goalWeight) ?? 0
        
        // Calculate BMR using Mifflin-St Jeor
        let bmr = 10 * (weightVal * 0.453592) + 6.25 * (heightVal * 2.54) - 5 * ageVal + 5
        let tdee = bmr * selectedActivity.multiplier
        let deficit = weightVal > goalWeightVal ? 500.0 : 0.0
        let calorieTarget = Int(tdee - deficit)
        
        let userData = UserData(
            displayName: "",
            age: age,
            height: height,
            weight: weight,
            goalWeight: goalWeight,
            activityLevel: selectedActivity.rawValue,
            dietPreference: selectedDiet.rawValue,
            workoutPreference: selectedWorkout.rawValue,
            calorieTarget: calorieTarget
        )
        
        appState.completeOnboarding(with: userData)
        authManager.completeOnboarding()
    }
}

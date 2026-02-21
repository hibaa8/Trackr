//
//  ProfileEditView.swift
//  AITrainer
//
//  Comprehensive profile editing with photo picker
//

import SwiftUI
import PhotosUI
import Combine

struct ProfileEditView: View {
    let userId: Int
    let profile: ProfileResponse?
    var onSaved: ((ProfileResponse) -> Void)?

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var backendConnector: FrontendBackendConnector
    @EnvironmentObject private var authManager: AuthenticationManager
    @StateObject private var viewModel = ProfileEditViewModel()

    @State private var showImagePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var useImperialUnits = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header with units toggle
                        headerWithUnitsToggle
                            .padding(.top, 60)
                            .padding(.bottom, 32)

                        // Profile photo section
                        profilePhotoSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)

                        // Simplified core fields
                        coreFieldsSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)

                        // Preferences section
                        preferencesSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)

                        // Progress indicator
                        progressIndicator
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)

                        // Save button
                        saveButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 60)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Load profile data when available; fallback to appState.
                if let profile {
                    viewModel.loadProfile(user: profile.user, preferences: profile.preferences)
                } else if let cached = backendConnector.profile {
                    viewModel.loadProfile(user: cached.user, preferences: cached.preferences)
                } else {
                    backendConnector.loadProfile(userId: userId) { result in
                        if case .success(let response) = result {
                            viewModel.loadProfile(user: response.user, preferences: response.preferences)
                        }
                    }
                }

                if viewModel.email.isEmpty, let email = authManager.currentUser {
                    viewModel.email = email
                } else if viewModel.email.isEmpty,
                          let stored = UserDefaults.standard.string(forKey: "currentUserEmail") {
                    viewModel.email = stored
                }

                if viewModel.name.isEmpty, let userData = appState.userData {
                    let user = User(
                        email: viewModel.email.isEmpty ? "john@example.com" : viewModel.email,
                        name: userData.displayName.isEmpty ? "John Doe" : userData.displayName,
                        age: Int(userData.age) ?? 25,
                        heightInches: Double(userData.height) ?? 70.0,
                        weightPounds: Double(userData.weight) ?? 180.0,
                        goalWeightPounds: Double(userData.goalWeight) ?? 175.0,
                        activityLevel: ActivityLevel(rawValue: userData.activityLevel) ?? .moderate,
                        fitnessGoal: FitnessGoal.maintain,
                        dailyCalorieTarget: userData.calorieTarget
                    )
                    viewModel.loadUserData(user)
                }
            }
            .photosPicker(isPresented: $showImagePicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, newPhoto in
                if let newPhoto = newPhoto {
                    viewModel.handlePhotoSelection(newPhoto)
                }
            }
        }
    }

    // MARK: - Header with Units Toggle

    private var headerWithUnitsToggle: some View {
        VStack(spacing: 24) {
            // Main title section
            VStack(spacing: 8) {
                Text("Complete Your Profile")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Help us personalize your fitness journey")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            // Balanced units toggle without text
            HStack {
                Spacer()

                HStack(spacing: 12) {
                    // Metric button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            useImperialUnits = false
                        }
                    }) {
                        Text("Metric")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(useImperialUnits ? .white.opacity(0.6) : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(useImperialUnits ? Color.clear : Color.blue)
                            )
                    }

                    // Imperial button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            useImperialUnits = true
                        }
                    }) {
                        Text("Imperial")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(useImperialUnits ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(useImperialUnits ? Color.blue : Color.clear)
                            )
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                )

                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Profile Photo Section

    private var profilePhotoSection: some View {
        VStack(spacing: 20) {
            Text("Profile Photo")
                .font(.headlineLarge)
                .foregroundColor(.white)

            Button(action: {
                showImagePicker = true
            }) {
                ZStack {
                    // Outer glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.blue.opacity(0.4),
                                    Color.blue.opacity(0.2)
                                ],
                                center: .center,
                                startRadius: 40,
                                endRadius: 80
                            )
                        )
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)

                    // Main photo container
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.9),
                                    Color.blue.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )

                    // Photo or placeholder
                    if let profileImage = viewModel.profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)

                            Text("Add Photo")
                                .font(.captionMedium)
                                .foregroundColor(.white)
                        }
                    }

                    // Edit indicator
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        )
                        .overlay(
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 40, y: 40)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Basic Information")

            ModernCard {
                VStack(spacing: 20) {
                    ModernTextField(
                        title: "Full Name",
                        text: $viewModel.name,
                        icon: "person.fill",
                        placeholder: "Enter your name"
                    )

                    ModernTextField(
                        title: "Email",
                        text: $viewModel.email,
                        icon: "envelope.fill",
                        placeholder: "Enter your email"
                    )

                    ModernDateField(
                        title: "Birthday",
                        date: $viewModel.birthdate,
                        icon: "calendar",
                        placeholder: "Select your birthday"
                    )
                }
                .padding(24)
            }
        }
    }

    // MARK: - Physical Stats Section

    private func physicalStatsSection(useImperial: Bool) -> some View {
        VStack(spacing: 20) {
            HStack {
                sectionHeader("Physical Stats")
                Spacer()
                Toggle(useImperial ? "Imperial" : "Metric", isOn: $useImperialUnits)
                    .toggleStyle(SwitchToggleStyle())
            }

            ModernCard {
                VStack(spacing: 20) {
                    if useImperial {
                        ModernMeasurementField(
                            title: "Height",
                            value: $viewModel.heightInches,
                            icon: "ruler.fill",
                            unit: "inches",
                            placeholder: "Enter height"
                        )

                        ModernInteractiveWheelField(
                            title: "Current Weight",
                            value: $viewModel.weightPounds,
                            icon: "scalemass.fill",
                            unit: "lbs",
                            range: 80...500,
                            step: 1
                        )

                        ModernInteractiveWheelField(
                            title: "Goal Weight",
                            value: $viewModel.goalWeightPounds,
                            icon: "target",
                            unit: "lbs",
                            range: 80...500,
                            step: 1
                        )
                    } else {
                        ModernMeasurementField(
                            title: "Height",
                            value: Binding(
                                get: { viewModel.heightInches.map { $0 * 2.54 } },
                                set: { viewModel.heightInches = $0.map { $0 / 2.54 } }
                            ),
                            icon: "ruler.fill",
                            unit: "cm",
                            placeholder: "Enter height"
                        )

                        ModernInteractiveWheelField(
                            title: "Current Weight",
                            value: Binding(
                                get: { viewModel.weightPounds.map { $0 / 2.20462 } },
                                set: { viewModel.weightPounds = $0.map { $0 * 2.20462 } }
                            ),
                            icon: "scalemass.fill",
                            unit: "kg",
                            range: 30...200,
                            step: 0.1
                        )

                        ModernInteractiveWheelField(
                            title: "Goal Weight",
                            value: Binding(
                                get: { viewModel.goalWeightPounds.map { $0 / 2.20462 } },
                                set: { viewModel.goalWeightPounds = $0.map { $0 * 2.20462 } }
                            ),
                            icon: "target",
                            unit: "kg",
                            range: 30...200,
                            step: 0.1
                        )
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: - Core Fields Section

    private var coreFieldsSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                // Name field with validation
                ModernTextField(
                    title: "Full Name",
                    text: $viewModel.name,
                    icon: "person.fill",
                    placeholder: "Enter your name",
                    validation: viewModel.validateName()
                )

                // Age field
                ModernNumberField(
                    title: "Age",
                    value: $viewModel.age,
                    icon: "calendar",
                    placeholder: "Enter your age"
                )
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )

                // Goal selector with motivation
                ModernGoalField(
                    title: "Primary Goal",
                    selection: $viewModel.primaryGoal,
                    icon: "target"
                )
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }

            VStack(spacing: 20) {
                // Height field
                DarkMeasurementField(
                    title: "Height",
                    value: useImperialUnits ?
                        Binding(
                            get: { viewModel.heightInches },
                            set: { viewModel.heightInches = $0 }
                        ) :
                        Binding(
                            get: { viewModel.heightInches.map { $0 * 2.54 } },
                            set: { viewModel.heightInches = $0.map { $0 / 2.54 } }
                        ),
                    icon: "ruler.fill",
                    unit: useImperialUnits ? "inches" : "cm",
                    explanation: "Height is used for BMI and calorie calculations"
                )

                // Current weight with dark styling
                DarkWeightField(
                    title: "Current Weight",
                    value: useImperialUnits ? $viewModel.weightPounds : Binding(
                        get: { viewModel.weightPounds.map { $0 / 2.20462 } },
                        set: { viewModel.weightPounds = $0.map { $0 * 2.20462 } }
                    ),
                    icon: "scalemass.fill",
                    unit: useImperialUnits ? "lbs" : "kg",
                    explanation: "We use this to calculate your personalized calorie targets"
                )

                // Target weight with dark styling
                DarkWeightField(
                    title: "Target Weight",
                    value: useImperialUnits ? $viewModel.goalWeightPounds : Binding(
                        get: { viewModel.goalWeightPounds.map { $0 / 2.20462 } },
                        set: { viewModel.goalWeightPounds = $0.map { $0 * 2.20462 } }
                    ),
                    icon: "flag.fill",
                    unit: useImperialUnits ? "lbs" : "kg",
                    explanation: "Your target helps us create the perfect plan"
                )

                // Gender field
                ModernGenderField(
                    title: "Gender",
                    selection: $viewModel.gender,
                    icon: "person.2.fill"
                )
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )

            }
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                // Activity Level
                ModernActivityLevelField(
                    title: "Activity Level",
                    selection: $viewModel.activityLevel,
                    icon: "figure.walk"
                )
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )

                // Dietary Preferences
                ModernTextField(
                    title: "Dietary Preferences",
                    text: $viewModel.dietaryPreferences,
                    icon: "leaf.fill",
                    placeholder: "e.g., Vegetarian, Gluten-free, No allergies"
                )
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        VStack(spacing: 16) {
            // Enhanced header with icon
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)

                Text("Profile Completion")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                // Animated percentage with pulsing effect
                Text("\(viewModel.completionPercentage)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .scaleEffect(viewModel.completionPercentage == 100 ? 1.1 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: viewModel.completionPercentage)
            }

            // Enhanced progress bar with glow effect
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 12)

                    // Progress fill with animated glow
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, geometry.size.width * (Double(viewModel.completionPercentage) / 100.0)), height: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.6), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .shadow(color: .blue.opacity(0.6), radius: viewModel.completionPercentage > 50 ? 4 : 0, x: 0, y: 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: viewModel.completionPercentage)
                }
            }
            .frame(height: 12)

            // Enhanced status message
            Group {
                if viewModel.completionPercentage < 100 {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)

                        Text("Complete your profile for personalized recommendations!")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .transition(.opacity.combined(with: .scale))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                            .scaleEffect(1.2)

                        Text("Profile complete! You're all set!")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.green)

                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.completionPercentage)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: viewModel.completionPercentage == 100 ?
                                    [Color.green.opacity(0.5), Color.blue.opacity(0.3)] :
                                    [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Goals & Preferences")

            ModernCard {
                VStack(spacing: 20) {
                    ModernPickerField(
                        title: "Activity Level",
                        selection: $viewModel.activityLevel,
                        options: ActivityLevel.allCases,
                        icon: "figure.walk"
                    )

                    ModernPickerField(
                        title: "Fitness Goal",
                        selection: $viewModel.fitnessGoal,
                        options: FitnessGoal.allCases,
                        icon: "target"
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)

                            Text("Daily Calorie Target")
                                .font(.bodyMedium)
                                .foregroundColor(.white)
                        }

                        ModernWheelIntField(
                            value: $viewModel.dailyCalorieTarget,
                            range: 1000...5000,
                            unit: "kcal",
                            step: 25
                        )
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: {
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            let payload = viewModel.buildUpdatePayload(userId: userId)
            backendConnector.updateProfile(payload: payload) { result in
                switch result {
                case .success(let response):
                    viewModel.saveChanges()
                    onSaved?(response)

                    // Success haptic
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)

                    dismiss()
                case .failure(let error):
                    print("Failed to update profile: \(error)")

                    // Error haptic
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                }
            }
        }) {
            HStack(spacing: 12) {
                if viewModel.hasChanges {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Text(viewModel.hasChanges ? "Save Changes" : "No Changes to Save")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        viewModel.hasChanges ?
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: viewModel.hasChanges ?
                                [Color.white.opacity(0.3), Color.white.opacity(0.1)] :
                                [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: viewModel.hasChanges ? Color.blue.opacity(0.3) : Color.clear,
                radius: 8,
                x: 0,
                y: 4
            )
            .scaleEffect(viewModel.hasChanges ? 1.0 : 0.98)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.hasChanges)
        }
        .disabled(!viewModel.hasChanges)
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headlineLarge)
                .foregroundColor(.white)

            Spacer()
        }
    }
}

// MARK: - Profile Edit ViewModel

// MARK: - Supporting Enums

enum AgeRange: String, CaseIterable {
    case teens = "16-19"
    case twenties = "20-29"
    case thirties = "30-39"
    case forties = "40-49"
    case fifties = "50-59"
    case sixties = "60+"
}

enum PrimaryGoal: String, CaseIterable {
    case loseWeight = "Lose Weight"
    case gainMuscle = "Gain Muscle"
    case maintainHealth = "Stay Healthy"
    case improvePerformance = "Get Stronger"
}

enum Gender: String, CaseIterable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
    case preferNotToSay = "Prefer not to say"
}

enum ValidationResult: Equatable {
    case valid
    case invalid(String)
    case empty
}

class ProfileEditViewModel: ObservableObject {
    @Published var name = "" { didSet { markChanged() } }
    @Published var age: Int? = nil { didSet { markChanged() } }
    @Published var gender: Gender? = nil { didSet { markChanged() } }
    @Published var heightInches: Double? = nil { didSet { markChanged() } }
    @Published var weightPounds: Double? = nil { didSet { markChanged() } }
    @Published var goalWeightPounds: Double? = nil { didSet { markChanged() } }
    @Published var activityLevel: ActivityLevel = .moderate { didSet { markChanged() } }
    @Published var fitnessGoal: FitnessGoal = .maintain { didSet { markChanged() } }
    @Published var dietaryPreferences: String = "" { didSet { markChanged() } }
    @Published var profileImage: UIImage? = nil

    // Legacy fields for compatibility
    @Published var ageRange: AgeRange = .twenties { didSet { markChanged() } }
    @Published var primaryGoal: PrimaryGoal = .maintainHealth {
        didSet {
            if !isLoadingData {
                fitnessGoal = mapPrimaryGoalToFitnessGoal(primaryGoal)
            }
            markChanged()
        }
    }
    @Published var email = ""
    @Published var birthdate: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @Published var dailyCalorieTarget: Int = 2000

    @Published var hasChanges = false
    private var isLoadingData = false
    private var imageChanged = false

    private var originalUser: User?

    // MARK: - Validation Methods

    func validateName() -> ValidationResult {
        if name.isEmpty {
            return .empty
        }
        if name.count < 2 {
            return .invalid("Name must be at least 2 characters")
        }
        if name.count > 50 {
            return .invalid("Name is too long")
        }
        return .valid
    }

    func validateWeight(_ weight: Double?) -> ValidationResult {
        guard let weight = weight else {
            return .empty
        }
        if weight < 30 || weight > 500 {
            return .invalid("Please enter a realistic weight")
        }
        return .valid
    }

    // MARK: - Completion Percentage

    var completionPercentage: Int {
        var completed = 0
        let totalFields = 7

        if validateName() == .valid { completed += 1 }
        if age != nil && age! > 0 { completed += 1 }
        if gender != nil { completed += 1 }
        if heightInches != nil && heightInches! > 0 { completed += 1 }
        if weightPounds != nil && validateWeight(weightPounds) == .valid { completed += 1 }
        if goalWeightPounds != nil && validateWeight(goalWeightPounds) == .valid { completed += 1 }
        if !dietaryPreferences.isEmpty { completed += 1 }

        return Int((Double(completed) / Double(totalFields)) * 100)
    }

    func loadUserData(_ user: User?) {
        guard let user = user else { return }
        isLoadingData = true
        self.originalUser = user
        self.name = user.name
        self.email = user.email
        if let age = user.age {
            self.birthdate = Calendar.current.date(byAdding: .year, value: -age, to: Date()) ?? Date()
        }
        self.heightInches = user.heightInches
        self.weightPounds = user.weightPounds
        self.goalWeightPounds = user.goalWeightPounds
        self.activityLevel = user.activityLevel
        self.fitnessGoal = user.fitnessGoal
        self.dailyCalorieTarget = user.dailyCalorieTarget
        loadProfileImage()
        imageChanged = false
        hasChanges = false
        isLoadingData = false
    }

    func loadProfile(user: ProfileUserResponse?, preferences: ProfilePreferencesResponse?) {
        isLoadingData = true
        self.name = user?.name ?? ""
        self.age = user?.age_years
        self.gender = mapGender(user?.gender)
        self.email = ""
        if let age = user?.age_years {
            self.birthdate = Calendar.current.date(byAdding: .year, value: -age, to: Date()) ?? Date()
        }
        self.heightInches = user?.height_cm.map { $0 / 2.54 }
        self.weightPounds = user?.weight_kg.map { $0 * 2.20462 }
        self.goalWeightPounds = preferences?.target_weight_kg.map { $0 * 2.20462 }
        self.activityLevel = mapActivityLevel(preferences?.activity_level)
        self.fitnessGoal = mapFitnessGoal(preferences?.goal_type)
        self.primaryGoal = mapPrimaryGoal(preferences?.goal_type)
        self.dietaryPreferences = preferences?.dietary_preferences ?? ""
        self.dailyCalorieTarget = 2000
        loadProfileImage(base64: user?.profile_image_base64)
        imageChanged = false
        hasChanges = false
        isLoadingData = false
    }

    func handlePhotoSelection(_ photoItem: PhotosPickerItem) {
        Task {
            if let data = try? await photoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.profileImage = image
                    self.imageChanged = true
                    self.hasChanges = true
                }
            }
        }
    }

    private func loadProfileImage(base64: String? = nil) {
        if let base64, let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
            self.profileImage = image
            return
        }
        if let imageData = UserDefaults.standard.data(forKey: "profileImage"),
           let image = UIImage(data: imageData) {
            self.profileImage = image
        }
    }

    func saveChanges() {
        // Save profile image
        if let profileImage = profileImage,
           let imageData = profileImage.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(imageData, forKey: "profileImage")
        }

        // Update user data
        // This would typically update the user in your data store
        hasChanges = false
        imageChanged = false
    }

    func buildUpdatePayload(userId: Int) -> ProfileUpdateRequest {
        let heightCm = heightInches.map { $0 * 2.54 }
        let weightKg = weightPounds.map { $0 / 2.20462 }
        let goalWeightKg = goalWeightPounds.map { $0 / 2.20462 }
        let imageBase64: String?
        if imageChanged, let profileImage, let data = profileImage.jpegData(compressionQuality: 0.8) {
            imageBase64 = data.base64EncodedString()
        } else {
            imageBase64 = nil
        }

        return ProfileUpdateRequest(
            user_id: userId,
            name: name.isEmpty ? nil : name,
            birthdate: nil,
            height_cm: heightCm,
            weight_kg: weightKg,
            gender: gender?.rawValue.lowercased(),
            age_years: age,
            agent_id: nil,
            profile_image_base64: imageBase64,
            activity_level: activityLevel.rawValue,
            goal_type: backendGoalType(primaryGoal),
            target_weight_kg: goalWeightKg,
            dietary_preferences: dietaryPreferences.isEmpty ? nil : dietaryPreferences,
            workout_preferences: nil
        )
    }

    private func mapActivityLevel(_ value: String?) -> ActivityLevel {
        guard let value else { return .moderate }
        if let match = ActivityLevel.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }) {
            return match
        }
        return .moderate
    }

    private func mapFitnessGoal(_ value: String?) -> FitnessGoal {
        guard let value else { return .maintain }
        if let match = FitnessGoal.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }) {
            return match
        }
        return .maintain
    }

    private func mapPrimaryGoal(_ value: String?) -> PrimaryGoal {
        guard let value else { return .maintainHealth }
        switch value.lowercased() {
        case "lose":
            return .loseWeight
        case "gain":
            return .gainMuscle
        default:
            return .maintainHealth
        }
    }

    private func mapPrimaryGoalToFitnessGoal(_ goal: PrimaryGoal) -> FitnessGoal {
        switch goal {
        case .loseWeight:
            return .lose
        case .gainMuscle:
            return .gain
        case .maintainHealth, .improvePerformance:
            return .maintain
        }
    }

    private func backendGoalType(_ goal: PrimaryGoal) -> String {
        switch goal {
        case .loseWeight:
            return "lose"
        case .gainMuscle:
            return "gain"
        case .maintainHealth, .improvePerformance:
            return "maintain"
        }
    }

    private func mapGender(_ value: String?) -> Gender? {
        guard let value else { return nil }
        if let match = Gender.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }) {
            return match
        }
        return nil
    }

    private func markChanged() {
        guard !isLoadingData else { return }
        hasChanges = true
    }
}

// MARK: - Modern Text Field

struct ModernTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let placeholder: String
    var validation: ValidationResult = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)

                Spacer()

                // Validation indicator
                if case .valid = validation {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
            }

            TextField(placeholder, text: $text)
                .font(.bodyLarge)
                .foregroundColor(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )

            // Validation message
            if case .invalid(let message) = validation {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
            }
        }
    }

    private var borderColor: Color {
        switch validation {
        case .valid: return .green.opacity(0.5)
        case .invalid: return .red.opacity(0.5)
        case .empty: return .blue.opacity(0.3)
        }
    }
}

// MARK: - Modern Number Field

struct ModernNumberField: View {
    let title: String
    @Binding var value: Int?
    let icon: String
    let placeholder: String

    @State private var textValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                .foregroundColor(.white)
            }

            TextField(placeholder, text: $textValue)
                .font(.bodyLarge)
                .foregroundColor(.white)
                .keyboardType(.numberPad)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: textValue) { _, newValue in
                    value = Int(newValue)
                }
                .onChange(of: value) { _, newValue in
                    if let newValue {
                        textValue = String(newValue)
                    } else {
                        textValue = ""
                    }
                }
                .onAppear {
                    if let value = value {
                        textValue = String(value)
                    }
                }
        }
    }
}

// MARK: - Modern Measurement Field

struct ModernMeasurementField: View {
    let title: String
    @Binding var value: Double?
    let icon: String
    let unit: String
    let placeholder: String
    var useWheelPicker: Bool = false

    @State private var textValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                .foregroundColor(.white)
            }

            if useWheelPicker {
                let currentValue = value ?? 70.0
                let index = Int((currentValue * 10.0).rounded())
                let normalizedIndex = min(max(((index + 2) / 5) * 5, 300), 3000)
                HStack(spacing: 12) {
                    Picker("", selection: Binding(
                        get: { normalizedIndex },
                        set: { newValue in
                            value = Double(newValue) / 10.0
                        }
                    )) {
                        ForEach(300...3000, id: \.self) { raw in
                            if raw % 5 == 0 {
                                Text(String(format: "%.1f", Double(raw) / 10.0)).tag(raw)
                            }
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .clipped()

                    Text(unit)
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            } else {
                HStack {
                    TextField(placeholder, text: $textValue)
                        .font(.bodyLarge)
                        .foregroundColor(.black)
                        .keyboardType(.decimalPad)

                    Text(unit)
                        .font(.bodyMedium)
                        .foregroundColor(.black.opacity(0.6))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: textValue) { _, newValue in
                    value = Double(newValue)
                }
                .onAppear {
                    if let value = value {
                        textValue = String(format: "%.1f", value)
                    }
                }
            }
        }
    }
}

struct ModernWheelIntField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var step: Int = 1

    var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: $value) {
                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { item in
                    Text("\(item)").tag(item)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            .clipped()

            Text(unit)
                .font(.bodyMedium)
                .foregroundColor(.black.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Modern Picker Field

struct ModernPickerField<T: CaseIterable & RawRepresentable>: View where T.RawValue == String, T: Equatable {
    let title: String
    @Binding var selection: T
    let options: [T]
    let icon: String

    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)
            }

            Button(action: {
                showPicker = true
            }) {
                HStack {
                    Text(selection.rawValue)
                        .font(.bodyLarge)
                        .foregroundColor(.black)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.6))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showPicker) {
            PickerSheet(title: title, selection: $selection, options: options)
        }
    }
}

// MARK: - Picker Sheet

struct PickerSheet<T: CaseIterable & RawRepresentable>: View where T.RawValue == String, T: Equatable {
    let title: String
    @Binding var selection: T
    let options: [T]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List(options, id: \.rawValue) { option in
                Button(action: {
                    selection = option
                    dismiss()
                }) {
                    HStack {
                        Text(option.rawValue)
                            .foregroundColor(.white)

                        Spacer()

                        if selection == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .navigationTitle(title)
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

// MARK: - Modern Date Field

struct ModernDateField: View {
    let title: String
    @Binding var date: Date
    let icon: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)
            }

            DatePicker(placeholder, selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(.bodyLarge)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

// MARK: - Modern Interactive Wheel Field

struct ModernInteractiveWheelField: View {
    let title: String
    @Binding var value: Double?
    let icon: String
    let unit: String
    let range: ClosedRange<Double>
    let step: Double

    @State private var selectedIndex: Int = 0

    private var values: [Double] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
    }

    private var currentValue: Double {
        value ?? (range.lowerBound + range.upperBound) / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)
            }

            HStack(spacing: 12) {
                Picker("", selection: $selectedIndex) {
                    ForEach(values.indices, id: \.self) { index in
                        let val = values[index]
                        Text(String(format: step < 1 ? "%.1f" : "%.0f", val))
                            .foregroundColor(.white)
                            .tag(index)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .clipped()
                .onChange(of: selectedIndex) { _, newIndex in
                    if values.indices.contains(newIndex) {
                        value = values[newIndex]
                    }
                }

                Text(unit)
                    .font(.bodyMedium)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .onAppear {
            // Set initial selected index based on current value
            if let currentValue = value,
               let closestIndex = values.enumerated().min(by: { abs($0.element - currentValue) < abs($1.element - currentValue) })?.offset {
                selectedIndex = closestIndex
            } else {
                selectedIndex = values.count / 2
            }
        }
    }
}

// MARK: - Enhanced UI Components

struct ModernAgeRangeField: View {
    let title: String
    @Binding var selection: AgeRange
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)

                Spacer()

                Text("✨ Privacy friendly")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
            }

            Menu {
                ForEach(AgeRange.allCases, id: \.self) { range in
                    Button(range.rawValue) {
                        selection = range
                    }
                }
            } label: {
                HStack {
                    Text(selection.rawValue)
                        .font(.bodyLarge)
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

struct ModernGoalField: View {
    let title: String
    @Binding var selection: PrimaryGoal
    let icon: String

    private let goalDescriptions: [PrimaryGoal: String] = [
        .loseWeight: "Burn fat and reach your ideal weight",
        .gainMuscle: "Build strength and lean muscle mass",
        .maintainHealth: "Stay fit and feel great every day",
        .improvePerformance: "Push your limits and get stronger"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)
            }

            Menu {
                ForEach(PrimaryGoal.allCases, id: \.self) { goal in
                    Button(action: { selection = goal }) {
                        VStack(alignment: .leading) {
                            Text(goal.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                            Text(goalDescriptions[goal] ?? "")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selection.rawValue)
                            .font(.bodyLarge)
                            .foregroundColor(.white)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Text(goalDescriptions[selection] ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

struct SmartWeightField: View {
    let title: String
    @Binding var value: Double?
    let icon: String
    let unit: String
    let isImperial: Bool
    let explanation: String

    @State private var textValue = ""
    @State private var isEditing = false
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enhanced header with validation
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // Validation indicator
                if let value = value, value > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
                }
            }

            // Enhanced input field
            HStack(spacing: 12) {
                TextField(isImperial ? "150" : "70", text: $textValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isEditing = true
                        }
                        // Add haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }

                Text(unit)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isEditing ?
                            Color.blue.opacity(0.15) :
                            Color.white.opacity(0.08)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: isEditing ?
                                [Color.blue, Color.cyan] :
                                [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isEditing ? 2 : 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isEditing)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)

            // Explanation with icon
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.blue.opacity(0.8))

                Text(explanation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue.opacity(0.8))
            }

            // Enhanced smart suggestions
            if isEditing {
                VStack(spacing: 8) {
                    Text("Quick Select")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(getSuggestions(), id: \.self) { suggestion in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    textValue = String(format: isImperial ? "%.0f" : "%.1f", suggestion)
                                    value = suggestion
                                    isEditing = false
                                }

                                // Add haptic feedback
                                let selectionFeedback = UISelectionFeedbackGenerator()
                                selectionFeedback.selectionChanged()
                            }) {
                                VStack(spacing: 4) {
                                    Text(String(format: isImperial ? "%.0f" : "%.1f", suggestion))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)

                                    Text(unit)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.blue)
                                }
                                .frame(height: 44)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isEditing)
            }
        }
        .onTapGesture {
            if isEditing {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isEditing = false
                }
            }
        }
        .onChange(of: textValue) { _, newValue in
            value = Double(newValue)
        }
        .onAppear {
            if let value = value {
                textValue = String(format: isImperial ? "%.0f" : "%.1f", value)
            }
        }
    }

    private func getSuggestions() -> [Double] {
        if isImperial {
            return [120, 140, 160, 180, 200, 220] // pounds
        } else {
            return [50, 60, 70, 80, 90, 100] // kg
        }
    }
}

// MARK: - Dark Weight Field (Profile Completion Style)

struct DarkWeightField: View {
    let title: String
    @Binding var value: Double?
    let icon: String
    let unit: String
    let explanation: String

    @State private var textValue = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with validation
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // Validation indicator like Profile Completion
                if let value = value, value > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
                }
            }

            // Dark input field matching Profile Completion style
            HStack(spacing: 12) {
                TextField("0", text: $textValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)

                Text(unit)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            // Info explanation
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.blue.opacity(0.8))

                Text(explanation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue.opacity(0.8))
            }
        }
        .onChange(of: textValue) { _, newValue in
            value = Double(newValue)
        }
        .onChange(of: value) { _, newValue in
            if let newValue {
                textValue = String(format: "%.1f", newValue)
            } else {
                textValue = ""
            }
        }
        .onAppear {
            if let value = value {
                textValue = String(format: "%.1f", value)
            }
        }
    }
}

// MARK: - Dark Measurement Field (Height)

struct DarkMeasurementField: View {
    let title: String
    @Binding var value: Double?
    let icon: String
    let unit: String
    let explanation: String

    @State private var textValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with validation
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // Validation indicator
                if let value = value, value > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
                }
            }

            // Dark input field
            HStack(spacing: 12) {
                TextField("0", text: $textValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)

                Text(unit)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            // Info explanation
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.blue.opacity(0.8))

                Text(explanation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue.opacity(0.8))
            }
        }
        .onChange(of: textValue) { _, newValue in
            value = Double(newValue)
        }
        .onChange(of: value) { _, newValue in
            if let newValue {
                textValue = String(format: "%.1f", newValue)
            } else {
                textValue = ""
            }
        }
        .onAppear {
            if let value = value {
                textValue = String(format: "%.1f", value)
            }
        }
    }
}

// MARK: - Modern Gender Field

struct ModernGenderField: View {
    let title: String
    @Binding var selection: Gender?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)

                Spacer()

                if selection != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
            }

            Menu {
                ForEach(Gender.allCases, id: \.self) { gender in
                    Button(gender.rawValue) {
                        selection = gender
                    }
                }
            } label: {
                HStack {
                    Text(selection?.rawValue ?? "Select gender")
                        .font(.bodyLarge)
                        .foregroundColor(selection != nil ? .white : .white.opacity(0.6))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Modern Activity Level Field

struct ModernActivityLevelField: View {
    let title: String
    @Binding var selection: ActivityLevel
    let icon: String

    private let activityDescriptions: [ActivityLevel: String] = [
        .sedentary: "Desk job, little to no exercise",
        .light: "Light exercise 1-3 times per week",
        .moderate: "Moderate exercise 3-5 times per week",
        .very: "Heavy exercise 6-7 times per week",
        .extra: "Very heavy exercise, physical job"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            }

            Menu {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    Button(action: { selection = level }) {
                        VStack(alignment: .leading) {
                            Text(level.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                            Text(activityDescriptions[level] ?? "")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selection.rawValue)
                            .font(.bodyLarge)
                            .foregroundColor(.white)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Text(activityDescriptions[selection] ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

#Preview {
    ProfileEditView(userId: 1, profile: nil)
        .environmentObject(AppState())
        .environmentObject(FrontendBackendConnector.shared)
}
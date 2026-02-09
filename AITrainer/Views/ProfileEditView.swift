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
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ProfileEditViewModel()

    @State private var showImagePicker = false
    @State private var selectedPhoto: PhotosPickerItem?

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
                    VStack(spacing: 32) {
                        // Profile photo section
                        profilePhotoSection
                            .padding(.top, 20)

                        // Basic info section
                        basicInfoSection
                            .padding(.horizontal, 20)

                        // Physical stats section
                        physicalStatsSection
                            .padding(.horizontal, 20)

                        // Goals section
                        goalsSection
                            .padding(.horizontal, 20)

                        // Save button
                        saveButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
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
                // Load user data if available, otherwise use default values
                if let userData = appState.userData {
                    let user = User(
                        email: "john@example.com", // Default email
                        name: "John Doe", // Default name since UserData doesn't have name
                        age: Int(userData.age) ?? 25,
                        heightInches: Double(userData.height) ?? 70.0,
                        weightPounds: Double(userData.weight) ?? 180.0,
                        goalWeightPounds: Double(userData.goalWeight) ?? 175.0,
                        activityLevel: ActivityLevel(rawValue: userData.activityLevel) ?? .moderate,
                        fitnessGoal: FitnessGoal.maintain, // Default goal
                        dailyCalorieTarget: userData.calorieTarget
                    )
                    viewModel.loadUserData(user)
                } else {
                    // Load with completely default values
                    let defaultUser = User(
                        email: "john@example.com",
                        name: "John Doe",
                        age: 25,
                        heightInches: 70.0,
                        weightPounds: 180.0,
                        goalWeightPounds: 175.0,
                        activityLevel: .moderate,
                        fitnessGoal: .maintain,
                        dailyCalorieTarget: 2000
                    )
                    viewModel.loadUserData(defaultUser)
                }
            }
            .photosPicker(isPresented: $showImagePicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { newPhoto in
                if let newPhoto = newPhoto {
                    viewModel.handlePhotoSelection(newPhoto)
                }
            }
        }
    }

    // MARK: - Profile Photo Section

    private var profilePhotoSection: some View {
        VStack(spacing: 20) {
            Text("Profile Photo")
                .font(.headlineLarge)
                .foregroundColor(.textPrimary)

            Button(action: {
                showImagePicker = true
            }) {
                ZStack {
                    // Outer glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.fitnessGradientStart.opacity(0.4),
                                    Color.fitnessGradientEnd.opacity(0.2)
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
                                    Color.fitnessGradientStart.opacity(0.9),
                                    Color.fitnessGradientEnd.opacity(0.9)
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
                        .fill(Color.fitnessGradientStart)
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

                    ModernNumberField(
                        title: "Age",
                        value: $viewModel.age,
                        icon: "calendar",
                        placeholder: "Enter your age"
                    )
                }
                .padding(24)
            }
        }
    }

    // MARK: - Physical Stats Section

    private var physicalStatsSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Physical Stats")

            ModernCard {
                VStack(spacing: 20) {
                    ModernMeasurementField(
                        title: "Height",
                        value: $viewModel.heightInches,
                        icon: "ruler.fill",
                        unit: "inches",
                        placeholder: "Enter height"
                    )

                    ModernMeasurementField(
                        title: "Current Weight",
                        value: $viewModel.weightPounds,
                        icon: "scalemass.fill",
                        unit: "kg",
                        placeholder: "Enter weight"
                    )

                    ModernMeasurementField(
                        title: "Goal Weight",
                        value: $viewModel.goalWeightPounds,
                        icon: "target",
                        unit: "kg",
                        placeholder: "Enter goal weight"
                    )
                }
                .padding(24)
            }
        }
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
                                .foregroundColor(.fitnessGradientStart)

                            Text("Daily Calorie Target")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                        }

                        TextField("Enter calorie target", value: $viewModel.dailyCalorieTarget, format: .number)
                            .font(.bodyLarge)
                            .keyboardType(.numberPad)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.backgroundGradientStart)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        ModernPrimaryButton(title: "Save Changes") {
            viewModel.saveChanges()
            dismiss()
        }
        .disabled(!viewModel.hasChanges)
        .opacity(viewModel.hasChanges ? 1.0 : 0.6)
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headlineLarge)
                .foregroundColor(.textPrimary)

            Spacer()
        }
    }
}

// MARK: - Profile Edit ViewModel

class ProfileEditViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var age: Int? = nil
    @Published var heightInches: Double? = nil
    @Published var weightPounds: Double? = nil
    @Published var goalWeightPounds: Double? = nil
    @Published var activityLevel: ActivityLevel = .moderate
    @Published var fitnessGoal: FitnessGoal = .maintain
    @Published var dailyCalorieTarget: Int = 2000
    @Published var profileImage: UIImage? = nil

    @Published var hasChanges = false

    private var originalUser: User?

    func loadUserData(_ user: User?) {
        guard let user = user else { return }
        self.originalUser = user

        self.name = user.name
        self.email = user.email
        self.age = user.age
        self.heightInches = user.heightInches
        self.weightPounds = user.weightPounds
        self.goalWeightPounds = user.goalWeightPounds
        self.activityLevel = user.activityLevel
        self.fitnessGoal = user.fitnessGoal
        self.dailyCalorieTarget = user.dailyCalorieTarget

        // Load profile image if exists
        loadProfileImage()

        // Monitor for changes
        setupChangeDetection()
    }

    private func setupChangeDetection() {
        // This would typically observe all published properties
        // For simplicity, we'll set hasChanges to true when any field changes
    }

    func handlePhotoSelection(_ photoItem: PhotosPickerItem) {
        Task {
            if let data = try? await photoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.profileImage = image
                    self.hasChanges = true
                }
            }
        }
    }

    private func loadProfileImage() {
        // Load from UserDefaults or file system
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
    }
}

// MARK: - Modern Text Field

struct ModernTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.fitnessGradientStart)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
            }

            TextField(placeholder, text: $text)
                .font(.bodyLarge)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.backgroundGradientStart)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
                )
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
                    .foregroundColor(.fitnessGradientStart)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
            }

            TextField(placeholder, text: $textValue)
                .font(.bodyLarge)
                .keyboardType(.numberPad)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.backgroundGradientStart)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: textValue) { _, newValue in
                    value = Int(newValue)
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

    @State private var textValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.fitnessGradientStart)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
            }

            HStack {
                TextField(placeholder, text: $textValue)
                    .font(.bodyLarge)
                    .keyboardType(.decimalPad)

                Text(unit)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundGradientStart)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
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
                    .foregroundColor(.fitnessGradientStart)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
            }

            Button(action: {
                showPicker = true
            }) {
                HStack {
                    Text(selection.rawValue)
                        .font(.bodyLarge)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.backgroundGradientStart)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
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
                            .foregroundColor(.textPrimary)

                        Spacer()

                        if selection == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(.fitnessGradientStart)
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

#Preview {
    ProfileEditView()
        .environmentObject(AppState())
}
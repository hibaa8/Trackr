import SwiftUI
import PhotosUI
import UIKit

struct WireframeProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showSettings = false
    @State private var profileImageOffset: CGFloat = 0

    // Section edit states
    @State private var showIdentityEdit = false
    @State private var showPhysicalStatsEdit = false
    @State private var showGoalsEdit = false
    @State private var showPreferencesEdit = false

    var body: some View {
        NavigationView {
            ZStack {
                // Stunning background gradient
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
                        // Enhanced profile header
                        modernProfileHeader
                            .padding(.top, 20)
                            .padding(.horizontal, 20)

                        // Physical stats
                        physicalStatsSection
                            .padding(.horizontal, 20)

                        // Goals section
                        goalsSection
                            .padding(.horizontal, 20)

                        // Preferences section
                        preferencesSection
                            .padding(.horizontal, 20)

                        // Settings section
                        settingsSection
                            .padding(.horizontal, 20)

                        // Enhanced logout section
                        modernLogoutSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showIdentityEdit) {
                ProfileIdentityEditSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showPhysicalStatsEdit) {
                PhysicalStatsEditSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showGoalsEdit) {
                GoalsEditSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showPreferencesEdit) {
                PreferencesEditSheet()
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Modern Profile Header

    var modernProfileHeader: some View {
        VStack(spacing: 24) {
            // Modern profile picture with stunning effects
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

                // Main avatar container
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

                // Profile image or placeholder
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else {
                    Text("👤")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .scaleEffect(1.0 + sin(profileImageOffset) * 0.05)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                                profileImageOffset = .pi * 2
                            }
                        }
                }

                // Online status indicator
                Circle()
                    .fill(Color.green)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .offset(x: 40, y: 40)
            }

            // User info with modern typography
            VStack(spacing: 8) {
                Text(displayNameText)
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)

                Text(profileCompletionText)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }
        }
        .onTapGesture {
            showIdentityEdit = true
        }
    }

    // MARK: - Physical Stats Section

    var physicalStatsSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Physical Stats")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button("Edit") {
                    showPhysicalStatsEdit = true
                }
                .font(.bodyMedium)
                .foregroundColor(.fitnessGradientStart)
            }

            ModernCard {
                VStack(spacing: 0) {
                    ModernProfileRow(
                        icon: "person.fill",
                        title: "Age",
                        value: valueOrSetup(userData.age, suffix: "years"),
                        color: .blue
                    ) {
                        showPhysicalStatsEdit = true
                    }

                    ModernDivider()

                    ModernProfileRow(
                        icon: "ruler.fill",
                        title: "Height",
                        value: valueOrSetup(userData.height, suffix: "in"),
                        color: .green
                    ) {
                        showPhysicalStatsEdit = true
                    }

                    ModernDivider()

                    ModernProfileRow(
                        icon: "scalemass.fill",
                        title: "Current Weight",
                        value: valueOrSetup(userData.weight, suffix: "lbs"),
                        color: .purple
                    ) {
                        showPhysicalStatsEdit = true
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Goals Section

    var goalsSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Goals")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button("Edit") {
                    showGoalsEdit = true
                }
                .font(.bodyMedium)
                .foregroundColor(.fitnessGradientStart)
            }

            ModernCard {
                VStack(spacing: 0) {
                    ModernProfileRow(
                        icon: "target",
                        title: "Goal Weight",
                        value: valueOrSetup(userData.goalWeight, suffix: "lbs"),
                        color: .orange
                    ) {
                        showGoalsEdit = true
                    }

                    ModernDivider()

                    ModernProfileRow(
                        icon: "flame.fill",
                        title: "Daily Calorie Target",
                        value: "\(userData.calorieTarget) cal",
                        color: .red
                    ) {
                        showGoalsEdit = true
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Preferences Section

    var preferencesSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Preferences")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button("Edit") {
                    showPreferencesEdit = true
                }
                .font(.bodyMedium)
                .foregroundColor(.fitnessGradientStart)
            }

            ModernCard {
                VStack(spacing: 0) {
                    ModernProfileRow(
                        icon: "figure.walk",
                        title: "Activity Level",
                        value: valueOrSetup(userData.activityLevel),
                        color: .blue
                    ) {
                        showPreferencesEdit = true
                    }

                    ModernDivider()

                    ModernProfileRow(
                        icon: "fork.knife",
                        title: "Diet Preference",
                        value: valueOrSetup(userData.dietPreference),
                        color: .green
                    ) {
                        showPreferencesEdit = true
                    }

                    ModernDivider()

                    ModernProfileRow(
                        icon: "dumbbell.fill",
                        title: "Workout Preference",
                        value: valueOrSetup(userData.workoutPreference),
                        color: .purple
                    ) {
                        showPreferencesEdit = true
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Quick Settings Section

    var settingsSection: some View {
        VStack(spacing: 20) {
            ModernCard {
                Button(action: { showSettings = true }) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 44, height: 44)

                            Image(systemName: "gear")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Settings & More")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)

                            Text("Notifications, integrations, help & support")
                                .font(.captionLarge)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Modern Logout Section

    var modernLogoutSection: some View {
        Button(action: { authManager.signOut() }) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.right.square.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.red)

                Text("Sign Out")
                    .font(.bodyLarge)
                    .foregroundColor(.red)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .background(
                ModernCard {
                    Rectangle()
                        .fill(Color.clear)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var userData: UserData {
        appState.userData ?? UserData(
            displayName: "",
            age: "",
            height: "",
            weight: "",
            goalWeight: "",
            activityLevel: "",
            dietPreference: "",
            workoutPreference: "",
            calorieTarget: 2000
        )
    }

    private var profileCompletionText: String {
        let fields = [
            userData.displayName,
            userData.age,
            userData.height,
            userData.weight,
            userData.goalWeight,
            userData.activityLevel,
            userData.dietPreference,
            userData.workoutPreference
        ]
        let completed = fields.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        if completed == fields.count {
            return "All set — profile complete"
        }
        return "Complete your profile to personalize your plan"
    }

    private func valueOrSetup(_ value: String, suffix: String? = nil) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Set up"
        }
        if let suffix = suffix {
            return "\(trimmed) \(suffix)"
        }
        return trimmed
    }

    private var displayNameText: String {
        let trimmed = userData.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Set your name" : trimmed
    }

    private var profileImage: UIImage? {
        guard let data = UserDefaults.standard.data(forKey: "profileImage") else {
            return nil
        }
        return UIImage(data: data)
    }
}

// MARK: - Modern Stat Box

struct ModernStatBox: View {
    let value: String
    let label: String
    let icon: String
    let gradient: LinearGradient

    var body: some View {
        VStack(spacing: 12) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(gradient.opacity(0.2))
                    .frame(width: 48, height: 48)

                Text(icon)
                    .font(.system(size: 20))
            }

            VStack(spacing: 4) {
                Text(value)
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)
                    .fontWeight(.bold)

                Text(label)
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Modern Profile Row

struct ModernProfileRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    let action: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 20) {
                // Modern icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)

                    Text(value)
                        .font(.captionLarge)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Modern Settings Row

struct ModernSettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    let action: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 20) {
                // Modern icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Profile Section Editors

struct PhysicalStatsEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var age: String = ""
    @State private var height: String = ""
    @State private var weight: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Physical Stats")) {
                    TextField("Age", text: $age)
                        .keyboardType(.numberPad)
                    TextField("Height (in)", text: $height)
                        .keyboardType(.decimalPad)
                    TextField("Weight (lbs)", text: $weight)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Edit Physical Stats")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        let data = appState.userData
        age = data?.age ?? ""
        height = data?.height ?? ""
        weight = data?.weight ?? ""
    }

    private func save() {
        var data = appState.userData ?? UserData(
            displayName: "",
            age: "",
            height: "",
            weight: "",
            goalWeight: "",
            activityLevel: "",
            dietPreference: "",
            workoutPreference: "",
            calorieTarget: 2000
        )
        data.age = age.trimmingCharacters(in: .whitespacesAndNewlines)
        data.height = height.trimmingCharacters(in: .whitespacesAndNewlines)
        data.weight = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.userData = data
        dismiss()
    }
}

struct GoalsEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var goalWeight: String = ""
    @State private var calorieTarget: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Goals")) {
                    TextField("Goal Weight (lbs)", text: $goalWeight)
                        .keyboardType(.decimalPad)
                    TextField("Daily Calorie Target", text: $calorieTarget)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Edit Goals")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        let data = appState.userData
        goalWeight = data?.goalWeight ?? ""
        calorieTarget = String(data?.calorieTarget ?? 2000)
    }

    private func save() {
        var data = appState.userData ?? UserData(
            displayName: "",
            age: "",
            height: "",
            weight: "",
            goalWeight: "",
            activityLevel: "",
            dietPreference: "",
            workoutPreference: "",
            calorieTarget: 2000
        )
        data.goalWeight = goalWeight.trimmingCharacters(in: .whitespacesAndNewlines)
        if let target = Int(calorieTarget.trimmingCharacters(in: .whitespacesAndNewlines)) {
            data.calorieTarget = target
        }
        appState.userData = data
        dismiss()
    }
}

struct PreferencesEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var activityLevel: String = ""
    @State private var dietPreference: String = ""
    @State private var workoutPreference: String = ""

    private let activityOptions = [
        "Sedentary",
        "Lightly Active",
        "Moderately Active",
        "Very Active",
        "Extra Active"
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferences")) {
                    Picker("Activity Level", selection: $activityLevel) {
                        ForEach(activityOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    Picker("Diet Preference", selection: $dietPreference) {
                        ForEach(DietPreference.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    Picker("Workout Preference", selection: $workoutPreference) {
                        ForEach(WorkoutPreference.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                }
            }
            .navigationTitle("Edit Preferences")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        let data = appState.userData
        activityLevel = data?.activityLevel ?? activityOptions[2]
        dietPreference = data?.dietPreference ?? DietPreference.omnivore.rawValue
        workoutPreference = data?.workoutPreference ?? WorkoutPreference.mixed.rawValue
    }

    private func save() {
        var data = appState.userData ?? UserData(
            displayName: "",
            age: "",
            height: "",
            weight: "",
            goalWeight: "",
            activityLevel: "",
            dietPreference: "",
            workoutPreference: "",
            calorieTarget: 2000
        )
        data.activityLevel = activityLevel
        data.dietPreference = dietPreference
        data.workoutPreference = workoutPreference
        appState.userData = data
        dismiss()
    }
}

struct ProfileIdentityEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var displayName: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showImagePicker = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Photo")) {
                    Button(action: { showImagePicker = true }) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.fitnessGradientStart.opacity(0.2))
                                    .frame(width: 64, height: 64)
                                if let image = profileImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 56)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "camera.fill")
                                        .foregroundColor(.fitnessGradientStart)
                                }
                            }
                            Text("Change Photo")
                                .foregroundColor(.textPrimary)
                        }
                    }
                }

                Section(header: Text("Display Name")) {
                    TextField("Enter your name", text: $displayName)
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .onAppear { load() }
            .photosPicker(isPresented: $showImagePicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { newPhoto in
                if let newPhoto = newPhoto {
                    loadPhoto(newPhoto)
                }
            }
        }
    }

    private func load() {
        displayName = appState.userData?.displayName ?? ""
        if let data = UserDefaults.standard.data(forKey: "profileImage") {
            profileImage = UIImage(data: data)
        }
    }

    private func save() {
        var data = appState.userData ?? UserData(
            displayName: "",
            age: "",
            height: "",
            weight: "",
            goalWeight: "",
            activityLevel: "",
            dietPreference: "",
            workoutPreference: "",
            calorieTarget: 2000
        )
        data.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.userData = data

        if let profileImage = profileImage,
           let imageData = profileImage.jpegData(compressionQuality: 0.85) {
            UserDefaults.standard.set(imageData, forKey: "profileImage")
        }

        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    profileImage = image
                }
            }
        }
    }
}

// MARK: - Modern Divider

struct ModernDivider: View {
    var body: some View {
        Divider()
            .background(Color.textTertiary.opacity(0.1))
            .padding(.leading, 64)
    }
}


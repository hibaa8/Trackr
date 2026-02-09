//
//  SettingsView.swift
//  AITrainer
//
//  App settings and preferences
//

import SwiftUI
import Combine

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SettingsViewModel()

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
                    VStack(spacing: 24) {
                        // Notifications section
                        notificationsSection
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        // Health integration section
                        healthSection
                            .padding(.horizontal, 20)

                        // Workout preferences section
                        workoutPreferencesSection
                            .padding(.horizontal, 20)

                        // Diet preferences section
                        dietPreferencesSection
                            .padding(.horizontal, 20)

                        // App preferences section
                        appPreferencesSection
                            .padding(.horizontal, 20)

                        // Account section
                        accountSection
                            .padding(.horizontal, 20)

                        // About section
                        aboutSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadSettings()
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Notifications", icon: "bell.fill", color: .orange)

            ModernCard {
                VStack(spacing: 0) {
                    ModernToggleRow(
                        title: "Enable Notifications",
                        subtitle: "Get reminders and updates",
                        isOn: $viewModel.enableNotifications
                    )

                    if viewModel.enableNotifications {
                        ModernDivider()

                        ModernToggleRow(
                            title: "Meal Reminders",
                            subtitle: "Remind me to log meals",
                            isOn: $viewModel.mealReminders
                        )

                        ModernDivider()

                        ModernToggleRow(
                            title: "Workout Reminders",
                            subtitle: "Remind me to exercise",
                            isOn: $viewModel.workoutReminders
                        )

                        ModernDivider()

                        ModernToggleRow(
                            title: "Progress Updates",
                            subtitle: "Weekly progress summaries",
                            isOn: $viewModel.progressUpdates
                        )
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Health Section

    private var healthSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Health Integration", icon: "heart.fill", color: .red)

            ModernCard {
                VStack(spacing: 0) {
                    ModernToggleRow(
                        title: "HealthKit Sync",
                        subtitle: "Sync with Apple Health",
                        isOn: $viewModel.enableHealthKitSync
                    )

                    ModernDivider()

                    ModernToggleRow(
                        title: "Calendar Integration",
                        subtitle: "Add workouts to calendar",
                        isOn: $viewModel.enableCalendarIntegration
                    )

                    ModernDivider()

                    ModernActionRow(
                        title: "Sync Health Data",
                        subtitle: "Import latest health data",
                        icon: "arrow.clockwise",
                        color: .blue
                    ) {
                        viewModel.syncHealthData()
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Workout Preferences Section

    private var workoutPreferencesSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Workout Preferences", icon: "dumbbell.fill", color: .purple)

            ModernCard {
                VStack(spacing: 0) {
                    ModernPickerRow(
                        title: "Preferred Workout Time",
                        selection: $viewModel.preferredWorkoutTime,
                        options: ["Morning", "Afternoon", "Evening"],
                        icon: "clock"
                    )

                    ModernDivider()

                    ModernActionRow(
                        title: "Exercise Preferences",
                        subtitle: "Liked and disliked exercises",
                        icon: "heart.circle",
                        color: .green
                    ) {
                        viewModel.showExercisePreferences = true
                    }

                    ModernDivider()

                    ModernPickerRow(
                        title: "Default Workout Duration",
                        selection: $viewModel.defaultWorkoutDuration,
                        options: ["30 min", "45 min", "60 min", "90 min"],
                        icon: "timer"
                    )
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Diet Preferences Section

    private var dietPreferencesSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Diet Preferences", icon: "fork.knife", color: .green)

            ModernCard {
                VStack(spacing: 0) {
                    ModernActionRow(
                        title: "Dietary Restrictions",
                        subtitle: "Allergies and restrictions",
                        icon: "exclamationmark.triangle",
                        color: .orange
                    ) {
                        viewModel.showDietaryRestrictions = true
                    }

                    ModernDivider()

                    ModernPickerRow(
                        title: "Meal Plan Type",
                        selection: $viewModel.mealPlanType,
                        options: ["Balanced", "Low Carb", "High Protein", "Vegetarian"],
                        icon: "leaf"
                    )

                    ModernDivider()

                    ModernToggleRow(
                        title: "Macro Tracking",
                        subtitle: "Track protein, carbs, and fat",
                        isOn: $viewModel.enableMacroTracking
                    )
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - App Preferences Section

    private var appPreferencesSection: some View {
        VStack(spacing: 20) {
            sectionHeader("App Preferences", icon: "gear", color: .gray)

            ModernCard {
                VStack(spacing: 0) {
                    ModernPickerRow(
                        title: "Units",
                        selection: $viewModel.units,
                        options: ["Metric (kg, cm)"],
                        icon: "ruler"
                    )

                    ModernDivider()

                    ModernPickerRow(
                        title: "Theme",
                        selection: $viewModel.theme,
                        options: ["System", "Light", "Dark"],
                        icon: "paintbrush"
                    )

                    ModernDivider()

                    ModernToggleRow(
                        title: "Analytics",
                        subtitle: "Help improve the app",
                        isOn: $viewModel.enableAnalytics
                    )
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Account", icon: "person.circle", color: .blue)

            ModernCard {
                VStack(spacing: 0) {
                    ModernActionRow(
                        title: "Change Password",
                        subtitle: "Update your password",
                        icon: "key",
                        color: .blue
                    ) {
                        viewModel.showChangePassword = true
                    }

                    ModernDivider()

                    ModernActionRow(
                        title: "Privacy Policy",
                        subtitle: "Read our privacy policy",
                        icon: "shield",
                        color: .green
                    ) {
                        viewModel.showPrivacyPolicy = true
                    }

                    ModernDivider()

                    ModernActionRow(
                        title: "Export Data",
                        subtitle: "Download your data",
                        icon: "square.and.arrow.up",
                        color: .orange
                    ) {
                        viewModel.exportUserData()
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: 20) {
            sectionHeader("About", icon: "info.circle", color: .blue)

            ModernCard {
                VStack(spacing: 0) {
                    ModernActionRow(
                        title: "Version",
                        subtitle: "1.0.0",
                        icon: "app",
                        color: .gray
                    ) {}

                    ModernDivider()

                    ModernActionRow(
                        title: "Help & Support",
                        subtitle: "Get help with the app",
                        icon: "questionmark.circle",
                        color: .purple
                    ) {
                        viewModel.showSupport = true
                    }

                    ModernDivider()

                    ModernActionRow(
                        title: "Rate the App",
                        subtitle: "Leave a review",
                        icon: "star",
                        color: .yellow
                    ) {
                        viewModel.rateApp()
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.headlineLarge)
                .foregroundColor(.textPrimary)

            Spacer()
        }
    }
}

// MARK: - Settings ViewModel

class SettingsViewModel: ObservableObject {
    // Notifications
    @Published var enableNotifications = true
    @Published var mealReminders = true
    @Published var workoutReminders = true
    @Published var progressUpdates = false

    // Health
    @Published var enableHealthKitSync = true
    @Published var enableCalendarIntegration = false

    // Workout preferences
    @Published var preferredWorkoutTime = "Morning"
    @Published var defaultWorkoutDuration = "45 min"

    // Diet preferences
    @Published var mealPlanType = "Balanced"
    @Published var enableMacroTracking = true

    // App preferences
    @Published var units = "Metric (kg, cm)"
    @Published var theme = "System"
    @Published var enableAnalytics = true

    // Sheet states
    @Published var showExercisePreferences = false
    @Published var showDietaryRestrictions = false
    @Published var showChangePassword = false
    @Published var showPrivacyPolicy = false
    @Published var showSupport = false

    func loadSettings() {
        // Load settings from UserDefaults or Core Data
        enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
        // ... load other settings
    }

    func saveSettings() {
        // Save settings to UserDefaults or Core Data
        UserDefaults.standard.set(enableNotifications, forKey: "enableNotifications")
        // ... save other settings
    }

    func syncHealthData() {
        // Sync with HealthKit
    }

    func exportUserData() {
        // Export user data
    }

    func rateApp() {
        // Open App Store rating
    }
}

// MARK: - Modern Toggle Row

struct ModernToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.captionLarge)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .tint(.fitnessGradientStart)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Modern Action Row

struct ModernActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)

                    Text(subtitle)
                        .font(.captionLarge)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
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

// MARK: - Modern Picker Row

struct ModernPickerRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    let icon: String

    @State private var showPicker = false

    var body: some View {
        Button(action: {
            showPicker = true
        }) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)

                    Text(selection)
                        .font(.captionLarge)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.fitnessGradientStart)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showPicker) {
            SimplePickerSheet(title: title, selection: $selection, options: options)
        }
    }
}

// MARK: - Simple Picker Sheet

struct SimplePickerSheet: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List(options, id: \.self) { option in
                Button(action: {
                    selection = option
                    dismiss()
                }) {
                    HStack {
                        Text(option)
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
    SettingsView()
        .environmentObject(AppState())
}
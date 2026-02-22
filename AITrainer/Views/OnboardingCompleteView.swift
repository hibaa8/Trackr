import SwiftUI
import Combine
import UIKit
import AVFoundation

struct OnboardingCompleteView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var backendConnector: FrontendBackendConnector
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var showMainApp = false

    private var coach: Coach {
        appState.selectedCoach ?? appState.coaches.first ?? Coach.placeholder
    }
    @State private var confettiOpacity = 0.0
    @State private var checkmarkScale = 0.0
    @State private var textOpacity = 0.0
    @State private var buttonOffset = 50.0

    var body: some View {
        if showMainApp {
            MainTabView()
                .environmentObject(appState)
                .environmentObject(backendConnector)
        } else {
            ZStack {
                // Dark background with celebration effect
                Color.black.ignoresSafeArea()

                // Confetti/celebration background
                ZStack {
                    ForEach(0..<50, id: \.self) { index in
                        ConfettiPiece(delay: Double(index) * 0.1)
                    }
                }
                .opacity(confettiOpacity)

                VStack(spacing: 40) {
                    Spacer()

                    // Success checkmark
                    ZStack {
                        Circle()
                            .stroke(Color.cyan, lineWidth: 4)
                            .frame(width: 120, height: 120)

                        Image(systemName: "checkmark")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    .scaleEffect(checkmarkScale)

                    // Success message
                    VStack(spacing: 16) {
                        Text("You're All Set!")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)

                        Text("\(coach.name) has created your\npersonalized plan. Let's get started!")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(textOpacity)

                    Spacer()

                    // Start Training button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showMainApp = true
                        }
                    }) {
                        Text("Start Training")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(coach.primaryColor),
                                        Color(coach.secondaryColor)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }
                    .offset(y: buttonOffset)
                    .opacity(textOpacity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
            .onAppear {
                startAnimations()
            }
        }
    }

    private func startAnimations() {
        // Confetti animation
        withAnimation(.easeOut(duration: 1.0)) {
            confettiOpacity = 1.0
        }

        // Checkmark animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)) {
            checkmarkScale = 1.0
        }

        // Text animation
        withAnimation(.easeOut(duration: 0.6).delay(0.8)) {
            textOpacity = 1.0
            buttonOffset = 0.0
        }
    }
}

struct ConfettiPiece: View {
    let delay: Double
    @State private var yOffset = -100.0
    @State private var rotation = 0.0
    @State private var opacity = 1.0

    private let colors: [Color] = [.blue, .cyan, .purple, .pink, .orange, .green]
    private let size = Double.random(in: 4...8)
    private let startX = Double.random(in: 0...UIScreen.main.bounds.width)

    var body: some View {
        Rectangle()
            .fill(colors.randomElement() ?? .blue)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .position(x: startX, y: yOffset)
            .onAppear {
                withAnimation(
                    .linear(duration: 3.0)
                    .delay(delay)
                    .repeatForever(autoreverses: false)
                ) {
                    yOffset = UIScreen.main.bounds.height + 100
                    rotation = 360
                }

                withAnimation(
                    .linear(duration: 1.0)
                    .delay(delay + 2.0)
                ) {
                    opacity = 0.0
                }
            }
    }
}

// Main trainer interface matching screen 08 mockup
struct TrainerMainView: View {
    private enum ChatLaunchMode {
        case text
        case voice
    }

    let coach: Coach
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var currentTime = Date()
    @State private var showVoiceChat = false
    @State private var chatLaunchMode: ChatLaunchMode = .text
    @State private var chatInitialPrompt: String?
    @State private var showingWorkoutDetail = false
    @State private var showLogFoodOptions = false
    @State private var showMealLogging = false
    @State private var showManualLogging = false
    @State private var showPlanDetail = false
    @State private var showCalorieDetail = false
    @State private var showRecipePlanner = false
    @State private var showGamificationSheet = false
    @State private var todayPlan: PlanDayResponse?
    @State private var gamification: GamificationResponse?
    @State private var lastKnownPoints: Int?
    @State private var lastKnownLevel: Int?
    @State private var xpGainToastText: String?
    @State private var showXPGainToast = false
    @State private var showDailyCompletionGraffiti = false
    @State private var showLevelUpGraffiti = false
    @State private var leveledTo = 1
    @State private var lastCelebratedDayKey: String?
    @State private var lastMealLogCount = 0
    @State private var lastWorkoutLogCount = 0
    @State private var lastWeightLogCount = 0
    @State private var hasSeededDailyCounts = false
    @State private var showEndOfDayPrompt = false
    @State private var todayCheckinCount = 0
    @State private var checklistCompleteToday = false
    @State private var showChecklistReminder = false
    @State private var showStreakFreezePrompt = false
    @State private var streakFreezePromptMessage = ""
    @State private var speechSynth = AVSpeechSynthesizer()
    @AppStorage("trainer.endOfDayPromptDate") private var lastEndOfDayPromptDate = ""
    @AppStorage("trainer.dailyChecklistPromptDate") private var lastChecklistPromptDate = ""
    @AppStorage("trainer.lastCoachGreetingDay") private var lastCoachGreetingDay = ""
    @State private var isLoadingPlan = false
    @State private var cancellables = Set<AnyCancellable>()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var activePlan: PlanDayResponse? { appState.todayPlan ?? todayPlan }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                trainerBackground

                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                // Extra shader to improve foreground legibility over photos.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.36),
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView(topInset: geometry.safeAreaInsets.top)
                        .padding(.bottom, 30)
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            greetingSection
                                .padding(.horizontal, 24)
                                .padding(.bottom, 10)

                            quickLogActions
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)

                            coachToolsRow
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)

                            dailyChecklistCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)

                            HStack(alignment: .top, spacing: 12) {
                                todaysPlanCard
                                    .frame(maxWidth: .infinity, minHeight: 176)
                                calorieBalanceCard
                                    .frame(maxWidth: .infinity, minHeight: 176)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 120)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if showDailyCompletionGraffiti {
                    DailyCompletionGraffitiOverlay()
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(10)
                }

                if showLevelUpGraffiti {
                    LevelUpGraffitiOverlay(level: leveledTo)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(11)
                }
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onAppear {
            if appState.todayPlan == nil {
                loadTodayPlan()
            } else {
                todayPlan = appState.todayPlan
            }
            refreshDashboardData()
            loadGamification(trackGain: false)
            loadProgressForXPTracking(trackChanges: false)
            checkStreakStatusOnOpen()
            speakMotivationalGreetingIfNeeded()
            maybePromptEndOfDayCheckin()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            refreshDashboardData()
            loadProgressForXPTracking(trackChanges: true)
            loadGamification(trackGain: true)
        }
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(
                coach: coach,
                autoFocus: chatLaunchMode == .text,
                startRecording: chatLaunchMode == .voice,
                initialPrompt: chatInitialPrompt
            )
        }
        .safeAreaInset(edge: .bottom) {
            bottomInputBar
                .padding(.bottom, 10)
        }
        .sheet(isPresented: $showMealLogging) {
            VoiceActiveView(
                coach: coach,
                initialPrompt: "I want to log a meal. Please ask me for the food, quantity, time, and any other details needed to calculate calories, then log it."
            )
        }
        .sheet(isPresented: $showManualLogging) {
            VoiceActiveView(
                coach: coach,
                initialPrompt: "I want to log a meal. Please ask me for the food, quantity, time, and any other details needed to calculate calories, then log it."
            )
        }
        .fullScreenCover(isPresented: $showPlanDetail) {
            TodayPlanDetailView()
        }
        .fullScreenCover(isPresented: $showCalorieDetail) {
            CalorieBalanceDetailView()
        }
        .fullScreenCover(isPresented: $showRecipePlanner) {
            RecipeFinderView()
        }
        .confirmationDialog("Log Food", isPresented: $showLogFoodOptions, titleVisibility: .visible) {
            Button("Log Food") {
                showMealLogging = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showGamificationSheet) {
            if let gamification {
                GamificationSheetView(summary: gamification)
            }
        }
        .onChange(of: showGamificationSheet) { _, isShown in
            if isShown {
                loadGamification(trackGain: false)
            }
        }
        .alert("Daily Check-In", isPresented: $showEndOfDayPrompt) {
            Button("Chat now") {
                chatLaunchMode = .text
                chatInitialPrompt = "Let's do my end-of-day check-in. Analyze today's meals, workouts, and weight progress versus plan/checkpoints, then suggest improvements or ask what I want to adjust."
                showVoiceChat = true
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Want a quick status chat with your coach for today?")
        }
        .alert("Today's Checklist", isPresented: $showChecklistReminder) {
            Button("Open coach chat") {
                chatLaunchMode = .text
                chatInitialPrompt = "Let's do my daily check-in now and confirm today's checklist."
                showVoiceChat = true
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Complete 3 meals, 1 workout, and 1 daily check-in to finish today and earn +10 XP.")
        }
        .alert("Streak Freeze", isPresented: $showStreakFreezePrompt) {
            Button("Use Freeze") {
                submitStreakDecision(useFreeze: true)
            }
            Button("Reset Streak", role: .destructive) {
                submitStreakDecision(useFreeze: false)
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(streakFreezePromptMessage)
        }
    }

    private func headerView(topInset: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(coach.primaryColor).opacity(0.8))
                        .frame(width: 34, height: 34)
                    if let url = coach.imageURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trainer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Text(coach.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if showXPGainToast, let xpGainToastText {
                    Text(xpGainToastText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Button(action: { showGamificationSheet = true }) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Lv \(gamification?.level ?? 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("🔥 \(gamification?.streak_days ?? 0)d")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange.opacity(0.95))
                        Text("\(gamification?.next_level_points ?? 0) to next")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 12)
        .frame(maxWidth: .infinity)
    }

    private var greetingSection: some View {
        VStack(spacing: 12) {
            Text(getGreeting())
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Ready to crush your goals today?")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
    }

    private var dailyChecklistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Checklist")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(checklistCompleteToday ? "Complete" : "In progress")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(checklistCompleteToday ? .green : .orange)
            }
            checklistRow(title: "Log 3 meals", current: lastMealLogCount, target: 3)
            checklistRow(title: "Log workout", current: lastWorkoutLogCount, target: 1)
            checklistRow(title: "Daily check-in", current: todayCheckinCount, target: 1)
        }
        .padding(14)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func checklistRow(title: String, current: Int, target: Int) -> some View {
        let done = current >= target
        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? .green : .white.opacity(0.7))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text("\(min(current, target))/\(target)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(done ? .green : .orange)
        }
    }

    private var todaysPlanCard: some View {
        let workoutTitle = planSummaryTitle()
        let progressText = isLoadingPlan ? "Loading..." : "Tap for details"
        let progressRatio: Double = 0.4

        return Button(action: {
            showPlanDetail = true
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Today's Plan")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text(workoutTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * progressRatio, height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text(progressText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(glassCardBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private var quickLogActions: some View {
        HStack(spacing: 10) {
            quickLogButton(
                title: "Log Weight",
                systemImage: "scalemass.fill"
            ) {
                chatLaunchMode = .text
                chatInitialPrompt = "I want to log my weight. Please ask me for my weight in kg and the date of the weigh-in, then log it."
                showVoiceChat = true
            }

            quickLogButton(
                title: "Log Food",
                systemImage: "fork.knife"
            ) {
                chatLaunchMode = .text
                chatInitialPrompt = "I want to log a meal. Please ask me for the food, quantity, time, and any other details needed to calculate calories, then log it."
                showVoiceChat = true
            }

            quickLogButton(
                title: "Log Workout",
                systemImage: "figure.strengthtraining.traditional"
            ) {
                chatLaunchMode = .text
                chatInitialPrompt = "I want to log a workout. Please ask me for the workout type, duration, sets, reps, intensity, and any other details needed to estimate calories burned, then log it."
                showVoiceChat = true
            }
        }
    }

    private var coachToolsRow: some View {
        HStack(spacing: 10) {
            quickLogButton(
                title: "Plan Meals",
                systemImage: "fork.knife.circle"
            ) {
                showRecipePlanner = true
            }
            quickLogButton(
                title: "Learn Exercise",
                systemImage: "figure.strengthtraining.functional"
            ) {
                chatLaunchMode = .text
                chatInitialPrompt = "Teach me how to do an exercise properly. Ask which exercise I want to learn, then give cues, common mistakes, regressions, and progressions."
                showVoiceChat = true
            }
        }
    }

    private func quickLogButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var calorieBalanceCard: some View {
        let caloriesConsumed = appState.caloriesIn
        let caloriesGoal = activePlan?.calorie_target ?? appState.userData?.calorieTarget ?? 2000
        let progress = min(1.0, max(0.0, Double(caloriesConsumed) / Double(max(caloriesGoal, 1))))
        let remaining = max(0, caloriesGoal - caloriesConsumed)

        return Button(action: {
            showCalorieDetail = true
        }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Calorie Balance")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 8)
                            .frame(width: 68, height: 68)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [Color.cyan, Color.blue]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 68, height: 68)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 2) {
                            Text("\(caloriesConsumed)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("of \(caloriesGoal)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(remaining) kcal")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        Text("remaining")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Tap for details")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(glassCardBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial.opacity(0.94))
            .background(Color.black.opacity(0.42))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private var trainerBackground: some View {
        Group {
            if let url = coach.imageURL {
                GeometryReader { geometry in
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.black
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .scaleEffect(1.1)
                    .saturation(0.72)
                    .brightness(-0.06)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    private func planSummaryTitle() -> String {
        if activePlan?.rest_day == true {
            return "Rest Day"
        }
        let plan = (activePlan?.workout_plan ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if plan.isEmpty {
            return "Full Body Strength"
        }
        if let colon = plan.firstIndex(of: ":") {
            let prefix = String(plan[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix.isEmpty ? "Full Body Strength" : prefix
        }
        if let period = plan.firstIndex(of: ".") {
            let prefix = String(plan[..<period]).trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix.isEmpty ? "Full Body Strength" : prefix
        }
        let words = plan.split(separator: " ")
        if words.count > 5 {
            return words.prefix(5).joined(separator: " ")
        }
        return plan
    }

    private var bottomInputBar: some View {
        HStack(spacing: 16) {
            Button(action: {
                chatLaunchMode = .text
                chatInitialPrompt = nil
                showVoiceChat = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Text")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.15))
                )
            }

            Button(action: {
                chatLaunchMode = .voice
                chatInitialPrompt = nil
                showVoiceChat = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Voice")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.15))
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial.opacity(0.9))
                .background(Color.black.opacity(0.4))
        )
        .padding(.horizontal, 20)
    }


    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: currentTime)

        if hour < 12 {
            return "Good morning!"
        } else if hour < 17 {
            return "Good afternoon!"
        } else {
            return "Good evening!"
        }
    }

    // AppState handles daily intake refresh

    private func refreshDashboardData() {
        guard let userId = authManager.effectiveUserId else { return }
        appState.refreshDailyData(for: appState.selectedDate, userId: userId)
        loadTodayPlan()
    }

    private func loadTodayPlan() {
        guard let userId = authManager.effectiveUserId else {
            return
        }
        isLoadingPlan = true
        APIService.shared.getTodayPlan(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingPlan = false
                    if case .failure(let error) = completion {
                        print("Failed to load today's plan: \(error)")
                    }
                },
                receiveValue: { plan in
                    self.todayPlan = plan
                    self.appState.todayPlan = plan
                    if var existing = self.appState.userData {
                        existing.calorieTarget = plan.calorie_target
                        self.appState.userData = existing
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func loadGamification(trackGain: Bool) {
        guard let userId = authManager.effectiveUserId else { return }
        APIService.shared.getGamification(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { summary in
                    let previousPoints = self.lastKnownPoints
                    let previousLevel = self.lastKnownLevel
                    self.gamification = summary
                    self.lastKnownPoints = summary.points
                    self.lastKnownLevel = summary.level
                    if trackGain, let previousPoints, summary.points > previousPoints {
                        let gained = summary.points - previousPoints
                        let encouragement = randomEncouragement(for: gained)
                        showXPGainToast(
                            message: "+\(gained) XP • \(summary.next_level_points) to next level • \(encouragement)"
                        )
                        speak(encouragement)
                    }
                    if trackGain, let previousLevel, summary.level > previousLevel {
                        leveledTo = summary.level
                        showXPGainToast(
                            message: "Level up! +1 streak freeze unlocked"
                        )
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showLevelUpGraffiti = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showLevelUpGraffiti = false
                            }
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func loadProgressForXPTracking(trackChanges: Bool) {
        guard let userId = authManager.effectiveUserId else { return }
        APIService.shared.getProgress(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { progress in
                    let todayKey = dayKey(from: Date())
                    let checklist = progress.daily_checklist
                    let mealCount = checklist?.meals_logged ?? progress.meals.filter { item in
                        dayKey(fromRaw: item.logged_at) == todayKey
                    }.count
                    let workoutCount = checklist?.workouts_logged ?? progress.workouts.filter { item in
                        item.completed == true && dayKey(fromRaw: item.date) == todayKey
                    }.count
                    let checkinCount = checklist?.checkin_done == true
                        ? 1
                        : progress.checkins.filter { item in dayKey(fromRaw: item.date) == todayKey }.count

                    triggerDailyCompletionGraffitiIfNeeded(
                        mealCount: mealCount,
                        workoutCount: workoutCount,
                        checkinCount: checkinCount,
                        dayKey: todayKey
                    )
                    lastMealLogCount = mealCount
                    lastWorkoutLogCount = workoutCount
                    lastWeightLogCount = checkinCount
                    todayCheckinCount = checkinCount
                    checklistCompleteToday = checklist?.checklist_done ?? (mealCount >= 3 && workoutCount >= 1 && checkinCount >= 1)
                    maybePromptDailyChecklist()
                    hasSeededDailyCounts = true
                }
            )
            .store(in: &cancellables)
    }

    private func triggerDailyCompletionGraffitiIfNeeded(mealCount: Int, workoutCount: Int, checkinCount: Int, dayKey: String) {
        guard mealCount >= 3, workoutCount >= 1, checkinCount >= 1, lastCelebratedDayKey != dayKey else { return }
        lastCelebratedDayKey = dayKey
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showDailyCompletionGraffiti = true
        }
        let quote = completionQuote()
        showXPGainToast(message: "Checklist complete! +10 XP • \(quote)")
        speak("Checklist complete. Great job today. \(quote)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showDailyCompletionGraffiti = false
            }
        }
    }

    private func dayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dayKey(fromRaw value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        let calendar = Calendar.current
        if lower == "today" || lower == "now" {
            return dayKey(from: Date())
        }
        if lower == "yesterday", let date = calendar.date(byAdding: .day, value: -1, to: Date()) {
            return dayKey(from: date)
        }
        if raw.count >= 10 {
            let prefix = String(raw.prefix(10))
            let chars = Array(prefix)
            if chars.count >= 10, chars[4] == "-", chars[7] == "-" {
                return prefix
            }
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            return dayKey(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: raw) {
            return dayKey(from: date)
        }
        return nil
    }

    private func showXPGainToast(message: String) {
        xpGainToastText = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showXPGainToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showXPGainToast = false
            }
        }
    }

    private func maybePromptEndOfDayCheckin() {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= 20 else { return }
        let today = dayKey(from: now)
        guard lastEndOfDayPromptDate != today else { return }
        lastEndOfDayPromptDate = today
        showEndOfDayPrompt = true
    }

    private func maybePromptDailyChecklist() {
        let today = dayKey(from: Date())
        guard !checklistCompleteToday else { return }
        guard lastChecklistPromptDate != today else { return }
        lastChecklistPromptDate = today
        showChecklistReminder = true
    }

    private func checkStreakStatusOnOpen() {
        guard let userId = authManager.effectiveUserId else { return }
        APIService.shared.notifyAppOpen(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    self.gamification = response.gamification
                    if response.freeze_prompt_required {
                        self.streakFreezePromptMessage = response.message
                        self.showStreakFreezePrompt = true
                    } else if response.streak_reset {
                        self.showXPGainToast(message: response.message)
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func submitStreakDecision(useFreeze: Bool) {
        guard let userId = authManager.effectiveUserId else { return }
        APIService.shared.submitStreakDecision(userId: userId, useFreeze: useFreeze)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    self.gamification = response.gamification
                    self.showXPGainToast(message: response.message)
                }
            )
            .store(in: &cancellables)
    }

    private func randomEncouragement(for gained: Int) -> String {
        if gained >= 10 {
            return completionQuote()
        }
        let lines = [
            "Nice work. Keep stacking wins.",
            "Strong move. Stay consistent.",
            "Great logging discipline today.",
            "You are building momentum.",
            "One rep, one meal, one win at a time."
        ]
        return lines.randomElement() ?? "Great job."
    }

    private func completionQuote() -> String {
        let quotes = [
            "Consistency beats intensity over time.",
            "Small wins compound into big results.",
            "Discipline today builds confidence tomorrow.",
            "You are proving it to yourself.",
            "Progress is earned one day at a time."
        ]
        return quotes.randomElement() ?? "You crushed it."
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.volume = 0.9
        speechSynth.speak(utterance)
    }

    private func speakMotivationalGreetingIfNeeded() {
        let today = dayKey(from: Date())
        guard lastCoachGreetingDay != today else { return }
        lastCoachGreetingDay = today
        let phrase = coach.commonPhrases.randomElement() ?? "Let's get after it."
        let text = "\(phrase) Ready to make progress today."
        speak(text)
    }
}

private struct DailyCompletionGraffitiOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            Circle()
                .fill(Color.pink.opacity(0.35))
                .frame(width: 260, height: 260)
                .offset(x: -70, y: -30)
            Circle()
                .fill(Color.cyan.opacity(0.3))
                .frame(width: 220, height: 220)
                .offset(x: 90, y: 30)
            Circle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 180, height: 180)
                .offset(x: 10, y: -100)

            Text("DAY CRUSHED")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .rotationEffect(.degrees(-8))
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)

            Text("Meals + workouts complete")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: 56)
        }
        .allowsHitTesting(false)
    }
}

private struct LevelUpGraffitiOverlay: View {
    let level: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            Circle()
                .fill(Color.orange.opacity(0.34))
                .frame(width: 280, height: 280)
                .offset(x: -75, y: -40)
            Circle()
                .fill(Color.purple.opacity(0.3))
                .frame(width: 230, height: 230)
                .offset(x: 95, y: 25)

            VStack(spacing: 8) {
                Text("LEVEL UP")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(-7))
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)

                Text("Level \(level) • +1 Streak Freeze")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .allowsHitTesting(false)
    }
}

// Alias for the trainer content without bottom toolbar
typealias TrainerMainViewContent = TrainerMainView

// Voice Active View matching screen 09 mockup
struct VoiceActiveView: View {
    let coach: Coach
    var autoFocus: Bool = false
    var startRecording: Bool = false
    var initialPrompt: String? = nil
    @State private var messages: [VoiceMessage] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var threadId: String?
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showImageOptions = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var didSendInitialPrompt = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            // Blurred gym background
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 200))
                .foregroundColor(.white.opacity(0.05))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.6), Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: 10)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }

                    Text("Trainer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                coachProfileHeader

                // Chat messages
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(messages) { message in
                            VoiceMessageBubble(message: message, coach: coach)
                        }
                        if isLoading {
                            VoiceTypingDots()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                Spacer()

                // Input bar (image + text + voice/send)
                VStack(spacing: 10) {
                    if let selectedImage {
                        HStack(spacing: 12) {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                            Spacer()
                            Button(action: { self.selectedImage = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    HStack(spacing: 12) {
                        Button(action: { showImageOptions = true }) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        TextField("Type to ask your coach...", text: $messageText, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.white.opacity(0.15))
                            )
                            .focused($inputFocused)

                        if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil {
                            Button(action: sendMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.blue)
                            }
                            .disabled(isLoading)
                        } else {
                            Button(action: {
                                if isRecording {
                                    stopVoiceRecording()
                                } else {
                                    startVoiceRecording()
                                }
                            }) {
                                Image(systemName: isRecording ? "mic.fill" : "mic")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(isRecording ? .red : .white.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)

                    if isRecording {
                        Text("Recording...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .onAppear {
            loadWelcomeMessage()
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    inputFocused = true
                }
            }
            if startRecording {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startVoiceRecording()
                }
            }
            if let prompt = initialPrompt, !didSendInitialPrompt {
                didSendInitialPrompt = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    messageText = prompt
                    sendMessage()
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: imagePickerSource, selectedImage: $selectedImage)
        }
        .confirmationDialog("Add Image", isPresented: $showImageOptions, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") {
                    imagePickerSource = .camera
                    showImagePicker = true
                }
            }
            Button("Photo Library") {
                imagePickerSource = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }

 
    private func loadWelcomeMessage() {
        if messages.isEmpty {
            let examples = """
            Try asking me things like:
            - "My current plan feels too difficult. Can you adjust it?"
            - "I'm unmotivated and missed workouts this week."
            - "I'm going on vacation next week. Please adapt my plan."
            - "Plan a good meal for today with what I have."
            - "Teach me a new exercise with proper form."
            - "I need quick, high-protein meals under 30 minutes."
            """
            messages = [
                VoiceMessage(
                    id: UUID(),
                    text: "Hi! I'm \(coach.name). Ask me anything about workouts, nutrition, or your plan.",
                    isFromCoach: true,
                    timestamp: Date(),
                    image: nil
                ),
                VoiceMessage(
                    id: UUID(),
                    text: examples,
                    isFromCoach: true,
                    timestamp: Date(),
                    image: nil
                )
            ]
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let outgoingText = trimmed.isEmpty && selectedImage != nil ? "Sent an image." : trimmed
        guard !outgoingText.isEmpty else { return }

        let userMessage = VoiceMessage(
            id: UUID(),
            text: outgoingText,
            isFromCoach: false,
            timestamp: Date(),
            image: selectedImage
        )
        messages.append(userMessage)
        messageText = ""
        let imageToUpload = selectedImage
        selectedImage = nil
        isLoading = true
        guard let userId = authManager.effectiveUserId else {
            isLoading = false
            return
        }

        if let imageToUpload {
            uploadImage(imageToUpload, message: outgoingText) { result in
                let imageBase64: String?
                switch result {
                case .success(let encoded):
                    imageBase64 = encoded
                case .failure:
                    imageBase64 = nil
                }
                sendChat(outgoingText, imageBase64: imageBase64, userId: userId)
            }
        } else {
            sendChat(outgoingText, imageBase64: nil, userId: userId)
        }
    }

    private func sendChat(_ outgoingText: String, imageBase64: String?, userId: Int) {
        AICoachService.shared.sendMessage(
            outgoingText,
            threadId: threadId,
            agentId: coach.id,
            userId: userId,
            imageBase64: imageBase64
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let response):
                    self.threadId = response.thread_id
                    let replyText = response.reply.isEmpty ? "How can I help you next?" : response.reply
                    let coachMessage = VoiceMessage(
                        id: UUID(),
                        text: replyText,
                        isFromCoach: true,
                        timestamp: Date(),
                        image: nil
                    )
                    self.messages.append(coachMessage)
                    NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
                case .failure:
                    let errorMessage = VoiceMessage(
                        id: UUID(),
                        text: "I couldn’t reach the coach service. Please make sure the backend is running.",
                        isFromCoach: true,
                        timestamp: Date(),
                        image: nil
                    )
                    self.messages.append(errorMessage)
                }
            }
        }
    }

    private func startVoiceRecording() {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { return }
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)

                    let filename = "voice-\(UUID().uuidString).m4a"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 12000,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                    ]
                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    recorder.record()
                    audioRecorder = recorder
                    isRecording = true
                } catch {
                    isRecording = false
                }
            }
        }
    }

    private func stopVoiceRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        let url = audioRecorder?.url
        audioRecorder = nil
        isRecording = false
        guard let url else { return }
        transcribeVoice(url: url)
    }

    private func transcribeVoice(url: URL) {
        guard let requestUrl = URL(string: "\(BackendConfig.baseURL)/api/voice-to-text") else { return }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"voice.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        if let data = try? Data(contentsOf: url) {
            body.append(data)
        }
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"trainer_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(coach.id)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: body) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = payload["transcribed_text"] as? String else {
                return
            }
            DispatchQueue.main.async {
                messageText = text
                sendMessage()
            }
        }.resume()
    }

    private func uploadImage(_ image: UIImage, message: String?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let requestUrl = URL(string: "\(BackendConfig.baseURL)/api/upload-image") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let data = image.jpegData(compressionQuality: 0.85) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"trainer_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(coach.id)\r\n".data(using: .utf8)!)
        if let message, !message.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"message\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(message)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: body) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let encoded = payload["image_base64"] as? String else {
                completion(.failure(URLError(.cannotParseResponse)))
                return
            }
            completion(.success(encoded))
        }.resume()
    }

    private var coachProfileHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(coach.primaryColor).opacity(0.8))
                    .frame(width: 44, height: 44)
                if let url = coach.imageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(coach.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(coach.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

}

struct VoiceMessage: Identifiable {
    let id: UUID
    let text: String
    let isFromCoach: Bool
    let timestamp: Date
    let image: UIImage?
}


private struct VoiceImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        let resolvedSource: UIImagePickerController.SourceType
        if sourceType == .camera, UIImagePickerController.isSourceTypeAvailable(.camera) {
            resolvedSource = .camera
        } else {
            resolvedSource = .photoLibrary
        }
        picker.sourceType = resolvedSource
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VoiceImagePicker
        init(_ parent: VoiceImagePicker) {
            self.parent = parent
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private struct GamificationSheetView: View {
    let summary: GamificationResponse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.06, green: 0.08, blue: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Level \(summary.level)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(summary.points) XP")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text("\(summary.next_level_points) XP to next level")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.28), Color.cyan.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

                xpProgressBar

                HStack(spacing: 12) {
                    statCard(title: "Streak", value: "\(summary.streak_days) days")
                    statCard(title: "Best", value: "\(summary.best_streak_days) days")
                }
                HStack(spacing: 12) {
                    statCard(title: "Freeze", value: "\(summary.freeze_streaks)")
                    statCard(title: "Streak Freeze Used", value: "\(summary.used_freeze_streaks)")
                }

                ShareLink(item: summary.share_text) {
                    Text("Share streak with friends")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("XP & Streaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            }
        }
    }

    private var xpProgressBar: some View {
        let required = max(1, 60 + ((summary.level - 1) * 5))
        let toNext = max(0, summary.next_level_points)
        let inLevel = max(0, required - toNext)
        let progress = min(1.0, max(0.0, Double(inLevel) / Double(required)))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress to next level")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                Spacer()
                Text("\(inLevel)/\(required)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 10)
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 2)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct VoiceMessageBubble: View {
    let message: VoiceMessage
    let coach: Coach

    var body: some View {
        HStack {
            if message.isFromCoach {
                HStack(spacing: 12) {
                    // Coach avatar
                    ZStack {
                        Circle()
                            .fill(Color(coach.primaryColor).opacity(0.8))
                            .frame(width: 32, height: 32)
                        if let url = coach.imageURL {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let image = message.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Text(.init(message.text))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(coach.primaryColor).opacity(0.9), Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(18, corners: [.topLeft, .topRight, .bottomRight])
                }
                Spacer()
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if let image = message.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 180, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Text(.init(message.text))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(18, corners: [.topLeft, .topRight, .bottomLeft])
            }
        }
    }

}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private struct VoiceTypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == index ? 1.25 : 0.9)
                        .opacity(phase == index ? 1.0 : 0.45)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.16))
            .clipShape(Capsule())
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

struct VoiceWaveform: View {
    @Binding var isAnimating: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 3, height: CGFloat.random(in: 10...40))
                    .scaleEffect(y: isAnimating ? CGFloat.random(in: 0.3...1.5) : 0.5)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.3...0.8))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 40)
        .background(
            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 120, height: 120)
        )
    }
}


#Preview {
    OnboardingCompleteView()
        .environmentObject(AppState())
        .environmentObject(FrontendBackendConnector.shared)
        .environmentObject(AuthenticationManager())
}

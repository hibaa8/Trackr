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
        appState.selectedCoach ?? appState.coaches.first ?? Coach.allCoaches[0]
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
    let coach: Coach
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var currentTime = Date()
    @State private var showVoiceChat = false
    @State private var focusChatOnOpen = false
    @State private var showingWorkoutDetail = false
    @State private var showLogFoodOptions = false
    @State private var showMealLogging = false
    @State private var showManualLogging = false
    @State private var showPlanDetail = false
    @State private var showCalorieDetail = false
    @State private var showGamificationSheet = false
    @State private var todayPlan: PlanDayResponse?
    @State private var gamification: GamificationResponse?
    @State private var lastKnownPoints: Int?
    @State private var xpGainToastText: String?
    @State private var showXPGainToast = false
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

                VStack(spacing: 0) {
                    headerView(topInset: geometry.safeAreaInsets.top)
                        .padding(.bottom, 30)

                    greetingSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)

                    VStack(spacing: 15) {
                        todaysPlanCard
                        calorieBalanceCard
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            refreshDashboardData()
            loadGamification(trackGain: true)
        }
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(coach: coach, autoFocus: focusChatOnOpen, startRecording: !focusChatOnOpen)
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
        .confirmationDialog("Log Food", isPresented: $showLogFoodOptions, titleVisibility: .visible) {
            Button("Log Food") {
                showMealLogging = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showGamificationSheet) {
            if let gamification {
                GamificationSheetView(
                    summary: gamification,
                    onUseFreeze: { useFreezeStreak() }
                )
            }
        }
        .onChange(of: showGamificationSheet) { _, isShown in
            if isShown {
                loadGamification(trackGain: false)
            }
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
                        Text("\(gamification?.points ?? 0) XP")
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

    private var calorieBalanceCard: some View {
        let caloriesConsumed = appState.caloriesIn
        let caloriesGoal = activePlan?.calorie_target ?? appState.userData?.calorieTarget ?? 2000
        let progress = min(1.0, max(0.0, Double(caloriesConsumed) / Double(max(caloriesGoal, 1))))
        let remaining = max(0, caloriesGoal - caloriesConsumed)

        return Button(action: {
            showCalorieDetail = true
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Calorie Balance")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 8)
                            .frame(width: 80, height: 80)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [Color.cyan, Color.blue]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 2) {
                            Text("\(caloriesConsumed)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("of \(caloriesGoal)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(remaining) kcal")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        Text("remaining")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Text("Tap for details")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(glassCardBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial.opacity(0.9))
            .background(Color.black.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                focusChatOnOpen = true
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
                focusChatOnOpen = false
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
                    self.gamification = summary
                    self.lastKnownPoints = summary.points
                    guard trackGain, let previousPoints, summary.points > previousPoints else { return }
                    let gained = summary.points - previousPoints
                    showXPGainToast(message: "Coach: +\(gained) XP")
                }
            )
            .store(in: &cancellables)
    }

    private func useFreezeStreak() {
        guard let userId = authManager.effectiveUserId else { return }
        APIService.shared.useFreezeStreak(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { summary in
                    self.gamification = summary
                }
            )
            .store(in: &cancellables)
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
            messages = [
                VoiceMessage(
                    id: UUID(),
                    text: "Hi! I'm \(coach.name). Ask me anything about workouts, nutrition, or your plan.",
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
    let onUseFreeze: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Level \(summary.level)")
                        .font(.system(size: 28, weight: .bold))
                    Text("\(summary.points) XP")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("\(summary.next_level_points) XP to next level")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)

                xpProgressBar

                HStack(spacing: 12) {
                    statCard(title: "Streak", value: "\(summary.streak_days) days")
                    statCard(title: "Best", value: "\(summary.best_streak_days) days")
                }
                HStack(spacing: 12) {
                    statCard(title: "Freeze", value: "\(summary.freeze_streaks)")
                    statCard(title: "Unlocked", value: "\(summary.unlocked_freeze_streaks)")
                }

                Button(action: { onUseFreeze() }) {
                    Text("Use freeze to save your streak")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(summary.freeze_streaks <= 0)
                .opacity(summary.freeze_streaks <= 0 ? 0.5 : 1)

                ShareLink(item: summary.share_text) {
                    Text("Share streak with friends")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("XP & Streaks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var xpProgressBar: some View {
        let total = max(1, summary.next_level_points)
        let progress = min(1.0, max(0.0, Double(summary.points) / Double(total)))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress to next level")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(summary.points)/\(summary.next_level_points)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue)
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
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.06))
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

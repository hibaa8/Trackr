import SwiftUI
import Combine
import UIKit
import AVFoundation

struct OnboardingCompleteView: View {
    let coach: Coach
    @EnvironmentObject private var backendConnector: FrontendBackendConnector
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var showMainApp = false
    @State private var confettiOpacity = 0.0
    @State private var checkmarkScale = 0.0
    @State private var textOpacity = 0.0
    @State private var buttonOffset = 50.0

    var body: some View {
        if showMainApp {
            MainTabView(coach: coach)
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
    @State private var todayPlan: PlanDayResponse?
    @State private var isLoadingPlan = false
    @State private var cancellables = Set<AnyCancellable>()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var activePlan: PlanDayResponse? { appState.todayPlan ?? todayPlan }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Realistic gym background with person
                AsyncImage(url: URL(string: "https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } placeholder: {
                    // Fallback gym-style background
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.25, blue: 0.3),
                            Color(red: 0.15, green: 0.2, blue: 0.25),
                            Color(red: 0.1, green: 0.15, blue: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()

                // Dark overlay for text readability
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerView

                    Spacer()

                    // Main content positioned to match mockup
                    VStack(spacing: 32) {
                        // Greeting text
                        greetingSection

                        // Cards positioned lower on screen
                        HStack(spacing: 16) {
                            todaysPlanCard
                            calorieBalanceCard
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 120) // Space for bottom toolbar

                    Spacer()
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
        }
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(coach: coach, autoFocus: focusChatOnOpen)
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
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(coach.primaryColor).opacity(0.8))
                        .frame(width: 34, height: 34)
                    if let image = coachAvatar() {
                        image
                            .resizable()
                            .scaledToFill()
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(coach.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 40) // Moved higher as requested
    }

    private func coachAvatar() -> Image? {
        guard let url = coach.imageURL,
              let uiImage = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private var greetingSection: some View {
        VStack(spacing: 8) {
            Text(getGreeting())
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Ready to crush your goals today?")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    private var todaysPlanCard: some View {
        let workoutTitle = activePlan?.workout_plan ?? "Leg Day - 45 min"
        let workoutDetails: String
        if activePlan?.rest_day == true {
            workoutDetails = "Rest, recover, and stretch today."
        } else if let plan = activePlan?.workout_plan, !plan.isEmpty {
            workoutDetails = plan
        } else {
            workoutDetails = "Warm-up, Squats, Lunges, Cool-down"
        }
        let progressText = isLoadingPlan ? "Loading..." : "Tap for details"

        return Button(action: {
            showPlanDetail = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today's Plan")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text(workoutTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text(workoutDetails)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)

                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: 80, height: 4) // 75% progress
                        }

                        Text(progressText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 160)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial.opacity(0.8))
                    .background(Color.black.opacity(0.3))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var calorieBalanceCard: some View {
        let caloriesConsumed = appState.caloriesIn
        let caloriesGoal = activePlan?.calorie_target ?? appState.userData?.calorieTarget ?? 2000
        let progress = min(1.0, max(0.0, Double(caloriesConsumed) / Double(max(caloriesGoal, 1))))
        let remaining = max(0, caloriesGoal - caloriesConsumed)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Calorie Balance")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 10)
                        .frame(width: 86, height: 86)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [Color.cyan, Color.blue, Color.purple]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 86, height: 86)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color.blue.opacity(0.35), radius: 5, x: 0, y: 2)

                    VStack(spacing: 2) {
                        Text("\(caloriesConsumed)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text("of \(caloriesGoal)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("\(remaining)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("kcal remaining")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: CGFloat(progress) * 110, height: 6)
                    }
                    .frame(width: 110)

                    Text("Tap for details")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial.opacity(0.9))
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.black.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onTapGesture {
            showCalorieDetail = true
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            // Keyboard icon
            Button(action: {
                focusChatOnOpen = true
                showVoiceChat = true
            }) {
                Image(systemName: "keyboard")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(0.6))
                    )
            }

            Spacer()

            // Voice microphone (main action) - matches mockup
            Button(action: {
                focusChatOnOpen = false
                showVoiceChat = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // Camera icon
            Button(action: {}) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(0.6))
                    )
            }
        }
        .frame(height: 120)
        .padding(.horizontal, 24)
        .padding(.bottom, 50) // Moved lower as requested
        .background(
            RoundedRectangle(cornerRadius: 24)
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
}

// Alias for the trainer content without bottom toolbar
typealias TrainerMainViewContent = TrainerMainView

// Voice Active View matching screen 09 mockup
struct VoiceActiveView: View {
    let coach: Coach
    var autoFocus: Bool = false
    var initialPrompt: String? = nil
    @State private var messages: [VoiceMessage] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var threadId: String?
    @State private var didSendInitialPrompt = false
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var audioErrorMessage: String?
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
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
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                Spacer()

                // Text input for agent chat
                HStack(spacing: 12) {
                    TextField("Type to ask your coach...", text: $messageText)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.15))
                        )
                        .focused($inputFocused)

                    Button(action: toggleRecording) {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(isRecording ? Color.red : Color.white.opacity(0.2))
                            )
                    }

                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(messageText.isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                            )
                    }
                    .disabled(messageText.isEmpty || isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            loadWelcomeMessage()
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    inputFocused = true
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
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        audioErrorMessage = nil
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    audioErrorMessage = "Microphone permission denied."
                    return
                }
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    let filename = UUID().uuidString + ".m4a"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]
                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    recorder.record()
                    audioRecorder = recorder
                    recordingURL = url
                    isRecording = true
                } catch {
                    audioErrorMessage = "Could not start recording."
                }
            }
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        guard let url = recordingURL else { return }
        sendAudioForTranscription(url: url)
    }

    private func sendAudioForTranscription(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let boundary = "Boundary-\(UUID().uuidString)"
        let endpoint = "\(BackendConfig.baseURL)/api/transcribe"
        guard let requestURL = URL(string: endpoint) else { return }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else { return }
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async {
                messageText = trimmed
                sendMessage()
            }
        }.resume()
    }

    private func loadWelcomeMessage() {
        if messages.isEmpty {
            messages = [
                VoiceMessage(
                    id: UUID(),
                    text: "Hi! I'm \(coach.name). Ask me anything about workouts, nutrition, or your plan.",
                    isFromCoach: true,
                    timestamp: Date()
                )
            ]
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = VoiceMessage(id: UUID(), text: trimmed, isFromCoach: false, timestamp: Date())
        messages.append(userMessage)
        messageText = ""
        isLoading = true

        guard let userId = authManager.effectiveUserId else {
            let errorMessage = VoiceMessage(
                id: UUID(),
                text: "Missing user ID. Please sign in again to log this.",
                isFromCoach: true,
                timestamp: Date()
            )
            messages.append(errorMessage)
            return
        }
        AICoachService.shared.sendMessage(
            trimmed,
            threadId: threadId,
            agentId: coach.id,
            userId: userId
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
                        timestamp: Date()
                    )
                    self.messages.append(coachMessage)
                    NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
                case .failure:
                    let errorMessage = VoiceMessage(
                        id: UUID(),
                        text: "I couldn’t reach the coach service. Please make sure the backend is running.",
                        isFromCoach: true,
                        timestamp: Date()
                    )
                    self.messages.append(errorMessage)
                }
            }
        }
    }

    private var coachProfileHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(coach.primaryColor).opacity(0.8))
                    .frame(width: 44, height: 44)
                if let image = coachAvatar() {
                    image
                        .resizable()
                        .scaledToFill()
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

    private func coachAvatar() -> Image? {
        guard let url = coach.imageURL,
              let uiImage = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
}

struct VoiceMessage: Identifiable {
    let id: UUID
    let text: String
    let isFromCoach: Bool
    let timestamp: Date
}

private struct TranscriptionResponse: Decodable {
    let text: String
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
                        if let image = coachAvatar() {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }

                    Text(.init(message.text))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineSpacing(4)
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
                Text(.init(message.text))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(18, corners: [.topLeft, .topRight, .bottomLeft])
            }
        }
    }

    private func coachAvatar() -> Image? {
        guard let url = coach.imageURL,
              let uiImage = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return Image(uiImage: uiImage)
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
    OnboardingCompleteView(coach: Coach.allCoaches[0])
        .environmentObject(FrontendBackendConnector.shared)
        .environmentObject(AuthenticationManager())
}

import SwiftUI
import Combine

struct OnboardingCompleteView: View {
    let coach: Coach
    @State private var showMainApp = false
    @State private var confettiOpacity = 0.0
    @State private var checkmarkScale = 0.0
    @State private var textOpacity = 0.0
    @State private var buttonOffset = 50.0

    var body: some View {
        if showMainApp {
            MainTabView(coach: coach)
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
    @State private var currentTime = Date()
    @State private var showVoiceChat = false
    @State private var caloriesConsumed = 1850
    @State private var caloriesGoal = 2500
    @State private var showingWorkoutDetail = false

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Real gym photo background (placeholder - would use actual photo)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 200))
                .foregroundColor(.white.opacity(0.1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.8), Color.black.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with navigation
                headerView

                Spacer()

                // Main content area
                VStack(spacing: 20) {
                    // Greeting text overlay
                    greetingSection

                    Spacer().frame(height: 40)

                    // Two cards side by side
                    HStack(spacing: 16) {
                        todaysPlanCard
                        calorieBalanceCard
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Bottom toolbar
                bottomToolbar
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .sheet(isPresented: $showVoiceChat) {
            VoiceActiveView(coach: coach)
        }
    }

    private var headerView: some View {
        HStack {
            Text("Trainer")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Plan")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Leg Day - 45 min")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Warm-up, Squats,\nLunges, Cool-down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                VStack(spacing: 4) {
                    Text("75% Complete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 60, height: 4) // 75% of ~80px width
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.4))
                .backdrop(blur: 20)
        )
    }

    private var calorieBalanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calorie Balance")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 20) {
                // Circular progress with fork/knife icon
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 6)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: CGFloat(caloriesConsumed) / CGFloat(caloriesGoal))
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 16))
                            .foregroundColor(.white)

                        Text("\(caloriesConsumed)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                VStack(spacing: 4) {
                    Text("\(caloriesConsumed)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("\(caloriesGoal) kcal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.4))
                .backdrop(blur: 20)
        )
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            // Keyboard icon
            Button(action: {}) {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.4))
            }

            Spacer()

            // Voice microphone (main action)
            Button(action: {
                showVoiceChat = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // Camera icon
            Button(action: {}) {
                Image(systemName: "camera")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.4))
            }
        }
        .frame(height: 80)
        .padding(.horizontal, 20)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .backdrop(blur: 20)
        )
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
}

// Voice Active View matching screen 09 mockup
struct VoiceActiveView: View {
    let coach: Coach
    @State private var messages: [VoiceMessage] = []
    @State private var isListening = true
    @State private var waveAnimation = false
    @Environment(\.dismiss) private var dismiss

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

                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                // Chat messages
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(sampleMessages) { message in
                            VoiceMessageBubble(message: message, coach: coach)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                }

                Spacer()

                // Voice waveform and listening indicator
                VStack(spacing: 20) {
                    // Animated waveform
                    VoiceWaveform(isAnimating: $waveAnimation)

                    Text("Listening...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            startListeningAnimation()
            loadSampleConversation()
        }
    }

    private func startListeningAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            waveAnimation = true
        }
    }

    private func loadSampleConversation() {
        messages = sampleMessages
    }

    private var sampleMessages: [VoiceMessage] {
        [
            VoiceMessage(id: UUID(), text: "How was your workout today?", isFromCoach: true, timestamp: Date()),
            VoiceMessage(id: UUID(), text: "Great! Finished all sets.", isFromCoach: false, timestamp: Date()),
            VoiceMessage(id: UUID(), text: "Excellent! Let's log your meal now.", isFromCoach: true, timestamp: Date())
        ]
    }
}

struct VoiceMessage: Identifiable {
    let id: UUID
    let text: String
    let isFromCoach: Bool
    let timestamp: Date
}

struct VoiceMessageBubble: View {
    let message: VoiceMessage
    let coach: Coach

    var body: some View {
        HStack {
            if message.isFromCoach {
                HStack(spacing: 12) {
                    // Coach avatar
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        )

                    Text(message.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(20, corners: [.topLeft, .topRight, .bottomRight])
                }
                Spacer()
            } else {
                Spacer()
                Text(message.text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(20, corners: [.topLeft, .topRight, .bottomLeft])
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

// Backdrop blur effect extension
extension View {
    func backdrop(blur radius: CGFloat) -> some View {
        self.background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: radius)
        )
    }
}

#Preview {
    OnboardingCompleteView(coach: Coach.allCoaches[0])
}
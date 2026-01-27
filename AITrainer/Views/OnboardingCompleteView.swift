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
            TrainerMainView(coach: coach)
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

// Main trainer interface based on UI mockups
struct TrainerMainView: View {
    let coach: Coach
    @State private var currentTime = Date()
    @State private var showVoiceChat = false
    @State private var caloriesConsumed = 1200
    @State private var caloriesGoal = 2100
    @State private var showingWorkoutDetail = false

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ZStack {
                // Immersive coach background
                LinearGradient(
                    colors: [
                        Color(coach.primaryColor).opacity(0.4),
                        Color(coach.secondaryColor).opacity(0.2),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header with greeting and coach
                        headerView

                        // Today's plan cards
                        planCardsSection

                        // Calorie balance section
                        calorieBalanceSection

                        // Quick actions
                        quickActionsSection

                        Spacer(minLength: 100)
                    }
                }

                // Floating voice chat button
                voiceChatButton
            }
        }
        .navigationBarHidden(true)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .sheet(isPresented: $showVoiceChat) {
            VoiceChatView(coach: coach)
        }
    }

    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(getGreeting())
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    Text("Ready for today's challenge?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                // Coach avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(coach.primaryColor).opacity(0.8),
                                    Color(coach.secondaryColor).opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
        }
    }

    private var planCardsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Today's Plan")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Morning workout card
                    WorkoutCard(
                        title: "Morning Power",
                        duration: "25 min",
                        type: "HIIT",
                        difficulty: "Medium",
                        coach: coach,
                        isCompleted: false
                    ) {
                        showingWorkoutDetail = true
                    }

                    // Afternoon activity
                    WorkoutCard(
                        title: "Mindful Movement",
                        duration: "15 min",
                        type: "Yoga",
                        difficulty: "Easy",
                        coach: coach,
                        isCompleted: true
                    ) {
                        showingWorkoutDetail = true
                    }

                    // Evening routine
                    WorkoutCard(
                        title: "Evening Stretch",
                        duration: "10 min",
                        type: "Mobility",
                        difficulty: "Easy",
                        coach: coach,
                        isCompleted: false
                    ) {
                        showingWorkoutDetail = true
                    }

                    Spacer().frame(width: 8)
                }
                .padding(.leading, 24)
            }
        }
    }

    private var calorieBalanceSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Energy Balance")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            // Calorie balance card
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Calories Today")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        Text("\(caloriesConsumed)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)

                        Text("of \(caloriesGoal)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 8)
                            .frame(width: 80, height: 80)

                        Circle()
                            .trim(from: 0, to: CGFloat(caloriesConsumed) / CGFloat(caloriesGoal))
                            .stroke(
                                LinearGradient(
                                    colors: [Color(coach.primaryColor), Color(coach.secondaryColor)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int((Double(caloriesConsumed) / Double(caloriesGoal)) * 100))%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Quick stats
                HStack(spacing: 32) {
                    TrainerStatItem(title: "Protein", value: "45g", color: .cyan)
                    TrainerStatItem(title: "Carbs", value: "120g", color: .orange)
                    TrainerStatItem(title: "Fat", value: "35g", color: .purple)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.3))
                    .backdrop(blur: 20)
            )
            .padding(.horizontal, 24)
        }
    }

    private var quickActionsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Actions")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                QuickActionCard(
                    icon: "heart.fill",
                    title: "Track Workout",
                    color: .red
                ) { }

                QuickActionCard(
                    icon: "fork.knife",
                    title: "Log Meal",
                    color: .green
                ) { }

                QuickActionCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Progress",
                    color: .blue
                ) { }

                QuickActionCard(
                    icon: "gearshape.fill",
                    title: "Settings",
                    color: .gray
                ) { }
            }
            .padding(.horizontal, 24)
        }
    }

    private var voiceChatButton: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button(action: {
                    showVoiceChat = true
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(coach.primaryColor),
                                        Color(coach.secondaryColor)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .shadow(color: Color(coach.primaryColor).opacity(0.3), radius: 20, x: 0, y: 8)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
                .padding(.trailing, 24)
                .padding(.bottom, 40)
            }
        }
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

// Supporting views
struct WorkoutCard: View {
    let title: String
    let duration: String
    let type: String
    let difficulty: String
    let coach: Coach
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                Text(type)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(coach.primaryColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(coach.primaryColor).opacity(0.2))
                    .cornerRadius(8)

                HStack {
                    Text(duration)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()

                    Text(difficulty)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(16)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(isCompleted ? 0.2 : 0.4))
                    .backdrop(blur: 20)
            )
        }
    }
}

private struct TrainerStatItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .backdrop(blur: 20)
            )
        }
    }
}

// Placeholder for voice chat
struct VoiceChatView: View {
    let coach: Coach

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Text("Voice Chat with \(coach.name)")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()

                Text("Voice recognition coming soon...")
                    .foregroundColor(.gray)
            }
        }
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
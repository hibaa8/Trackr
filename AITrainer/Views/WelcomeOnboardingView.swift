import SwiftUI

enum OnboardingFlow {
    case intro
    case ashley
    case meetCoach(Coach)
    case browseCoaches
}

struct WelcomeOnboardingView: View {
    @State private var flow: OnboardingFlow = .intro
    @State private var contentOpacity = 0.0
    @State private var buttonOffset = 50.0

    var body: some View {
        switch flow {
        case .ashley:
            AshleyConversationView(
                onMeetCoach: { coach in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flow = .meetCoach(coach)
                    }
                },
                onBrowseAll: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flow = .browseCoaches
                    }
                }
            )
        case .meetCoach(let coach):
            MeetCoachFlowView(coach: coach) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    flow = .browseCoaches
                }
            }
        case .browseCoaches:
            CoachSelectionView()
        case .intro:
            ZStack {
                // Dark gradient background with blue accent
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.15, blue: 0.35),
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Main Content
                    VStack(spacing: 32) {
                        // Title Section
                        VStack(spacing: 16) {
                            Text("Choose Your Own\nAI Fitness Coach")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text("Personalized training, real results")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }

                        // Feature List
                        VStack(spacing: 24) {
                            FeatureRow(
                                icon: "brain",
                                title: "AI-Powered Coaching",
                                description: "Adaptive workouts that learn and grow with you"
                            )

                            FeatureRow(
                                icon: "mic.fill",
                                title: "Voice-First Experience",
                                description: "Natural conversations for seamless guidance"
                            )

                            FeatureRow(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Track Your Progress",
                                description: "Real-time insights and personalized feedback"
                            )
                        }
                    }
                    .opacity(contentOpacity)
                    .padding(.horizontal, 24)

                    Spacer()

                    // Get Started Button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            flow = .ashley
                        }
                    }) {
                        Text("Get Started")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }
                    .offset(y: buttonOffset)
                    .opacity(contentOpacity)
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
        withAnimation(.easeOut(duration: 0.8)) {
            contentOpacity = 1.0
            buttonOffset = 0.0
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blue)
            }

            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
    }
}

#Preview {
    WelcomeOnboardingView()
        .environmentObject(AppState())
        .environmentObject(AuthenticationManager())
}
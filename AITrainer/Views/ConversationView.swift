import SwiftUI

struct ConversationView: View {
    let coach: Coach
    @State private var currentQuestionIndex = 0
    @State private var messages: [OnboardingChatMessage] = []
    @State private var userInput = ""
    @State private var showCompletion = false
    @State private var quickReplies: [String] = []

    private let questions = [
        OnboardingQuestion(
            id: "weight",
            text: "What's your current weight?",
            quickReplies: []
        ),
        OnboardingQuestion(
            id: "goal",
            text: "Great! And what's your fitness goal?",
            quickReplies: ["Lose Weight", "Build Muscle", "Get Fit"]
        ),
        OnboardingQuestion(
            id: "experience",
            text: "How would you describe your fitness experience?",
            quickReplies: ["Beginner", "Intermediate", "Advanced"]
        )
    ]

    var body: some View {
        if showCompletion {
            OnboardingCompleteView(coach: coach)
        } else {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress indicator
                    VStack(spacing: 16) {
                        HStack {
                            ForEach(0..<questions.count, id: \.self) { index in
                                Circle()
                                    .fill(index <= currentQuestionIndex ? Color.white : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.top, 60)

                        Text("\(currentQuestionIndex + 1)/\(questions.count) questions")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }

                    // Chat messages
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                if message.isFromCoach {
                                    CoachMessageView(message: message, coach: coach)
                                } else {
                                    UserMessageView(message: message)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }

                    Spacer()

                    // Quick replies
                    if !quickReplies.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(quickReplies, id: \.self) { reply in
                                    Button(action: {
                                        sendMessage(reply)
                                    }) {
                                        Text(reply)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .stroke(Color.blue, lineWidth: 1)
                                            )
                                    }
                                }
                                Spacer().frame(width: 20)
                            }
                            .padding(.leading, 20)
                        }
                        .padding(.bottom, 16)
                    }

                    // Input area
                    HStack(spacing: 12) {
                        TextField("Or type your answer...", text: $userInput)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            )

                        Button(action: {
                            if !userInput.isEmpty {
                                sendMessage(userInput)
                                userInput = ""
                            }
                        }) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(userInput.isEmpty ? .gray : Color(coach.primaryColor))
                        }
                        .disabled(userInput.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .onAppear {
                startConversation()
            }
        }
    }

    private func startConversation() {
        // Add initial coach message
        let welcomeMessage = OnboardingChatMessage(
            id: UUID().uuidString,
            text: questions[0].text,
            isFromCoach: true,
            timestamp: Date()
        )
        messages.append(welcomeMessage)
        quickReplies = questions[0].quickReplies
    }

    private func sendMessage(_ text: String) {
        // Add user message
        let userMessage = OnboardingChatMessage(
            id: UUID().uuidString,
            text: text,
            isFromCoach: false,
            timestamp: Date()
        )
        messages.append(userMessage)

        // Move to next question or complete
        currentQuestionIndex += 1

        if currentQuestionIndex < questions.count {
            // Add next coach question with delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let nextQuestion = OnboardingChatMessage(
                    id: UUID().uuidString,
                    text: questions[currentQuestionIndex].text,
                    isFromCoach: true,
                    timestamp: Date()
                )
                messages.append(nextQuestion)
                quickReplies = questions[currentQuestionIndex].quickReplies
            }
        } else {
            // Complete onboarding
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showCompletion = true
                }
            }
        }
    }
}

struct OnboardingQuestion {
    let id: String
    let text: String
    let quickReplies: [String]
}

struct OnboardingChatMessage: Identifiable {
    let id: String
    let text: String
    let isFromCoach: Bool
    let timestamp: Date
}

struct CoachMessageView: View {
    let message: OnboardingChatMessage
    let coach: Coach

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Coach avatar
            ZStack {
                Circle()
                    .fill(Color(coach.primaryColor).opacity(0.8))
                    .frame(width: 32, height: 32)

                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(coach.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)

                Text(message.text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color(coach.primaryColor).opacity(0.9)
                    )
                    .cornerRadius(16, corners: [.topLeft, .topRight, .bottomRight])
            }

            Spacer()
        }
    }
}

struct UserMessageView: View {
    let message: OnboardingChatMessage

    var body: some View {
        HStack {
            Spacer()

            Text(message.text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(16, corners: [.topLeft, .topRight, .bottomLeft])
        }
    }
}

#Preview {
    ConversationView(coach: Coach.allCoaches[0])
}
import SwiftUI

struct CoachView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var backendConnector: FrontendBackendConnector
    @State private var messageText = ""
    @State private var isTyping = false

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

                VStack(spacing: 0) {
                    // Modern header with AI coach avatar
                    modernHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    // Messages with enhanced scrolling
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                // Welcome message when empty
                                if appState.chatMessages.isEmpty {
                                    welcomeSection
                                        .padding(.top, 20)
                                }

                                ForEach(appState.chatMessages) { message in
                                    EnhancedMessageBubble(message: message)
                                        .id(message.id)
                                }

                                if isTyping {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                        }
                        .background(Color.white.opacity(0.95))
                        .cornerRadius(24)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .onChange(of: appState.chatMessages.count) { _ in
                            if let lastMessage = appState.chatMessages.last {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: isTyping) { _ in
                            if isTyping {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    proxy.scrollTo("typing", anchor: .bottom)
                                }
                            }
                        }
                    }

                    // Enhanced input area
                    modernInputSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .padding(.top, 12)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            backendConnector.loadCoachSuggestion { _ in }
        }
    }
    
    // MARK: - Header Section

    private var modernHeader: some View {
        HStack(spacing: 16) {
            // AI Coach Avatar with stunning design
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
                            startRadius: 20,
                            endRadius: 50
                        )
                    )
                    .frame(width: 80, height: 80)
                    .blur(radius: 12)

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
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.8), Color.white.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )

                // Robot emoji with animation
                Text("🤖")
                    .font(.system(size: 28))
                    .scaleEffect(isTyping ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isTyping)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Vaylow Fitness")
                    .font(.headlineLarge)
                    .foregroundColor(.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isTyping ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isTyping)

                    Text(isTyping ? "Thinking..." : "Online")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Settings button
            ModernIconButton(
                icon: "gearshape.fill",
                size: 44,
                gradient: LinearGradient(
                    colors: [Color.textSecondary.opacity(0.3), Color.textSecondary.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ) {
                // Settings action
            }
        }
    }

    // MARK: - Welcome Section

    private var welcomeSection: some View {
        ModernCard {
            VStack(spacing: 24) {
                // Welcome message
                VStack(spacing: 12) {
                    Text("👋 Welcome to Vaylow Fitness!")
                        .font(.headlineLarge)
                        .foregroundColor(.textPrimary)

                    Text("I'm here to help you achieve your fitness goals. Ask me anything about workouts, nutrition, or your progress!")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                if let suggestion = backendConnector.coachSuggestion {
                    ModernCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coach Suggestion")
                                .font(.headlineMedium)
                                .foregroundColor(.textPrimary)
                            Text(suggestion.suggestion_text)
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                }

                // Quick action buttons
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    QuickActionButton(
                        icon: "🏃‍♂️",
                        title: "Workout Tips",
                        color: .blue
                    ) {
                        messageText = "Give me a quick workout tip"
                    }

                    QuickActionButton(
                        icon: "🥗",
                        title: "Nutrition Advice",
                        color: .green
                    ) {
                        messageText = "Help me with my nutrition"
                    }

                    QuickActionButton(
                        icon: "📊",
                        title: "Check Progress",
                        color: .purple
                    ) {
                        messageText = "How am I doing with my goals?"
                    }

                    QuickActionButton(
                        icon: "💪",
                        title: "Motivation",
                        color: .orange
                    ) {
                        messageText = "I need some motivation!"
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Input Section

    private var modernInputSection: some View {
        ModernCard {
            HStack(spacing: 16) {
                // Message input field
                HStack(spacing: 12) {
                    TextField("Ask your Vaylow coach anything...", text: $messageText, axis: .vertical)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1...4)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .background(Color.backgroundGradientStart)
                        .cornerRadius(24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.textTertiary.opacity(0.2), lineWidth: 1)
                        )

                    // Send button with stunning design
                    Button(action: {
                        sendMessage()
                    }) {
                        ZStack {
                            // Background glow
                            Circle()
                                .fill(LinearGradient.fitnessGradient)
                                .frame(width: 56, height: 56)
                                .blur(radius: 8)
                                .opacity(messageText.isEmpty ? 0.3 : 0.8)

                            // Main button
                            Circle()
                                .fill(
                                    messageText.isEmpty ?
                                    LinearGradient(
                                        colors: [Color.textTertiary.opacity(0.3), Color.textTertiary.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient.fitnessGradient
                                )
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.6), Color.white.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )

                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(messageText.isEmpty ? .textSecondary : .white)
                        }
                    }
                    .disabled(messageText.isEmpty)
                    .scaleEffect(messageText.isEmpty ? 0.9 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: messageText.isEmpty)
                }
            }
            .padding(16)
        }
    }

    func sendMessage() {
        guard !messageText.isEmpty else { return }

        // Start typing animation
        isTyping = true

        appState.sendMessage(messageText)
        messageText = ""

        // Simulate AI response delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTyping = false
        }
    }
}

// MARK: - Enhanced Message Bubble

struct EnhancedMessageBubble: View {
    let message: WireframeChatMessage
    @State private var showTime = false

    var body: some View {
        HStack(spacing: 12) {
            if message.isFromUser {
                Spacer()
            } else {
                // AI avatar for coach messages
                aiAvatar
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 8) {
                // Message content
                Text(message.text)
                    .font(.bodyMedium)
                    .foregroundColor(message.isFromUser ? .white : .textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(messageBackground)
                    .clipShape(messageBubbleShape)
                    .overlay(
                        messageBubbleShape
                            .stroke(
                                message.isFromUser ? Color.clear : Color.textTertiary.opacity(0.1),
                                lineWidth: 1
                            )
                    )

                // Timestamp
                if showTime {
                    Text(timeString(from: message.timestamp))
                        .font(.captionMedium)
                        .foregroundColor(.textTertiary)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: 280, alignment: message.isFromUser ? .trailing : .leading)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showTime.toggle()
                }
            }

            if !message.isFromUser {
                Spacer()
            } else {
                // User avatar for user messages
                userAvatar
            }
        }
    }

    private var aiAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.fitnessGradientStart.opacity(0.8),
                            Color.fitnessGradientEnd.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)

            Text("🤖")
                .font(.system(size: 16))
        }
    }

    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.8),
                            Color.purple.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)

            Text("👤")
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
    }

    private var messageBackground: some View {
        Group {
            if message.isFromUser {
                LinearGradient.fitnessGradient
            } else {
                Color.white.opacity(0.8)
            }
        }
    }

    private var messageBubbleShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 20)
    }

    func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 24))

                Text(title)
                    .font(.captionLarge)
                    .foregroundColor(.textPrimary)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(color.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 12) {
            // AI avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.fitnessGradientStart.opacity(0.8),
                                Color.fitnessGradientEnd.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Text("🤖")
                    .font(.system(size: 16))
            }

            // Typing animation
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.textSecondary)
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                            .opacity(animationPhase == index ? 1.0 : 0.5)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.8))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.textTertiary.opacity(0.1), lineWidth: 1)
                )

                Spacer()
            }
        }
        .onAppear {
            startTypingAnimation()
        }
    }

    private func startTypingAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

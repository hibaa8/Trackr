//
//  AshleyConversationView.swift
//  AITrainer
//
//  Chat with Ashley (receptionist) during onboarding. Ashley collects info naturally
//  and recommends a coach. User can accept the recommendation or browse all coaches.
//

import SwiftUI
import Combine

struct AshleyConversationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    var onMeetCoach: (Coach) -> Void
    var onBrowseAll: () -> Void

    @State private var messages: [AshleyMessage] = []
    @State private var userInput = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var subscriptions = Set<AnyCancellable>()
    @State private var recommendedCoach: Coach?
    @State private var threadId: String?
    @State private var showInitialGreeting = true

    private let ashley = Receptionist.ashley

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Chat with Ashley")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 16)

                // Recommendation card (when Ashley recommends a coach)
                if let coach = recommendedCoach {
                    AshleyRecommendationCard(
                        coach: coach,
                        onMeetCoach: { onMeetCoach(coach) },
                        onBrowseAll: onBrowseAll
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                if message.isFromAshley {
                                    AshleyMessageView(message: message, receptionist: ashley)
                                } else {
                                    UserMessageBubble(text: message.text)
                                }
                            }
                            if let submitError = submitError {
                                Text(submitError)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }

                Spacer()

                // Input area (only when no recommendation yet)
                if recommendedCoach == nil {
                    HStack(spacing: 12) {
                        TextField("Type your message...", text: $userInput)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            )
                            .submitLabel(.send)

                        Button(action: sendMessage) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(userInput.isEmpty ? .gray : Color(ashley.primaryColor))
                        }
                        .disabled(userInput.isEmpty || isSubmitting)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            loadCoachesIfNeeded()
            if messages.isEmpty && showInitialGreeting {
                showInitialGreeting = false
                let greeting = AshleyMessage(
                    id: UUID().uuidString,
                    text: "Hey! I'm Ashley, your AI fitness receptionist. I'd love to learn a bit about you so I can match you with the perfect coach. What brings you here today?",
                    isFromAshley: true,
                    timestamp: Date()
                )
                messages.append(greeting)
            }
        }
    }

    private func loadCoachesIfNeeded() {
        guard appState.coaches.isEmpty else { return }
        APIService.shared.getCoaches()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { coaches in
                    appState.coaches = coaches
                }
            )
            .store(in: &subscriptions)
    }

    private func sendMessage() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let userId = authManager.effectiveUserId else { return }

        let userMsg = AshleyMessage(
            id: UUID().uuidString,
            text: text,
            isFromAshley: false,
            timestamp: Date()
        )
        messages.append(userMsg)
        userInput = ""
        submitError = nil
        isSubmitting = true

        let history: [[String: String]] = messages.dropLast().map { msg in
            [
                "role": msg.isFromAshley ? "assistant" : "user",
                "content": msg.text
            ]
        }

        APIService.shared.sendAshleyMessage(
            message: text,
            userId: userId,
            threadId: threadId,
            messagesHistory: history.isEmpty ? nil : history
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isSubmitting = false
                if case .failure(let error) = completion {
                    submitError = "Failed to send: \(error.localizedDescription)"
                }
            },
            receiveValue: { response in
                threadId = response.thread_id
                let ashleyMsg = AshleyMessage(
                    id: UUID().uuidString,
                    text: response.reply,
                    isFromAshley: true,
                    timestamp: Date()
                )
                messages.append(ashleyMsg)
                if let slug = response.coach_recommendation_slug,
                   let coach = appState.coaches.first(where: { $0.slug == slug }) {
                    recommendedCoach = coach
                }
            }
        )
        .store(in: &subscriptions)
    }
}

struct AshleyMessage: Identifiable {
    let id: String
    let text: String
    let isFromAshley: Bool
    let timestamp: Date
}

struct AshleyMessageView: View {
    let message: AshleyMessage
    let receptionist: Receptionist

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(receptionist.primaryColor).opacity(0.8))
                    .frame(width: 32, height: 32)
                if let url = receptionist.imageURL {
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

            VStack(alignment: .leading, spacing: 4) {
                Text(receptionist.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                Text(message.text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(receptionist.primaryColor).opacity(0.9))
                    .cornerRadius(16)
            }

            Spacer(minLength: 40)
        }
    }
}

struct UserMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(16)
        }
    }
}

struct AshleyRecommendationCard: View {
    let coach: Coach
    let onMeetCoach: () -> Void
    let onBrowseAll: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Ashley recommends \(coach.name)!")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 12) {
                Button(action: onMeetCoach) {
                    Text("Meet \(coach.name)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            LinearGradient(
                                colors: [Color(coach.primaryColor), Color(coach.secondaryColor)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }

                Button(action: onBrowseAll) {
                    Text("Browse All Coaches")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

/// Wrapper that shows CoachIntroVideoView, then CoachDetailView (which leads to ChatSetupView → ConversationView).
struct MeetCoachFlowView: View {
    let coach: Coach
    var onBackToBrowse: (() -> Void)?

    @State private var showDetail = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showDetail {
                CoachDetailView(
                    coach: coach,
                    onBack: onBackToBrowse
                )
            } else {
                CoachIntroVideoView(coach: coach) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDetail = true
                    }
                }
            }
        }
    }
}

#Preview {
    AshleyConversationView(
        onMeetCoach: { _ in },
        onBrowseAll: {}
    )
    .environmentObject(AppState())
    .environmentObject(AuthenticationManager())
}

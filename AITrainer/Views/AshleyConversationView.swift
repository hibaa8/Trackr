//
//  AshleyConversationView.swift
//  AITrainer
//
//  Ashley intro video first, then chat. Ashley collects info naturally
//  and recommends a coach. User can accept the recommendation or browse all coaches.
//

import SwiftUI
import Combine
import AVKit

struct AshleyConversationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    var onBrowseAll: () -> Void
    /// Optional shared completion handler used by parent to finish onboarding consistently.
    var onCoachChosen: ((Coach, [[String: String]]) -> Void)? = nil
    var onBackToIntro: (() -> Void)? = nil
    /// When true, skip the intro video and show the chat directly (e.g. when returning from "Choose Your Coach").
    var startWithChat: Bool = false
    /// Called when messages change, so parent can store history for complete-onboarding.
    var onMessagesUpdated: (([[String: String]]) -> Void)? = nil

    @State private var showVideoFirst: Bool

    init(
        onBrowseAll: @escaping () -> Void,
        onCoachChosen: ((Coach, [[String: String]]) -> Void)? = nil,
        onBackToIntro: (() -> Void)? = nil,
        startWithChat: Bool = false,
        onMessagesUpdated: (([[String: String]]) -> Void)? = nil
    ) {
        self.onBrowseAll = onBrowseAll
        self.onCoachChosen = onCoachChosen
        self.onBackToIntro = onBackToIntro
        self.startWithChat = startWithChat
        self.onMessagesUpdated = onMessagesUpdated
        _showVideoFirst = State(initialValue: !startWithChat)
    }

    @State private var messages: [AshleyMessage] = []
    @State private var coachToMeet: Coach?
    @State private var userInput = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var subscriptions = Set<AnyCancellable>()
    @State private var recommendedCoach: Coach?
    @State private var threadId: String?
    @State private var showInitialGreeting = true

    private let ashley = Receptionist.ashley

    var body: some View {
        Group {
            if showVideoFirst {
                AshleyIntroVideoView(
                    receptionist: ashley,
                    onBack: onBackToIntro,
                    onFinish: { withAnimation(.easeInOut(duration: 0.3)) { showVideoFirst = false } }
                )
            } else {
                chatView
            }
        }
    }

    private var chatView: some View {
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
                        onMeetCoach: { coachToMeet = coach },
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

                // Keep chat input available even after recommendation,
                // so user can continue talking with Ashley.
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
        .onChange(of: messages.count) { _, _ in
            onMessagesUpdated?(messagesHistoryForAPI())
        }
        .fullScreenCover(item: $coachToMeet) { coach in
            MeetCoachFlowView(
                coach: coach,
                showBackToAshley: true,
                onBack: { coachToMeet = nil },
                onChooseCoach: {
                    completeOnboardingWithCoach(coach)
                }
            )
        }
        .onAppear {
            loadCoachesIfNeeded()
            if messages.isEmpty && showInitialGreeting {
                showInitialGreeting = false
                let greeting = AshleyMessage(
                    id: UUID().uuidString,
                    text: "Hey! I'm Ashley, your Vaylo Fitness guide. I'd love to learn a bit about you so I can match you with the perfect coach. What brings you here today?",
                    isFromAshley: true,
                    timestamp: Date()
                )
                messages.append(greeting)
            }
            onMessagesUpdated?(messagesHistoryForAPI())
        }
    }

    private func messagesHistoryForAPI() -> [[String: String]] {
        messages.map { msg in
            [
                "role": msg.isFromAshley ? "assistant" : "user",
                "content": msg.text
            ]
        }
    }

    private func completeOnboardingWithCoach(_ coach: Coach) {
        let history = messagesHistoryForAPI()
        coachToMeet = nil
        if let onCoachChosen {
            onCoachChosen(coach, history)
            return
        }

        guard let userId = authManager.effectiveUserId else {
            submitError = "Please sign in to continue."
            return
        }
        submitError = nil

        APIService.shared.completeAshleyOnboarding(
            userId: userId,
            coachId: coach.id,
            messagesHistory: history
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    submitError = "Failed to complete setup: \(error.localizedDescription)"
                }
            },
            receiveValue: { _ in
                appState.setSelectedCoach(coach)
                authManager.completeOnboarding()
            }
        )
        .store(in: &subscriptions)
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

/// Ashley's intro video shown before the chat.
struct AshleyIntroVideoView: View {
    let receptionist: Receptionist
    var onBack: (() -> Void)? = nil
    let onFinish: () -> Void
    @State private var player = AVPlayer()
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let url = receptionist.videoURL {
                AshleyFullScreenVideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        let item = AVPlayerItem(url: url)
                        player.replaceCurrentItem(with: item)
                        player.play()
                        endObserver = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: item,
                            queue: .main
                        ) { _ in
                            finishPlayback()
                        }
                    }
            } else {
                VStack(spacing: 24) {
                    if let imageURL = receptionist.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                    }
                    Text("Hey! I'm \(receptionist.name)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text(receptionist.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
            }

            HStack {
                if let onBack = onBack {
                    Button(action: {
                        player.pause()
                        onBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 50)
                    .padding(.leading, 20)
                }
                Spacer()
                Button(action: finishPlayback) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                }
                .padding(.top, 50)
                .padding(.trailing, 20)
            }
        }
        .onDisappear {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            player.pause()
        }
    }

    private func finishPlayback() {
        player.pause()
        onFinish()
    }
}

private struct AshleyFullScreenVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.videoGravity = .resizeAspectFill
        uiViewController.showsPlaybackControls = false
    }
}

/// Wrapper that shows CoachIntroVideoView, then CoachDetailView (which leads to ChatSetupView → ConversationView).
/// When showBackToAshley is true, shows a back arrow that returns to Ashley via onBack.
struct MeetCoachFlowView: View {
    let coach: Coach
    var showBackToAshley: Bool = false
    var onBack: (() -> Void)?
    var onChooseCoach: (() -> Void)? = nil

    @State private var showDetail = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showDetail {
                CoachDetailView(
                    coach: coach,
                    onBack: showBackToAshley ? onBack : nil,
                    onChoose: onChooseCoach
                )
            } else {
                CoachIntroVideoView(
                    coach: coach,
                    onBack: showBackToAshley ? onBack : nil,
                    dismissOnFinish: !showBackToAshley
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDetail = true
                    }
                }
            }
        }
    }
}

#Preview {
    AshleyConversationView(onBrowseAll: {})
    .environmentObject(AppState())
    .environmentObject(AuthenticationManager())
}

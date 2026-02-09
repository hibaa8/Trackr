import SwiftUI
import UIKit
import Combine

struct ConversationView: View {
    let coach: Coach
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var currentQuestionIndex = 0
    @State private var messages: [OnboardingChatMessage] = []
    @State private var userInput = ""
    @State private var quickReplies: [String] = []
    @State private var answers: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var subscriptions = Set<AnyCancellable>()
    @State private var lastPersonaPhrase: String?
    
    private let questions = [
        OnboardingQuestion(
            id: "weight",
            text: "What's your current weight?",
            quickReplies: []
        ),
        OnboardingQuestion(
            id: "height",
            text: "What's your height?",
            quickReplies: []
        ),
        OnboardingQuestion(
            id: "age",
            text: "How old are you?",
            quickReplies: []
        ),
        OnboardingQuestion(
            id: "goal",
            text: "Great! And what's your fitness goal?",
            quickReplies: ["Lose Weight", "Build Muscle", "Get Fit"]
        ),
        OnboardingQuestion(
            id: "target_weight",
            text: "Do you have a target weight in mind?",
            quickReplies: []
        ),
        OnboardingQuestion(
            id: "timeframe",
            text: "What timeline feels realistic for your goal?",
            quickReplies: ["4 weeks", "8 weeks", "12 weeks", "No rush"]
        )
    ]
    
    var body: some View {
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                if message.isFromCoach {
                                    CoachMessageView(message: message, coach: coach)
                                } else {
                                    UserMessageView(message: message)
                                }
                            }
                            if let submitError = submitError {
                                Text(submitError)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
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
                    .disabled(userInput.isEmpty || isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            startConversation()
        }
    }
    
    private func startConversation() {
        let introText = coachIntroMessage()
        let introMessage = OnboardingChatMessage(
            id: UUID().uuidString,
            text: introText,
            isFromCoach: true,
            timestamp: Date()
        )
        let firstQuestion = OnboardingChatMessage(
            id: UUID().uuidString,
            text: questions[0].text,
            isFromCoach: true,
            timestamp: Date()
        )
        messages.append(introMessage)
        messages.append(firstQuestion)
        quickReplies = questions[0].quickReplies
    }
    
    private func sendMessage(_ text: String) {
        guard currentQuestionIndex < questions.count else {
            submitError = "Onboarding is already complete."
            return
        }
        // Add user message
        let userMessage = OnboardingChatMessage(
            id: UUID().uuidString,
            text: text,
            isFromCoach: false,
            timestamp: Date()
        )
        messages.append(userMessage)
        submitError = nil
        answers[questions[currentQuestionIndex].id] = text
        
        // Move to next question or complete
        currentQuestionIndex += 1
        
        if currentQuestionIndex < questions.count {
            // Add next coach question with delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let response = coachResponse(for: text)
                if !response.isEmpty {
                    let responseMessage = OnboardingChatMessage(
                        id: UUID().uuidString,
                        text: response,
                        isFromCoach: true,
                        timestamp: Date()
                    )
                    messages.append(responseMessage)
                }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                submitOnboarding()
            }
        }
    }
    
    private func submitOnboarding() {
        isSubmitting = true
        let payload = buildOnboardingPayload()
        let userData = buildUserData(from: payload)

        APIService.shared.completeOnboarding(payload: payload)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        submitError = "Failed to save onboarding data: \(error)"
                        isSubmitting = false
                    }
                },
                receiveValue: { response in
                    if response.ok == true {
                        appState.completeOnboarding(with: userData)
                        authManager.completeOnboarding()
                    } else {
                        submitError = response.error ?? "Unable to finish onboarding."
                    }
                    isSubmitting = false
                }
            )
            .store(in: &subscriptions)
    }
    
    private func coachIntroMessage() -> String {
        let phrase = pickPersonaPhrase() ?? "Let's get to work."
        return "Hey, I’m \(coach.name), \(coach.title). \(coach.philosophy) \(phrase)"
    }
    
    private func coachResponse(for answer: String) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let phrase = pickPersonaPhrase()
        let phraseSuffix = phrase.map { " \($0)" } ?? ""
        switch coach.speakingStyle.lowercased() {
        case let style where style.contains("military"):
            return "Copy that.\(phraseSuffix)"
        case let style where style.contains("gentle"):
            return "Thank you for sharing.\(phraseSuffix)"
        case let style where style.contains("upbeat"):
            return "Love the energy!\(phraseSuffix)"
        default:
            return "Got it.\(phraseSuffix)"
        }
    }
    
    private func pickPersonaPhrase() -> String? {
        let phrases = coach.commonPhrases
        guard !phrases.isEmpty else { return nil }
        let usePhrase = Double.random(in: 0...1) < 0.85
        guard usePhrase else { return nil }
        let filtered = phrases.filter { $0 != lastPersonaPhrase }
        let next = (filtered.randomElement() ?? phrases.randomElement())
        if let next {
            lastPersonaPhrase = next
        }
        return next
    }
    
    private func buildOnboardingPayload() -> OnboardingCompletePayload {
        let weightKg = parseWeightKg(from: answers["weight"])
        let heightCm = parseHeightCm(from: answers["height"])
        let ageInt = parseInt(from: answers["age"])
        let goalType = mapGoalType(from: answers["goal"])
        let activity = mapActivityLevel(from: answers["activity"])
        let targetWeightKg = parseWeightKg(from: answers["target_weight"])
        let timeframeWeeks = parseTimeframeWeeks(from: answers["timeframe"])
        let weeklyDelta = computeWeeklyChangeKg(
            currentWeight: weightKg,
            targetWeight: targetWeightKg,
            timeframeWeeks: timeframeWeeks
        )
        
        return OnboardingCompletePayload(
            user_id: authManager.demoUserId,
            goal_type: goalType,
            target_weight_kg: targetWeightKg,
            weekly_weight_change_kg: weeklyDelta,
            activity_level: activity,
            storyline: coach.philosophy,
            trainer: coach.name,
            personality: coach.personality,
            voice: coach.speakingStyle,
            timeframe_weeks: timeframeWeeks,
            current_weight_kg: weightKg,
            height_cm: heightCm,
            age: ageInt,
            fitness_background: answers["experience"]
        )
    }
    
    private func buildUserData(from payload: OnboardingCompletePayload) -> UserData {
        let weightLbs = payload.current_weight_kg.map { $0 * 2.20462 }
        let heightIn = payload.height_cm.map { $0 / 2.54 }
        let ageText = payload.age.map { String($0) } ?? ""
        let weightText = weightLbs.map { String(format: "%.0f", $0) } ?? ""
        let heightText = heightIn.map { String(format: "%.0f", $0) } ?? ""
        let goalWeightText = payload.target_weight_kg.map { String(format: "%.0f", $0 * 2.20462) } ?? ""
        
        let activity = payload.activity_level ?? "moderate"
        let calorieTarget = estimateCalories(
            age: payload.age ?? 0,
            heightCm: payload.height_cm ?? 0,
            weightKg: payload.current_weight_kg ?? 0,
            activityLevel: activity
        )
        
        return UserData(
            displayName: "",
            age: ageText,
            height: heightText,
            weight: weightText,
            goalWeight: goalWeightText,
            activityLevel: activity,
            dietPreference: answers["dietary"] ?? "",
            workoutPreference: answers["workout_type"] ?? "",
            calorieTarget: calorieTarget
        )
    }
    
    private func estimateCalories(age: Int, heightCm: Double, weightKg: Double, activityLevel: String) -> Int {
        guard age > 0, heightCm > 0, weightKg > 0 else { return 2000 }
        let bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + 5
        let multiplier: Double
        switch activityLevel {
        case "sedentary":
            multiplier = 1.2
        case "light":
            multiplier = 1.375
        case "very":
            multiplier = 1.725
        case "extra":
            multiplier = 1.9
        default:
            multiplier = 1.55
        }
        return Int(bmr * multiplier)
    }
    
    private func parseWeightKg(from text: String?) -> Double? {
        guard let value = parseDouble(from: text) else { return nil }
        let lower = text?.lowercased() ?? ""
        if lower.contains("kg") {
            return value
        }
        if lower.contains("lb") {
            return value * 0.453592
        }
        return value * 0.453592
    }
    
    private func parseHeightCm(from text: String?) -> Double? {
        guard let value = parseDouble(from: text) else { return nil }
        let lower = text?.lowercased() ?? ""
        if lower.contains("cm") {
            return value
        }
        if lower.contains("m") && value < 3 {
            return value * 100
        }
        return value * 2.54
    }
    
    private func parseTimeframeWeeks(from text: String?) -> Int? {
        guard let value = parseInt(from: text) else { return nil }
        return value
    }
    
    private func computeWeeklyChangeKg(currentWeight: Double?, targetWeight: Double?, timeframeWeeks: Int?) -> Double? {
        guard let currentWeight, let targetWeight, let timeframeWeeks, timeframeWeeks > 0 else {
            return nil
        }
        return (targetWeight - currentWeight) / Double(timeframeWeeks)
    }
    
    private func mapGoalType(from text: String?) -> String? {
        let lower = text?.lowercased() ?? ""
        if lower.contains("lose") {
            return "lose"
        }
        if lower.contains("build") || lower.contains("gain") {
            return "gain"
        }
        if lower.contains("fit") || lower.contains("maintain") {
            return "maintain"
        }
        return nil
    }
    
    private func mapActivityLevel(from text: String?) -> String? {
        let lower = text?.lowercased() ?? ""
        if lower.contains("sedentary") {
            return "sedentary"
        }
        if lower.contains("light") {
            return "light"
        }
        if lower.contains("very") {
            return "very"
        }
        if lower.contains("extra") || lower.contains("6") {
            return "extra"
        }
        if lower.contains("moderate") {
            return "moderate"
        }
        return nil
    }
    
    private func parseInt(from text: String?) -> Int? {
        guard let value = parseDouble(from: text) else { return nil }
        return Int(value)
    }
    
    private func parseDouble(from text: String?) -> Double? {
        guard let text else { return nil }
        let filtered = text
            .replacingOccurrences(of: ",", with: " ")
            .split { !$0.isNumber && $0 != "." }
            .first
        return filtered.flatMap { Double($0) }
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
        
        private func coachAvatar() -> Image? {
            guard let url = coach.imageURL,
                  let uiImage = UIImage(contentsOfFile: url.path) else {
                return nil
            }
            return Image(uiImage: uiImage)
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
    
}

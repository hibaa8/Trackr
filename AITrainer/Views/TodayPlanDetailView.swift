import SwiftUI
import Combine
import AVFoundation

struct TodayPlanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var selectedDate = Date()
    @State private var isLoading = false
    @State private var dayPlan: PlanDayResponse?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var plansByDate: [String: PlanDayResponse] = [:]
    @State private var showFullDetails = true
    @State private var showLogWorkout = false
    @State private var showGuidedWorkout = false
    @State private var guidedExercises: [GuidedExercise] = []
    @State private var guidedWorkoutTitle = "Workout"
    @State private var resumeCandidate: GuidedWorkoutSessionState?
    @State private var pendingStartPayload: (title: String, exercises: [GuidedExercise], dayKey: String)?
    @State private var showResumePrompt = false
    @AppStorage("guidedWorkoutSessionData") private var savedWorkoutSessionData = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                dateSelector
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        let dateKey = isoDateFormatter.string(from: selectedDate)
                        let plan = plansByDate[dateKey]
                        let workoutText = (plan?.workout_plan ?? "Workout").trimmingCharacters(in: .whitespacesAndNewlines)
                        let calorieText = plan?.calorie_target ?? 0
                        let formattedDetails = formatWorkoutDetails(workoutText)
                        planCard(
                            title: workoutTitle(from: workoutText, date: selectedDate),
                            subtitle: calorieText > 0 ? "\(calorieText) kcal target" : "Workout",
                            details: formattedDetails.isEmpty ? ["🏋️ Workout"] : formattedDetails,
                            primaryButton: (plan?.rest_day == true ? nil : "Start Workout"),
                            secondaryButton: "Log Workout"
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .onAppear {
            selectedDate = appState.selectedDate
            loadSelectedPlan()
        }
        .onChange(of: selectedDate) { newValue in
            loadSelectedPlan()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            loadSelectedPlan()
        }
        .sheet(isPresented: $showLogWorkout) {
            VoiceActiveView(
                coach: appState.selectedCoach ?? appState.coaches.first ?? Coach.placeholder,
                initialPrompt: "I want to log a workout. Please ask me for the exercises, sets/reps, time, and any details needed, then log it."
            )
        }
        .fullScreenCover(isPresented: $showGuidedWorkout) {
            GuidedWorkoutPlayerView(
                coach: appState.selectedCoach ?? appState.coaches.first ?? Coach.placeholder,
                userId: authManager.effectiveUserId,
                dayKey: isoDateFormatter.string(from: selectedDate),
                workoutTitle: guidedWorkoutTitle,
                exercises: guidedExercises,
                resumeState: resumeCandidate,
                onSaveState: { state in
                    if let state {
                        persistGuidedState(state)
                    } else {
                        savedWorkoutSessionData = ""
                    }
                },
                onWorkoutCompleted: {
                    savedWorkoutSessionData = ""
                    NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
                    loadSelectedPlan()
                }
            )
        }
        .alert("Resume Workout?", isPresented: $showResumePrompt) {
            Button("Resume") {
                if let payload = pendingStartPayload {
                    guidedWorkoutTitle = payload.title
                    guidedExercises = payload.exercises
                    showGuidedWorkout = true
                }
            }
            Button("Start Over", role: .destructive) {
                resumeCandidate = nil
                if let payload = pendingStartPayload {
                    guidedWorkoutTitle = payload.title
                    guidedExercises = payload.exercises
                    showGuidedWorkout = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have a paused workout for today. Resume where you left off?")
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }

            Spacer()

            Text("Today's Plan")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var dateSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visibleDates, id: \.self) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    VStack(spacing: 4) {
                        Text(monthDayFormatter.string(from: date))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                        if Calendar.current.isDateInToday(date) {
                            Text("Today")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.blue : Color.clear)
                    )
                    .onTapGesture {
                        selectedDate = date
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func planCard(
        title: String,
        subtitle: String,
        details: [String],
        primaryButton: String? = nil,
        secondaryButton: String? = nil
    ) -> some View {
        let visibleItems = details

        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))

            if !visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.blue.opacity(0.8))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(item)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.82))
                                .lineLimit(showFullDetails ? nil : 2)
                        }
                    }
                }
            } else {
                Text("Details will appear once your plan is ready.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            if let primaryButton = primaryButton {
                Button(action: { startGuidedWorkout(from: details, title: title) }) {
                    Text(primaryButton)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }

            if let secondaryButton = secondaryButton {
                Button(action: { showLogWorkout = true }) {
                    Text(secondaryButton)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.08, green: 0.09, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.95)
        )
        .cornerRadius(16)
        .frame(minHeight: 220)
    }

    private var visibleDates: [Date] {
        let base = Calendar.current.startOfDay(for: selectedDate)
        return (-2...4).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: base) }
    }

    private var monthDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }

    private var isoDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func loadSelectedPlan() {
        guard let userId = authManager.effectiveUserId else {
            return
        }
        isLoading = true
        let date = selectedDate
        APIService.shared.getTodayPlan(date: date, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        print("Failed to load plan: \(error)")
                    }
                },
                receiveValue: { plan in
                    let key = self.isoDateFormatter.string(from: date)
                    self.plansByDate[key] = plan
                }
            )
            .store(in: &cancellables)
    }

    private func workoutTitle(from text: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayLabel = formatter.string(from: date)
        return dayLabel
    }

    private func formatWorkoutDetails(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var rawLines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if rawLines.count == 1 {
            let sentenceLines = rawLines[0]
                .split(separator: ".")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            rawLines = sentenceLines
            if let first = rawLines.first, first.contains(":") {
                let parts = first.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let listItems = parts[1]
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    rawLines.removeFirst()
                    rawLines.insert(contentsOf: listItems, at: 0)
                }
            }
        }
        return rawLines.map { line in
            line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^\s*[•\-\*]\s*"#, with: "", options: .regularExpression)
        }
    }

    private func startGuidedWorkout(from details: [String], title: String) {
        let parsed = parseGuidedExercises(from: details)
        guard !parsed.isEmpty else {
            showLogWorkout = true
            return
        }
        let dayKey = isoDateFormatter.string(from: selectedDate)
        pendingStartPayload = (title: title, exercises: parsed, dayKey: dayKey)
        if let resume = decodeSavedGuidedState(), resume.dayKey == dayKey {
            resumeCandidate = resume
            showResumePrompt = true
        } else {
            resumeCandidate = nil
            guidedWorkoutTitle = title
            guidedExercises = parsed
            showGuidedWorkout = true
        }
    }

    private func parseGuidedExercises(from details: [String]) -> [GuidedExercise] {
        var output: [GuidedExercise] = []
        for item in details {
            let raw = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            if raw.lowercased().contains("warm-up") || raw.lowercased().contains("progression") {
                continue
            }
            var name = raw
            var setsReps = "3x8-12"
            var rpe = "RPE7"
            let pattern = #"^([A-Za-z0-9 \-/\+]+)\s+(\d+x[0-9\-–/]+)\s*@?(RPE\s*\d+(-\d+)?)?"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let ns = raw as NSString
                let range = NSRange(location: 0, length: ns.length)
                if let match = regex.firstMatch(in: raw, options: [], range: range), match.numberOfRanges >= 3 {
                    name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    setsReps = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: "–", with: "-")
                    if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                        rpe = ns.substring(with: match.range(at: 3)).replacingOccurrences(of: " ", with: "")
                    }
                }
            }
            output.append(GuidedExercise(name: name, setsReps: setsReps, rpe: rpe))
        }
        if output.isEmpty {
            output = details.map { GuidedExercise(name: $0, setsReps: "3x8-12", rpe: "RPE7") }
        }
        return output
    }

    private func persistGuidedState(_ state: GuidedWorkoutSessionState) {
        guard let data = try? JSONEncoder().encode(state),
              let encoded = String(data: data, encoding: .utf8) else { return }
        savedWorkoutSessionData = encoded
    }

    private func decodeSavedGuidedState() -> GuidedWorkoutSessionState? {
        guard let data = savedWorkoutSessionData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GuidedWorkoutSessionState.self, from: data) else {
            return nil
        }
        return decoded
    }
}

private struct GuidedExercise: Codable, Hashable {
    let name: String
    let setsReps: String
    let rpe: String
}

private struct GuidedWorkoutSessionState: Codable {
    let dayKey: String
    let workoutTitle: String
    let exercises: [GuidedExercise]
    let currentIndex: Int
    let elapsedSeconds: Int
    let isPaused: Bool
}

private struct GuidedWorkoutPlayerView: View {
    let coach: Coach
    let userId: Int?
    let dayKey: String
    let workoutTitle: String
    let exercises: [GuidedExercise]
    let resumeState: GuidedWorkoutSessionState?
    let onSaveState: (GuidedWorkoutSessionState?) -> Void
    let onWorkoutCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var elapsedSeconds = 0
    @State private var isPaused = false
    @State private var isPreparing = true
    @State private var isLogging = false
    @State private var videosByIndex: [Int: WorkoutVideo] = [:]
    @State private var cancellables = Set<AnyCancellable>()
    @State private var tips: [String] = []
    @State private var speechSynth = AVSpeechSynthesizer()
    @State private var lastSpokenIndex: Int?
    @State private var showLoggedToast = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            backgroundLayer
            Color.black.opacity(0.35).ignoresSafeArea()
            if isPreparing {
                coachLoadingView(
                    title: "Preparing Workout",
                    subtitle: tips.joined(separator: "\n")
                )
            } else if isLogging {
                coachLoadingView(
                    title: "Logging Workout",
                    subtitle: completionQuote()
                )
            } else {
                workoutOverlay
            }
        }
        .onAppear {
            initializeState()
            fetchVideosForSteps()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isPreparing = false
                speakStepTipIfNeeded()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            speakStepTipIfNeeded()
        }
        .onReceive(timer) { _ in
            guard !isPaused, !isPreparing, !isLogging else { return }
            elapsedSeconds += 1
        }
    }

    private var steps: [GuidedExercise] {
        var all: [GuidedExercise] = []
        for idx in exercises.indices {
            all.append(exercises[idx])
            if idx < exercises.count - 1 {
                all.append(GuidedExercise(name: "Rest", setsReps: "60-90 sec", rpe: "Recovery"))
            }
        }
        return all
    }

    private var currentStep: GuidedExercise {
        guard !steps.isEmpty else {
            return GuidedExercise(name: "Workout", setsReps: "--", rpe: "--")
        }
        return steps[min(max(0, currentIndex), steps.count - 1)]
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let localId = localVideoId(for: currentStep.name) {
            YouTubePlayerView(videoId: localId, onError: nil)
                .ignoresSafeArea()
        } else if let video = videosByIndex[currentIndex], !video.id.isEmpty {
            YouTubePlayerView(videoId: video.id, onError: nil)
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color.black, Color(red: 0.06, green: 0.08, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var workoutOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text(formattedTime(elapsedSeconds))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(isPaused ? "Resume" : "Pause") {
                    isPaused.toggle()
                    saveProgress()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.16))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text(currentStep.name)
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(.white)
                Text("Sets/Reps: \(currentStep.setsReps)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text("Difficulty: \(currentStep.rpe)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text("Step \(currentIndex + 1) of \(steps.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))

                HStack(spacing: 10) {
                    Button("Pause & Exit") {
                        isPaused = true
                        saveProgress()
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button("Complete Workout") {
                        finishWorkout()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button(currentIndex >= steps.count - 1 ? "Finish" : "Next") {
                        goNext()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .overlay(alignment: .top) {
            if showLoggedToast {
                Text("Workout logged successfully")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 100)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func coachLoadingView(title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            if let url = coach.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(Color.white.opacity(0.2))
                    }
                }
                .frame(width: 86, height: 86)
                .clipShape(Circle())
            }
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            ProgressView().tint(.white)
        }
        .padding(20)
    }

    private func initializeState() {
        tips = [
            "Warm up before your first set.",
            "Keep your form strict and controlled.",
            "Use your listed RPE to pace intensity."
        ]
        if let resumeState, resumeState.dayKey == dayKey, resumeState.exercises == exercises {
            currentIndex = min(max(0, resumeState.currentIndex), max(0, steps.count - 1))
            elapsedSeconds = max(0, resumeState.elapsedSeconds)
            isPaused = resumeState.isPaused
        }
    }

    private func fetchVideosForSteps() {
        for index in steps.indices {
            let step = steps[index]
            let category = categoryForExercise(step.name)
            APIService.shared.getVideos(category: category, limit: 8)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { videos in
                        if let first = videos.first {
                            videosByIndex[index] = first
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }

    private func categoryForExercise(_ name: String) -> String {
        let lower = name.lowercased()
        if lower == "rest" { return "yoga" }
        if lower.contains("run") || lower.contains("bike") || lower.contains("cardio") || lower.contains("walk") {
            return "cardio"
        }
        if lower.contains("hiit") { return "hiit" }
        if lower.contains("flow") || lower.contains("mobility") { return "yoga" }
        return "strength"
    }

    private func goNext() {
        guard !steps.isEmpty else {
            finishWorkout()
            return
        }
        if currentIndex >= steps.count - 1 {
            finishWorkout()
            return
        }
        currentIndex += 1
        saveProgress()
    }

    private func saveProgress() {
        onSaveState(
            GuidedWorkoutSessionState(
                dayKey: dayKey,
                workoutTitle: workoutTitle,
                exercises: exercises,
                currentIndex: currentIndex,
                elapsedSeconds: elapsedSeconds,
                isPaused: isPaused
            )
        )
    }

    private func finishWorkout() {
        guard !isLogging else { return }
        isLogging = true
        isPaused = true
        let summary = exercises.map { "\($0.name) \($0.setsReps) \($0.rpe)" }.joined(separator: ", ")
        guard let userId else {
            onSaveState(nil)
            onWorkoutCompleted()
            dismiss()
            return
        }
        let logPrompt = """
        Please log this workout as completed for today.
        Workout: \(workoutTitle)
        Elapsed seconds: \(elapsedSeconds)
        Exercises: \(summary)
        """
        AICoachService.shared.sendMessage(logPrompt, threadId: nil, userId: userId) { _ in
            DispatchQueue.main.async {
                isLogging = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLoggedToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onSaveState(nil)
                    onWorkoutCompleted()
                    dismiss()
                }
            }
        }
    }

    private func localVideoId(for exercise: String) -> String? {
        let lower = exercise.lowercased()
        if lower.contains("rest") { return "v7AYKMP6rOE" } // calm recovery/yoga
        if lower.contains("squat") { return "YaXPRqUwItQ" }
        if lower.contains("bench") || lower.contains("chest press") { return "rT7DgCr-3pg" }
        if lower.contains("row") { return "vT2GjY_Umpw" }
        if lower.contains("deadlift") || lower.contains("rdl") { return "op9kVnSso6Q" }
        if lower.contains("lunge") { return "QOVaHwm-Q6U" }
        if lower.contains("overhead") || lower.contains("ohp") || lower.contains("shoulder press") { return "2yjwXTZQDDI" }
        if lower.contains("pull") || lower.contains("lat") { return "CAwf7n6Luuc" }
        if lower.contains("plank") { return "ASdvN_XEl_c" }
        if lower.contains("run") || lower.contains("cardio") { return "ml6cT4AZdqI" }
        return nil
    }

    private func speakStepTipIfNeeded() {
        guard !isPreparing, !isLogging else { return }
        guard lastSpokenIndex != currentIndex else { return }
        lastSpokenIndex = currentIndex
        let tip = stepTip(for: currentStep.name)
        let utterance = AVSpeechUtterance(string: tip)
        utterance.rate = 0.5
        utterance.volume = 0.9
        speechSynth.speak(utterance)
    }

    private func stepTip(for exercise: String) -> String {
        let lower = exercise.lowercased()
        if lower.contains("rest") {
            return "Take a controlled rest. Breathe deeply and get ready for the next set."
        }
        if lower.contains("squat") {
            return "For squats, keep your chest up, brace your core, and push through your mid-foot."
        }
        if lower.contains("bench") {
            return "For bench press, keep your shoulders packed and control the bar path."
        }
        if lower.contains("deadlift") || lower.contains("rdl") {
            return "For hinge movements, keep a neutral spine and drive with your hips."
        }
        if lower.contains("row") {
            return "On rows, pull your elbows back and squeeze your shoulder blades."
        }
        return "Move with control, keep good form, and stay near your target effort."
    }

    private func completionQuote() -> String {
        [
            "Strong finish. You showed up and did the work.",
            "Momentum built. Keep this streak alive.",
            "Session complete. Progress locked in."
        ].randomElement() ?? "Workout complete."
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    TodayPlanDetailView()
        .environmentObject(AppState())
        .environmentObject(AuthenticationManager())
}

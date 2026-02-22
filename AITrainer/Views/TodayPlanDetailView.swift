import SwiftUI
import Combine
import AVFoundation
import AVKit

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

            Text("Plan logic: compound lifts are programmed heavier (RPE 7-8), accessory lifts lighter (RPE 6-7), and progression favors clean form before loading.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.66))

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
            let cleaned = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^\s*[•\-\*]\s*"#, with: "", options: .regularExpression)
            let muscle = inferredMuscleGroup(from: cleaned)
            let load = inferredLoadGuidance(from: cleaned)
            return "\(cleaned)\nTarget: \(muscle) • Load: \(load)"
        }
    }

    private func inferredMuscleGroup(from exercise: String) -> String {
        let lower = exercise.lowercased()
        if lower.contains("squat") || lower.contains("lunge") || lower.contains("leg press") {
            return "Quads/Glutes"
        }
        if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("ham") {
            return "Posterior Chain"
        }
        if lower.contains("bench") || lower.contains("chest") {
            return "Chest/Triceps"
        }
        if lower.contains("row") || lower.contains("pull") || lower.contains("lat") {
            return "Back/Biceps"
        }
        if lower.contains("overhead") || lower.contains("shoulder") || lower.contains("ohp") {
            return "Shoulders/Triceps"
        }
        if lower.contains("curl") {
            return "Biceps"
        }
        if lower.contains("plank") || lower.contains("core") || lower.contains("pallof") || lower.contains("dead bug") {
            return "Core"
        }
        if lower.contains("bike") || lower.contains("run") || lower.contains("cardio") || lower.contains("zone 2") {
            return "Cardio Conditioning"
        }
        return "Full Body"
    }

    private func inferredLoadGuidance(from exercise: String) -> String {
        let lower = exercise.lowercased()
        let compound = ["squat", "deadlift", "bench", "row", "overhead", "leg press", "pull-up", "pull up"]
        if compound.contains(where: { lower.contains($0) }) {
            return "Heavier, controlled"
        }
        return "Lighter, strict form"
    }

    private func startGuidedWorkout(from details: [String], title: String) {
        var parsed = parseGuidedExercises(from: details)
        if parsed.isEmpty {
            let fallbackName = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Full Body Workout" : title
            parsed = [GuidedExercise(name: fallbackName, setsReps: "3x8-12", rpe: "RPE7")]
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
    @State private var tips: [String] = []
    @State private var showLoggedToast = false
    @State private var beatsPlayer: AVAudioPlayer?
    @State private var activeBeatStepIndex: Int?
    @State private var localVideoCatalog: [LocalWorkoutVideoResponse] = []
    @State private var assignedVideoByStepIndex: [Int: LocalWorkoutVideoResponse] = [:]
    @StateObject private var videoPlayback = GuidedWorkoutVideoPlayback()

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
            configureAudioSession()
            loadLocalVideoCatalog()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isPreparing = false
                playCurrentStepVideo()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            playCurrentStepVideo()
        }
        .onChange(of: isPreparing) { _, preparing in
            if !preparing {
                playCurrentStepVideo()
            }
        }
        .onReceive(timer) { _ in
            guard !isPaused, !isPreparing, !isLogging else { return }
            elapsedSeconds += 1
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                beatsPlayer?.pause()
                videoPlayback.pause()
            } else if let beatsPlayer {
                beatsPlayer.play()
                videoPlayback.play()
            } else {
                videoPlayback.play()
            }
        }
        .onDisappear {
            stopBeats()
            videoPlayback.stop()
        }
    }

    private var steps: [GuidedExercise] {
        let sourceExercises = exercises.isEmpty
            ? [GuidedExercise(name: workoutTitle.isEmpty ? "Full Body Workout" : workoutTitle, setsReps: "3x8-12", rpe: "RPE7")]
            : exercises
        var all: [GuidedExercise] = []
        for idx in sourceExercises.indices {
            all.append(sourceExercises[idx])
            if idx < sourceExercises.count - 1 {
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
        if let player = videoPlayback.player {
            GuidedVideoLayerView(player: player)
                .ignoresSafeArea()
                .clipped()
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
                Button(isPaused ? "Resume Workout" : "Pause Workout") {
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
                    Button("Complete Workout") {
                        finishWorkout()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button("Next") {
                        goNext()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(currentIndex >= steps.count - 1)
                    .opacity(currentIndex >= steps.count - 1 ? 0.45 : 1.0)
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
        stopBeats()
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
        stopBeats()
        videoPlayback.stop()
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

    private func loadLocalVideoCatalog() {
        APIService.shared.getLocalWorkoutVideos()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in
                    assignVideosToStepsIfNeeded()
                },
                receiveValue: { videos in
                    localVideoCatalog = videos
                    assignVideosToStepsIfNeeded()
                    playCurrentStepVideo()
                }
            )
            .store(in: &videoPlayback.cancellables)
    }

    private func assignVideosToStepsIfNeeded() {
        guard assignedVideoByStepIndex.isEmpty else { return }
        guard !localVideoCatalog.isEmpty else { return }
        for idx in steps.indices {
            let name = steps[idx].name
            if let matched = findBestMatchVideo(for: name) {
                assignedVideoByStepIndex[idx] = matched
                continue
            }
            assignedVideoByStepIndex[idx] = localVideoCatalog.randomElement()
        }
    }

    private func findBestMatchVideo(for exerciseName: String) -> LocalWorkoutVideoResponse? {
        let key = exerciseName.lowercased().replacingOccurrences(of: " ", with: "_")
        if let exact = localVideoCatalog.first(where: { $0.key.lowercased() == key }) {
            return exact
        }
        let words = Set(
            exerciseName
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 2 }
        )
        return localVideoCatalog.first { video in
            let hay = "\(video.key.lowercased()) \(video.base_filename.lowercased())"
            return words.contains(where: { hay.contains($0) })
        }
    }

    private func playCurrentStepVideo() {
        guard !isPreparing else { return }
        guard !steps.isEmpty else {
            videoPlayback.stop()
            return
        }
        if assignedVideoByStepIndex.isEmpty {
            assignVideosToStepsIfNeeded()
        }
        if assignedVideoByStepIndex[currentIndex] == nil, let random = localVideoCatalog.randomElement() {
            assignedVideoByStepIndex[currentIndex] = random
        }
        guard let pair = assignedVideoByStepIndex[currentIndex] else {
            videoPlayback.stop()
            return
        }
        videoPlayback.play(
            introURL: resolvedURL(remote: pair.base_url, localPath: pair.base_local_path),
            repsURL: resolvedURL(remote: pair.reps_url, localPath: pair.reps_local_path)
        )
    }

    private func resolvedURL(remote: String?, localPath: String?) -> URL? {
        if let localPath, !localPath.isEmpty, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        guard let remote, !remote.isEmpty else { return nil }
        return URL(string: remote)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // Non-fatal: guided workout can run without custom audio session.
        }
    }

    private func startBeats(forStepIndex stepIndex: Int) {
        guard activeBeatStepIndex != stepIndex else { return }
        guard let beatsURL = Bundle.main.url(forResource: "light_beats_loop", withExtension: "mp3") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: beatsURL)
            player.numberOfLoops = -1
            player.volume = 0.18
            player.prepareToPlay()
            player.play()
            beatsPlayer = player
            activeBeatStepIndex = stepIndex
        } catch {
            // Non-fatal: fallback is coach voice only.
        }
    }

    private func stopBeats() {
        beatsPlayer?.stop()
        beatsPlayer = nil
        activeBeatStepIndex = nil
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

private final class GuidedWorkoutVideoPlayback: ObservableObject {
    @Published var player: AVQueuePlayer?
    var cancellables = Set<AnyCancellable>()
    private var itemEndObserver: NSObjectProtocol?
    private var repsURL: URL?

    deinit {
        stop()
    }

    func play(introURL: URL?, repsURL: URL?) {
        guard let introURL else { return }
        stopObservers()
        self.repsURL = repsURL
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = false
        queuePlayer.actionAtItemEnd = .none
        player = queuePlayer

        let item = AVPlayerItem(url: introURL)
        queuePlayer.replaceCurrentItem(with: item)
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak queuePlayer] _ in
            if let reps = self?.repsURL {
                let repsItem = AVPlayerItem(url: reps)
                queuePlayer?.replaceCurrentItem(with: repsItem)
                queuePlayer?.play()
                self?.setupLoopObserver(for: repsItem)
                return
            }
            queuePlayer?.seek(to: .zero)
            queuePlayer?.play()
        }
        queuePlayer.play()
    }

    private func setupLoopObserver(for item: AVPlayerItem) {
        stopObservers()
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        stopObservers()
        player?.pause()
        repsURL = nil
        player = nil
    }

    private func stopObservers() {
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
    }

}

private struct GuidedVideoLayerView: UIViewRepresentable {
    let player: AVQueuePlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer.addSublayer(layer)
        context.coordinator.playerLayer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.player = player
        context.coordinator.playerLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}

#Preview {
    TodayPlanDetailView()
        .environmentObject(AppState())
        .environmentObject(AuthenticationManager())
}

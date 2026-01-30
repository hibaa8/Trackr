//
//  YouTubeService.swift
//  AITrainer
//
//  Service for fetching workout videos from Python backend
//

import Foundation
import Combine

class YouTubeService: ObservableObject {
    // Python backend URL - change this to your deployed backend URL
    private var baseURL: String { BackendConfig.baseURL }

    @Published var workoutVideos: [WorkoutVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    func searchWorkoutVideos(category: WorkoutCategory = .all, maxResults: Int = 20) {
        isLoading = true
        errorMessage = nil

        let urlString = "\(baseURL)/videos?category=\(category.rawValue)&limit=\(maxResults)"

        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            self.isLoading = false
            return
        }

        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: VideoResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to load videos: \(error.localizedDescription)"
                        print("YouTube Service Error: \(error)")

                        // Fallback to sample videos if backend is not available
                        self?.loadFallbackVideos(for: category)
                    }
                },
                receiveValue: { [weak self] response in
                    self?.workoutVideos = response.videos
                }
            )
            .store(in: &cancellables)
    }

    private func loadFallbackVideos(for category: WorkoutCategory) {
        // Fallback videos if backend is not available
        let fallbackVideos = getFallbackVideos(for: category)

        DispatchQueue.main.async {
            self.workoutVideos = fallbackVideos
            self.isLoading = false
            self.errorMessage = "Using offline videos (start Python backend for live content)"
        }
    }

    private func getFallbackVideos(for category: WorkoutCategory) -> [WorkoutVideo] {
        switch category {
        case .all, .cardio:
            return [
                WorkoutVideo(
                    id: "MLpne8lFxHs",
                    title: "10 MIN MORNING YOGA FLOW",
                    instructor: "Yoga with Adriene",
                    duration: 10,
                    formattedDuration: "10 min",
                    difficulty: "beginner",
                    thumbnailURL: "https://i.ytimg.com/vi/MLpne8lFxHs/hqdefault.jpg",
                    embedURL: "https://www.youtube-nocookie.com/embed/MLpne8lFxHs",
                    youtubeURL: "https://www.youtube.com/watch?v=MLpne8lFxHs",
                    viewCount: 5000000,
                    description: "Start your day with this energizing yoga flow."
                ),
                WorkoutVideo(
                    id: "6K8_N4XtTOQ",
                    title: "15 MIN FULL BODY WORKOUT",
                    instructor: "FitnessBlender",
                    duration: 15,
                    formattedDuration: "15 min",
                    difficulty: "intermediate",
                    thumbnailURL: "https://i.ytimg.com/vi/6K8_N4XtTOQ/hqdefault.jpg",
                    embedURL: "https://www.youtube-nocookie.com/embed/6K8_N4XtTOQ",
                    youtubeURL: "https://www.youtube.com/watch?v=6K8_N4XtTOQ",
                    viewCount: 3000000,
                    description: "Complete full body workout you can do at home."
                )
            ]
        case .strength:
            return [
                WorkoutVideo(
                    id: "IODxDxX7oi4",
                    title: "20 MIN UPPER BODY STRENGTH",
                    instructor: "MadFit",
                    duration: 20,
                    formattedDuration: "20 min",
                    difficulty: "intermediate",
                    thumbnailURL: "https://i.ytimg.com/vi/IODxDxX7oi4/hqdefault.jpg",
                    embedURL: "https://www.youtube-nocookie.com/embed/IODxDxX7oi4",
                    youtubeURL: "https://www.youtube.com/watch?v=IODxDxX7oi4",
                    viewCount: 2500000,
                    description: "Build upper body strength with bodyweight exercises."
                )
            ]
        case .yoga:
            return [
                WorkoutVideo(
                    id: "v7AYKMP6rOE",
                    title: "Morning Yoga For Beginners",
                    instructor: "Yoga with Adriene",
                    duration: 20,
                    formattedDuration: "20 min",
                    difficulty: "beginner",
                    thumbnailURL: "https://i.ytimg.com/vi/v7AYKMP6rOE/hqdefault.jpg",
                    embedURL: "https://www.youtube-nocookie.com/embed/v7AYKMP6rOE",
                    youtubeURL: "https://www.youtube.com/watch?v=v7AYKMP6rOE",
                    viewCount: 8000000,
                    description: "Perfect morning yoga routine for beginners."
                )
            ]
        case .hiit:
            return [
                WorkoutVideo(
                    id: "9jcKUb_-1eA",
                    title: "12 MIN INTENSE HIIT WORKOUT",
                    instructor: "Chloe Ting",
                    duration: 12,
                    formattedDuration: "12 min",
                    difficulty: "advanced",
                    thumbnailURL: "https://i.ytimg.com/vi/9jcKUb_-1eA/hqdefault.jpg",
                    embedURL: "https://www.youtube-nocookie.com/embed/9jcKUb_-1eA",
                    youtubeURL: "https://www.youtube.com/watch?v=9jcKUb_-1eA",
                    viewCount: 4000000,
                    description: "High intensity interval training to burn calories fast."
                )
            ]
        }
    }
}
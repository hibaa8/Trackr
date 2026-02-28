//
//  WorkoutVideoPlayer.swift
//  AITrainer
//
//  Modern YouTube video player
//

import SwiftUI
import YouTubeiOSPlayerHelper

struct WorkoutVideoPlayer: View {
    let video: WorkoutVideo
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true

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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Video player
                        videoPlayerSection

                        // Fallback: open in YouTube if embed is blocked
                        watchOnYouTubeButton

                        // Video info
                        videoInfoSection
                            .padding(.horizontal, 20)

                        // Action buttons
                        actionButtonsSection
                            .padding(.horizontal, 20)

                        // Description
                        descriptionSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(
                // Close button
                HStack {
                    VStack {
                        Button(action: {
                            dismiss()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 44, height: 44)

                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 60)
                        .padding(.leading, 20)

                        Spacer()
                    }

                    Spacer()
                },
                alignment: .topLeading
            )
        }
    }

    private var videoPlayerSection: some View {
        ZStack {
            // Video player with fallback
            Group {
                if !video.id.isEmpty {
                    YouTubePlayerView(videoId: video.id, onError: {
                        openYouTube()
                    })
                        .frame(height: 250)
                        .cornerRadius(12)
                } else {
                    // Fallback to thumbnail with play button
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(height: 250)
                    .cornerRadius(12)
                    .overlay(
                        Button(action: {
                            // Open in Safari using the youtubeURL from backend
                            openYouTube()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.7))
                                    .frame(width: 60, height: 60)

                                Image(systemName: "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                        }
                    )
                }
            }

            // Loading overlay
            if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.8))
                    .frame(height: 250)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.5)) {
                    isLoading = false
                }
            }
        }
    }

    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(video.title)
                .font(.headlineLarge)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 16) {
                // Instructor
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.fitnessGradientStart.opacity(0.2))
                            .frame(width: 32, height: 32)

                        Text("👤")
                            .font(.system(size: 14))
                    }

                    Text(video.instructor)
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                // Duration
                HStack(spacing: 4) {
                    Text("⏱️")
                        .font(.system(size: 12))

                    Text(video.formattedDuration)
                        .font(.captionLarge)
                        .foregroundColor(.textSecondary)
                        .fontWeight(.medium)
                }
            }

            // Tags
            HStack(spacing: 12) {
                // Difficulty tag
                Text(video.difficultyEnum.displayName)
                    .font(.captionMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(video.difficultyColor).opacity(0.8))
                    )

                // Category tag
                HStack(spacing: 4) {
                    Text(video.category.emoji)
                        .font(.system(size: 12))

                    Text(video.category.displayName)
                        .font(.captionMedium)
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.fitnessGradientStart.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
                )

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openYouTube() {
        if let url = URL(string: video.youtubeURL) {
            UIApplication.shared.open(url)
        }
    }

    private var watchOnYouTubeButton: some View {
        Button(action: {
            openYouTube()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                Text("Watch on YouTube")
            }
            .font(.bodyMedium)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.9))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            // Favorite button
            ModernActionButton(
                icon: "heart",
                title: "Favorite",
                gradient: LinearGradient(
                    colors: [Color.red.opacity(0.8), Color.pink.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ) {
                // Add to favorites
            }

            // Save for later
            ModernActionButton(
                icon: "bookmark",
                title: "Save",
                gradient: LinearGradient.fitnessGradient
            ) {
                // Save for later
            }

            // Share button
            ModernActionButton(
                icon: "square.and.arrow.up",
                title: "Share",
                gradient: LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ) {
                // Share workout
            }
        }
    }

    private var descriptionSection: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("About this workout")
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                Text(video.description.isEmpty ? "Get ready for an amazing workout session! This video will help you reach your fitness goals with expert guidance and motivation." : video.description)
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

// MARK: - YouTube Player View (YouTube iOS Player Helper SDK)

struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    var autoplay: Bool = false
    var muted: Bool = false
    var loopPlayback: Bool = false
    var showControls: Bool = true
    var startSeconds: Int = 0
    var endSeconds: Int? = nil
    let onError: (() -> Void)?

    func makeUIView(context: Context) -> YTPlayerView {
        let playerView = YTPlayerView()
        playerView.delegate = context.coordinator
        return playerView
    }

    func updateUIView(_ uiView: YTPlayerView, context: Context) {
        guard !videoId.isEmpty else { return }
        let playbackKey = "\(videoId)|\(autoplay)|\(muted)|\(loopPlayback)|\(showControls)|\(startSeconds)|\(endSeconds ?? -1)"
        context.coordinator.playbackConfig = PlaybackConfig(
            autoplay: autoplay,
            muted: muted
        )
        if context.coordinator.currentPlaybackKey != playbackKey {
            context.coordinator.currentPlaybackKey = playbackKey
            let vars: [String: Any] = [
                "playsinline": 1,
                "modestbranding": 1,
                "rel": 0,
                "autoplay": autoplay ? 1 : 0,
                "mute": muted ? 1 : 0,
                "controls": showControls ? 1 : 0,
                "fs": 0,
                "iv_load_policy": 3,
                "disablekb": 1,
                "start": max(0, startSeconds),
                "loop": loopPlayback ? 1 : 0,
                "playlist": loopPlayback ? videoId : ""
            ]
            var resolvedVars = vars
            if let endSeconds {
                resolvedVars["end"] = max(startSeconds + 1, endSeconds)
            }
            uiView.load(withVideoId: videoId, playerVars: resolvedVars)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    struct PlaybackConfig {
        let autoplay: Bool
        let muted: Bool
    }

    class Coordinator: NSObject, YTPlayerViewDelegate {
        let onError: (() -> Void)?
        var currentPlaybackKey: String?
        var playbackConfig = PlaybackConfig(autoplay: false, muted: false)

        init(onError: (() -> Void)?) {
            self.onError = onError
        }

        func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
            if playbackConfig.autoplay {
                playerView.playVideo()
            }
        }

        func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {
            onError?()
        }
    }
}

// MARK: - Modern Action Button

struct ModernActionButton: View {
    let icon: String
    let title: String
    let gradient: LinearGradient
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(title)
                    .font(.captionLarge)
                    .foregroundColor(.textPrimary)
                    .fontWeight(.medium)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}
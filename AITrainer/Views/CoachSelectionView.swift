import SwiftUI
import UIKit
import AVKit

struct CoachSelectionView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCoach: Coach? = nil
    @State private var showCoachDetail = false
    @State private var contentOpacity = 0.0
    @State private var introCoach: Coach? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        if showCoachDetail, let coach = selectedCoach {
            CoachDetailView(coach: coach)
        } else {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                VStack(spacing: 32) {
                    // Title
                    Text("Choose Your Coach")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 60)

                    // Coach Grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(appState.coaches) { coach in
                                CoachCard(coach: coach) {
                                    selectedCoach = coach
                                    introCoach = coach
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
                .opacity(contentOpacity)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    contentOpacity = 1.0
                }
            }
            .fullScreenCover(item: $introCoach) { coach in
                CoachIntroVideoView(coach: coach) {
                    selectedCoach = coach
                    introCoach = nil
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showCoachDetail = true
                    }
                }
            }
        }
    }
}

struct CoachCard: View {
    let coach: Coach
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Coach Image
                ZStack {
                    if let url = coach.imageURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(coach.primaryColor).opacity(0.8),
                                                Color(coach.primaryColor).opacity(0.4)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(coach.primaryColor).opacity(0.8),
                                        Color(coach.primaryColor).opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 160)
                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                // Coach Info
                VStack(alignment: .leading, spacing: 8) {
                    // Name and Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coach.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(coach.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }

                    // Specialties Tags
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 4) {
                        ForEach(Array(coach.expertise.prefix(4)), id: \.self) { specialty in
                            Text(specialty)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(coach.primaryColor))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color(coach.primaryColor).opacity(0.2))
                                )
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct CoachIntroVideoView: View {
    let coach: Coach
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let url = coach.videoURL {
                FullScreenVideoPlayer(player: player)
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
                Text("Video unavailable")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
            }

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
        dismiss()
        onFinish()
    }
}

struct FullScreenVideoPlayer: UIViewControllerRepresentable {
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

// Extension to convert string colors to SwiftUI Colors
extension Color {
    init(_ colorName: String) {
        switch colorName.lowercased() {
        case "blue":
            self = .blue
        case "cyan":
            self = .cyan
        case "purple":
            self = .purple
        case "pink":
            self = .pink
        case "orange":
            self = .orange
        case "red":
            self = .red
        case "green":
            self = .green
        case "teal":
            self = .teal
        case "navy":
            self = Color(red: 0, green: 0.2, blue: 0.4)
        case "indigo":
            self = .indigo
        default:
            self = .blue
        }
    }
}

#Preview {
    CoachSelectionView()
}
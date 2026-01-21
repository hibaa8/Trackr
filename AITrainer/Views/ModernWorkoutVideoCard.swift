//
//  ModernWorkoutVideoCard.swift
//  AITrainer
//
//  Modern workout video card for YouTube videos
//

import SwiftUI

struct ModernWorkoutVideoCard: View {
    let video: WorkoutVideo
    let action: () -> Void

    @State private var isPressed = false
    @State private var thumbnailImage: UIImage?

    var body: some View {
        ModernCard {
            Button(action: action) {
                VStack(spacing: 0) {
                    // Video thumbnail with play overlay
                    thumbnailSection

                    // Video information
                    videoInfoSection
                        .padding(20)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var thumbnailSection: some View {
        ZStack {
            // Thumbnail image
            AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
            } placeholder: {
                // Gradient placeholder
                LinearGradient(
                    colors: [
                        Color.fitnessGradientStart.opacity(0.8),
                        Color.fitnessGradientEnd.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .aspectRatio(16/9, contentMode: .fill)
                .overlay(
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                )
            }

            // Dark overlay for better text readability
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Play button
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.fitnessGradientStart)
                    .offset(x: 2) // Optical alignment
            }
            .scaleEffect(isPressed ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)

            // Duration badge
            HStack(spacing: 4) {
                Text("⏱️")
                    .font(.system(size: 12))

                Text(video.formattedDuration)
                    .font(.captionLarge)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(16)

            // View count (if available)
            if video.viewCount > 0 {
                HStack(spacing: 4) {
                    Text("👀")
                        .font(.system(size: 10))

                    Text(formatViewCount(video.viewCount))
                        .font(.captionMedium)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.6))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)
            }
        }
        .clipped()
    }

    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title and instructor
            VStack(alignment: .leading, spacing: 8) {
                Text(video.title)
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.fitnessGradientStart.opacity(0.2))
                            .frame(width: 24, height: 24)

                        Text("👤")
                            .font(.system(size: 12))
                    }

                    Text(video.instructor)
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)

                    Spacer()
                }
            }

            // Tags and difficulty
            HStack(spacing: 12) {
                // Difficulty badge
                Text(video.difficultyEnum.displayName)
                    .font(.captionMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(video.difficultyColor))
                    )

                // Category tag
                HStack(spacing: 4) {
                    Text(video.category.emoji)
                        .font(.system(size: 12))

                    Text(video.category.displayName)
                        .font(.captionMedium)
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.fitnessGradientStart.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
                )

                Spacer()

                // Quick action buttons
                HStack(spacing: 8) {
                    quickActionButton(icon: "bookmark", color: .blue)
                    quickActionButton(icon: "square.and.arrow.up", color: .purple)
                }
            }
        }
    }

    private func quickActionButton(icon: String, color: Color) -> some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatViewCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        } else {
            return "\(count)"
        }
    }
}
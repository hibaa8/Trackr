//
//  GuidedWorkoutsView.swift
//  AITrainer
//
//  YouTube-powered workout videos
//

import SwiftUI
import Combine

struct GuidedWorkoutsView: View {
    @StateObject private var youtubeService = YouTubeService()
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: WorkoutCategory = .all
    @State private var selectedVideo: WorkoutVideo?
    
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
                    // Modern header
                    modernHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Category selector
                    modernCategorySelector
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)

                    // Videos list
                    if youtubeService.isLoading {
                        loadingView
                    } else if youtubeService.workoutVideos.isEmpty {
                        emptyStateView
                    } else {
                        videosListView
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadVideos()
        }
        .onChange(of: selectedCategory) { _ in
            loadVideos()
        }
        .sheet(item: $selectedVideo) { video in
            WorkoutVideoPlayer(video: video)
        }
    }

    private func loadVideos() {
        youtubeService.searchWorkoutVideos(category: selectedCategory)
    }
    // MARK: - Modern Header

    private var modernHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Workout Videos")
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)

                Text("Follow expert trainers from YouTube")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 44, height: 44)

                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }

    // MARK: - Modern Category Selector

    private var modernCategorySelector: some View {
        ModernCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WorkoutCategory.allCases, id: \.self) { category in
                        ModernCategoryButton(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedCategory = category
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .fitnessGradientStart))
                .scaleEffect(1.5)

            Text("Loading workout videos...")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.fitnessGradientStart.opacity(0.2))
                    .frame(width: 80, height: 80)

                Text("💪")
                    .font(.system(size: 40))
            }

            VStack(spacing: 8) {
                Text("No videos found")
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                Text("Try selecting a different category")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
            }

            ModernPrimaryButton(title: "Retry") {
                loadVideos()
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Videos List View

    private var videosListView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(youtubeService.workoutVideos) { video in
                    ModernWorkoutVideoCard(video: video) {
                        selectedVideo = video
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Modern Category Button

private struct ModernCategoryButton: View {
    let category: WorkoutCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(category.emoji)
                    .font(.system(size: 16))

                Text(category.displayName)
                    .font(.bodyMedium)
                    .fontWeight(.semibold)
            }
            .foregroundColor(isSelected ? .white : .textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isSelected ?
                LinearGradient.fitnessGradient :
                LinearGradient(
                    colors: [Color.backgroundGradientStart],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        isSelected ? Color.clear : Color.textTertiary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    GuidedWorkoutsView()
}

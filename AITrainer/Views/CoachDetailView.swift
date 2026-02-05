import SwiftUI
import AVKit
import UIKit

struct CoachDetailView: View {
    let coach: Coach
    @State private var showChatSetup = false
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if showChatSetup {
            ChatSetupView(coach: coach)
        } else {
            ZStack {
                // Background - Full screen coach image simulation
                LinearGradient(
                    colors: [
                        Color(coach.primaryColor).opacity(0.3),
                        Color.black.opacity(0.8),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Navigation Header
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)

                    Spacer()

                    // Coach Image
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(coach.primaryColor).opacity(0.6),
                                        Color(coach.secondaryColor).opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)

                        if let image = coachImage() {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 180)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.bottom, 24)

                    // Content Card
                    VStack(alignment: .leading, spacing: 0) {
                        // Coach Name & Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text(coach.name)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)

                            Text(coach.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .padding(.bottom, 32)

                        // About Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)

                            Text(coach.backgroundStory)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
                                .lineSpacing(4)
                        }
                        .padding(.bottom, 32)

                        // Specialties Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Specialties")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)

                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 100), spacing: 8)
                            ], spacing: 8) {
                                ForEach(coach.expertise, id: \.self) { specialty in
                                    Text(specialty)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color(coach.primaryColor).opacity(0.8))
                                        )
                                }
                            }
                        }
                        .padding(.bottom, 32)

                        // Training Style Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Training Style")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)

                            Text(coach.personality + " " + coach.speakingStyle)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
                                .lineSpacing(4)
                        }
                        .padding(.bottom, 40)

                        // Choose Button
                        Button(action: {
                            appState.setSelectedCoach(coach)
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showChatSetup = true
                            }
                        }) {
                            Text("Choose \(coach.name)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(coach.primaryColor),
                                            Color(coach.secondaryColor)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func coachImage() -> Image? {
        guard let url = coach.imageURL,
              let uiImage = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
}

#Preview {
    CoachDetailView(coach: Coach.allCoaches[0])
}
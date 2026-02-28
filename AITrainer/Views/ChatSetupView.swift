import SwiftUI
import UIKit

struct ChatSetupView: View {
    let coach: Coach
    @State private var showConversation = false
    @State private var contentOpacity = 0.0
    @State private var messageOffset = 50.0
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if showConversation {
            ConversationView(coach: coach)
        } else {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Keep top spacing aligned with previous header area.
                    Color.clear
                        .frame(height: 60)

                    Spacer()

                    // Coach Avatar and Message
                    VStack(spacing: 32) {
                        // Coach Avatar
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
                                .frame(width: 120, height: 120)

                            if let url = coach.imageURL {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .frame(width: 110, height: 110)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .offset(y: messageOffset * 0.3)
                        .opacity(contentOpacity)

                        // Coach Name
                        Text(coach.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(contentOpacity)

                        // Coach Message Bubble
                        VStack(spacing: 20) {
                            ChatBubble(
                                text: getWelcomeMessage(for: coach),
                                isFromCoach: true,
                                coachColor: coach.primaryColor
                            )
                            .offset(y: messageOffset)
                            .opacity(contentOpacity)

                            Text("I'll ask you a few questions to\ncreate your personalized plan.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .opacity(contentOpacity)
                        }
                    }

                    Spacer()

                    // Let's Start Button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showConversation = true
                        }
                    }) {
                        Text("Let's Start")
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
                    .opacity(contentOpacity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
            .onAppear {
                if appState.selectedCoach?.id != coach.id {
                    appState.setSelectedCoach(coach)
                }
                startAnimations()
            }
        }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
            contentOpacity = 1.0
            messageOffset = 0.0
        }
    }

    private func getWelcomeMessage(for coach: Coach) -> String {
        switch coach.slug {
        case "marcus_hayes":
            return "Hey! I'm Marcus, your new coach. Let's get you set up!"
        case "alex_rivera":
            return "Hi there! I'm Alex. Let's build something amazing together!"
        case "maria_santos":
            return "¡Hola! I'm Maria! Ready to dance your way to fitness?"
        case "jake_foster":
            return "What's up! I'm Jake. Time to find your flow!"
        case "david_thompson":
            return "Hey! I'm David. Let's build champion-level habits!"
        case "zara_khan":
            return "Hi! I'm Zara. Ready to discover your inner strength?"
        case "kenji_tanaka":
            return "Hello! I'm Kenji. Let's find balance and strength together!"
        case "hana_kim":
            return "Hi! I'm Hana. Ready to build a stronger core?"
        case "chloe_evans":
            return "Hello! I'm Chloe. Let's find calm and strength together."
        case "simone_adebayo":
            return "Hey! I'm Simone. Ready to get powerful?"
        case "liam_carter":
            return "Hey! I'm Liam. Let's crush your goals together!"
        default:
            return "Hey! I'm your new coach. Let's get you set up!"
        }
    }

}

struct ChatBubble: View {
    let text: String
    let isFromCoach: Bool
    let coachColor: String

    var body: some View {
        HStack {
            if isFromCoach {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            Color(coachColor).opacity(0.9)
                        )
                        .cornerRadius(20, corners: [.topLeft, .topRight, .bottomRight])
                }
                Spacer()
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(20, corners: [.topLeft, .topRight, .bottomLeft])
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

// Custom corner radius extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ChatSetupView(coach: Coach.allCoaches[0])
}
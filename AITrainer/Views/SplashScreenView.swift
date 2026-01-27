import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var logoScale = 0.5
    @State private var logoOpacity = 0.0
    @State private var loadingOpacity = 0.0

    var body: some View {
        if isActive {
            WelcomeOnboardingView()
        } else {
            ZStack {
                // Dark gradient background
                LinearGradient(
                    colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    // AI Coach Logo
                    VStack(spacing: 20) {
                        // Logo Icon
                        ZStack {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.cyan, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 4
                                )
                                .frame(width: 120, height: 120)

                            // Stylized AI Brain/Body icon
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 50, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.cyan, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)

                        // App Name
                        Text("AI Coach")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(logoOpacity)
                    }

                    Spacer()

                    // Loading Indicator
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            .scaleEffect(1.2)

                        Text("Loading your AI fitness coach...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .opacity(loadingOpacity)

                    Spacer().frame(height: 60)
                }
                .padding()
            }
            .onAppear {
                startAnimations()
            }
        }
    }

    private func startAnimations() {
        // Logo animation
        withAnimation(.easeOut(duration: 0.8)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Loading indicator animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.5)) {
                loadingOpacity = 1.0
            }
        }

        // Transition to next screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isActive = true
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
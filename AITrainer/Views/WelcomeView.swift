//
//  WelcomeView.swift
//  AITrainer
//
//  Initial welcome and sign in view
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var mode: AuthMode = .signIn

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    enum AuthMode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Sign Up"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.5), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, 28)

                    authCard
                        .padding(.horizontal, 20)

                    footerSection
                        .padding(.bottom, 40)
                }
            }
        }
        .onReceive(authManager.$authErrorMessage) { message in
            if let message {
                errorMessage = message
            }
        }
        .preferredColorScheme(.dark)
    }
}

private extension WelcomeView {
    var headerSection: some View {
            VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .modernFloatingShadow()

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.white)
            }

                Text("AI Trainer")
                .font(.displayLarge)
                .foregroundColor(.white)

                Text("Your personal AI fitness coach")
                .font(.bodyLarge)
                .foregroundColor(.white.opacity(0.75))
        }
    }

    var authCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                )
            .modernCardShadow()

            VStack(spacing: 20) {
                Picker("Auth Mode", selection: $mode) {
                    ForEach(AuthMode.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
            }
                }
                .pickerStyle(SegmentedPickerStyle())
                .tint(.blue)
                .colorScheme(.dark)

                AuthTextField(
                    title: "Email",
                    text: $email,
                    icon: "envelope.fill",
                    placeholder: "Enter your email"
                )
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                SecureFieldView(
                    title: "Password",
                    text: $password
                )

                if mode == .signUp {
                    SecureFieldView(
                        title: "Confirm Password",
                        text: $confirmPassword
                    )
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.captionLarge)
                        .foregroundColor(.red)
                }

                AuthPrimaryButton(title: mode.rawValue) {
                    handleAuth()
                }
                .disabled(authManager.isLoading)

                AuthSecondaryButton(title: "Continue with Google") {
                    handleGoogleSignIn()
                }
                .disabled(authManager.isLoading)

                if mode == .signIn {
                    AuthSecondaryButton(title: "Skip to Demo") {
                    authManager.signInDemo()
                }
                }
            }
            .padding(24)
        }
    }

    var footerSection: some View {
        VStack(spacing: 8) {
            Text("By continuing, you agree to our Terms & Privacy Policy.")
                .font(.captionMedium)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            }
        .padding(.horizontal, 24)
    }

    func handleAuth() {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty || password.isEmpty {
            errorMessage = "Email and password are required."
            return
        }

        if mode == .signUp {
            if password != confirmPassword {
                errorMessage = "Passwords do not match."
                return
            }
            authManager.signUp(email: trimmedEmail, password: password)
        } else {
            authManager.signIn(email: trimmedEmail, password: password)
        }
    }

    func handleGoogleSignIn() {
        errorMessage = nil
        authManager.signInWithGoogle()
    }
}

struct SecureFieldView: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)
        }

            SecureField("Enter your password", text: $text)
                .font(.bodyLarge)
                .foregroundColor(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                )
        }
    }
}

struct AuthTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.white)
            }

            TextField(placeholder, text: $text)
                .font(.bodyLarge)
                .foregroundColor(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                )
        }
    }
}

struct AuthPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyLarge)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .modernButtonShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AuthSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyLarge)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white.opacity(0.08))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                )
                .modernCardShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AuthenticationManager())
}
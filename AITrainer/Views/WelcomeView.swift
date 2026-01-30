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

    @State private var name = ""
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
            LinearGradient.backgroundGradient
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
    }
}

private extension WelcomeView {
    var headerSection: some View {
            VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient.fitnessGradient)
                    .frame(width: 96, height: 96)
                    .modernFloatingShadow()

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.white)
            }

                Text("AI Trainer")
                .font(.displayLarge)
                .foregroundColor(.textPrimary)

                Text("Your personal AI fitness coach")
                .font(.bodyLarge)
                .foregroundColor(.textSecondary)
        }
    }

    var authCard: some View {
        ModernCard {
            VStack(spacing: 20) {
                Picker("Auth Mode", selection: $mode) {
                    ForEach(AuthMode.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
            }
                }
                .pickerStyle(SegmentedPickerStyle())

                if mode == .signUp {
                    ModernTextField(
                        title: "Full Name",
                        text: $name,
                        icon: "person.fill",
                        placeholder: "Enter your name"
                    )
                }

                ModernTextField(
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

                ModernPrimaryButton(title: mode.rawValue) {
                    handleAuth()
                }

                if mode == .signIn {
                    ModernSecondaryButton(title: "Skip to Demo") {
                    authManager.signIn(email: "demo", password: "demo")
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
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
            }
        .padding(.horizontal, 24)
    }

    func handleAuth() {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty || password.isEmpty {
            errorMessage = "Email and password are required."
            return
        }

        if mode == .signUp {
            if trimmedName.isEmpty {
                errorMessage = "Please enter your name."
                return
            }
            if password != confirmPassword {
                errorMessage = "Passwords do not match."
                return
            }
            authManager.signUp(name: trimmedName, email: trimmedEmail, password: password)
        } else {
            authManager.signIn(email: trimmedEmail, password: password)
        }
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
                    .foregroundColor(.fitnessGradientStart)

                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
        }

            SecureField("Enter your password", text: $text)
                .font(.bodyLarge)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.backgroundGradientStart)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AuthenticationManager())
}
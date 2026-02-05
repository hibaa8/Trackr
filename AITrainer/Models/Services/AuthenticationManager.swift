//
//  AuthenticationManager.swift
//  AITrainer
//
//  Authentication and user session management
//

import Foundation
import Combine
import Supabase
import GoogleSignIn
import UIKit

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var currentUser: String?
    @Published var authErrorMessage: String?
    @Published var isLoading = false

    private let userDefaults = UserDefaults.standard
    private let supabase: SupabaseClient?
    private let isoFormatter = ISO8601DateFormatter()

    private struct UserRecord: Codable {
        let id: Int?
        let email: String
        let name: String
        let gender: String?
        let birthdate: String?
        let height_cm: Double?
        let weight_kg: Double?
        let created_at: String
    }

    private struct UserInsert: Codable {
        let email: String
        let name: String
        let gender: String?
        let birthdate: String?
        let height_cm: Double?
        let weight_kg: Double?
        let created_at: String
    }

    init() {
        if let url = SupabaseConfig.supabaseURL, let anonKey = SupabaseConfig.anonKey {
            supabase = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        } else {
            supabase = nil
        }
        checkAuthenticationStatus()
    }

    func checkAuthenticationStatus() {
        hasCompletedOnboarding = userDefaults.bool(forKey: "hasCompletedOnboarding")
        currentUser = userDefaults.string(forKey: "currentUserEmail")

        let hasLocalAuth = userDefaults.string(forKey: "authToken") != nil
        if !hasLocalAuth {
            isAuthenticated = false
            currentUser = nil
            Task { await clearSupabaseSessionIfNeeded() }
            return
        }

        Task { await refreshSession() }
    }

    func signIn(email: String, password: String) {
        authErrorMessage = nil
        if email == "demo", password == "demo" {
            setAuthenticated(email: email, onboardingCompleted: true)
            return
        }
        guard let supabase else {
            authErrorMessage = "Supabase is not configured."
            return
        }

        isLoading = true
        Task {
            do {
                _ = try await supabase.auth.signIn(email: email, password: password)
                guard let record = try await fetchUserRecord(email: email) else {
                    authErrorMessage = "No user profile found. Please sign up first."
                    try? await supabase.auth.signOut()
                    isAuthenticated = false
                    currentUser = nil
                    isLoading = false
                    return
                }
                setAuthenticated(email: record.email, onboardingCompleted: true)
                isLoading = false
            } catch {
                authErrorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func signUp(name: String, email: String, password: String) {
        authErrorMessage = nil
        guard let supabase else {
            authErrorMessage = "Supabase is not configured."
            return
        }

        isLoading = true
        Task {
            do {
                _ = try await supabase.auth.signUp(email: email, password: password)
                let insert = UserInsert(
                    email: email,
                    name: name,
                    gender: nil,
                    birthdate: nil,
                    height_cm: nil,
                    weight_kg: nil,
                    created_at: isoFormatter.string(from: Date())
                )
                _ = try await supabase.from("users").insert(insert).execute()
                setAuthenticated(email: email, onboardingCompleted: false)
                userDefaults.set(name, forKey: "currentUserName")
                isLoading = false
            } catch {
                authErrorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func signOut() {
        if let supabase {
            Task { try? await supabase.auth.signOut() }
        }
        isAuthenticated = false
        hasCompletedOnboarding = false
        userDefaults.removeObject(forKey: "hasCompletedOnboarding")
        userDefaults.removeObject(forKey: "authToken")
        userDefaults.removeObject(forKey: "currentUserEmail")
        userDefaults.removeObject(forKey: "currentUserName")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        userDefaults.set(true, forKey: "hasCompletedOnboarding")
    }

    func signInWithGoogle(presenting viewController: UIViewController) {
        authErrorMessage = nil
        guard let supabase else {
            authErrorMessage = "Supabase is not configured."
            return
        }
        guard let clientID = SupabaseConfig.googleClientID else {
            authErrorMessage = "Google Sign-In is not configured."
            return
        }

        isLoading = true
        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
                guard let idToken = result.user.idToken?.tokenString else {
                    throw NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token."])
                }
                let accessToken = result.user.accessToken.tokenString
                _ = try await supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken, accessToken: accessToken))

                let email = result.user.profile?.email ?? ""
                let name = result.user.profile?.name ?? "Google User"
                let existingUser = try await fetchUserRecord(email: email)
                if existingUser == nil {
                    let insert = UserInsert(
                        email: email,
                        name: name,
                        gender: nil,
                        birthdate: nil,
                        height_cm: nil,
                        weight_kg: nil,
                        created_at: isoFormatter.string(from: Date())
                    )
                    _ = try await supabase.from("users").insert(insert).execute()
                    setAuthenticated(email: email, onboardingCompleted: false)
                } else {
                    setAuthenticated(email: email, onboardingCompleted: true)
                }
                userDefaults.set(name, forKey: "currentUserName")
                isLoading = false
            } catch {
                authErrorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func refreshSession() async {
        guard let supabase else {
            isAuthenticated = false
            currentUser = nil
            return
        }
        do {
            let session = try await supabase.auth.session
            isAuthenticated = true
            currentUser = session.user.email
        } catch {
            isAuthenticated = false
            currentUser = nil
        }
    }

    private func clearSupabaseSessionIfNeeded() async {
        guard let supabase else { return }
        try? await supabase.auth.signOut()
    }

    private func fetchUserRecord(email: String) async throws -> UserRecord? {
        guard let supabase else { return nil }
        let records: [UserRecord] = try await supabase.from("users")
            .select()
            .eq("email", value: email)
            .limit(1)
            .execute()
            .value
        return records.first
    }

    private func setAuthenticated(email: String, onboardingCompleted: Bool) {
        userDefaults.set(UUID().uuidString, forKey: "authToken")
        userDefaults.set(email, forKey: "currentUserEmail")
        currentUser = email
        isAuthenticated = true
        hasCompletedOnboarding = onboardingCompleted
        userDefaults.set(onboardingCompleted, forKey: "hasCompletedOnboarding")
    }
}
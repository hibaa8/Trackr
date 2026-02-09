//
//  AuthenticationManager.swift
//  AITrainer
//
//  Authentication and user session management
//

import Foundation
import Combine
import Supabase
import AuthenticationServices
import UIKit

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var currentUser: String?
    @Published var authErrorMessage: String?
    @Published var isLoading = false
    @Published var demoUserId: Int?
    @Published var currentUserId: Int?

    private let userDefaults = UserDefaults.standard
    private let supabase: SupabaseClient?
    private let isoFormatter = ISO8601DateFormatter()
    private var cancellables = Set<AnyCancellable>()

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

    var effectiveUserId: Int? {
        demoUserId ?? currentUserId
    }

    func checkAuthenticationStatus() {
        hasCompletedOnboarding = userDefaults.bool(forKey: "hasCompletedOnboarding")
        currentUser = userDefaults.string(forKey: "currentUserEmail")
        currentUserId = userDefaults.object(forKey: "currentUserId") as? Int

        let hasLocalAuth = userDefaults.string(forKey: "authToken") != nil
        if !hasLocalAuth {
            isAuthenticated = false
            currentUser = nil
            currentUserId = nil
            Task { await clearSupabaseSessionIfNeeded() }
            return
        }

        Task { await refreshSession() }
    }

    func signIn(email: String, password: String) {
        authErrorMessage = nil
        demoUserId = nil
        currentUserId = nil
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
                resolveAndStoreUserId(email: record.email)
                isLoading = false
            } catch {
                authErrorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func signInDemo() {
        demoUserId = 1
        currentUserId = nil
        setAuthenticated(email: "demo", onboardingCompleted: false)
    }

    func signUp(email: String, password: String) {
        authErrorMessage = nil
        demoUserId = nil
        currentUserId = nil
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
                    name: "New User",
                    gender: nil,
                    birthdate: nil,
                    height_cm: nil,
                    weight_kg: nil,
                    created_at: isoFormatter.string(from: Date())
                )
                _ = try await supabase.from("users").insert(insert).execute()
                setAuthenticated(email: email, onboardingCompleted: false)
                resolveAndStoreUserId(email: email)
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
        demoUserId = nil
        currentUserId = nil
        userDefaults.removeObject(forKey: "hasCompletedOnboarding")
        userDefaults.removeObject(forKey: "authToken")
        userDefaults.removeObject(forKey: "currentUserEmail")
        userDefaults.removeObject(forKey: "currentUserName")
        userDefaults.removeObject(forKey: "currentUserId")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        userDefaults.set(true, forKey: "hasCompletedOnboarding")
    }

    func signInWithGoogle() {
        authErrorMessage = nil
        guard let supabase else {
            authErrorMessage = "Supabase is not configured."
            return
        }

        isLoading = true
        Task {
            do {
                guard let redirectURL = SupabaseConfig.authRedirectURL else {
                    authErrorMessage = "Google redirect URL is missing."
                    isLoading = false
                    return
                }
                let session = try await supabase.auth.signInWithOAuth(
                    provider: .google,
                    redirectTo: redirectURL
                ) { session in
                    session.presentationContextProvider = AuthPresentationContextProvider.shared
                    session.prefersEphemeralWebBrowserSession = true
                }

                let email = session.user.email ?? ""
                let name = session.user.userMetadata["full_name"] as? String ?? "Google User"
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
                resolveAndStoreUserId(email: email)
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
            if currentUserId == nil, let email = currentUser {
                resolveAndStoreUserId(email: email)
            }
        } catch {
            isAuthenticated = false
            currentUser = nil
        }
    }

    private func resolveAndStoreUserId(email: String) {
        APIService.shared.getUserId(email: email)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] response in
                    self?.currentUserId = response.user_id
                    self?.userDefaults.set(response.user_id, forKey: "currentUserId")
                }
            )
            .store(in: &cancellables)
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

    func handleAuthCallback(url: URL) {
        guard let supabase else { return }
        supabase.auth.handle(url)
    }
}

private final class AuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return windowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
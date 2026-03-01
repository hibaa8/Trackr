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
import GoogleSignIn

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var currentUser: String?
    @Published var authErrorMessage: String?
    @Published var isLoading = false
    @Published var demoUserId: Int?
    @Published var currentUserId: Int?
    @Published var forceLoginOnLaunch = true

    private let userDefaults = UserDefaults.standard
    private let supabase: SupabaseClient?
    private let isoFormatter = ISO8601DateFormatter()
    private var cancellables = Set<AnyCancellable>()
    private let googleAccessTokenKey = "currentGoogleAccessToken"
    
    private func logCalendar(_ message: String) {
        print("[GoogleCalendar][AuthManager] \(message)")
    }

    private func maskedToken(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "nil" }
        if token.count <= 10 { return "\(token.prefix(2))...\(token.suffix(2))" }
        return "\(token.prefix(6))...\(token.suffix(4))"
    }

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

    private struct BackendAuthResponse: Decodable {
        let user_id: Int
        let email: String
        let name: String
        let onboarding_completed: Bool
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

    var googleAccessToken: String? {
        let token = userDefaults.string(forKey: googleAccessTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        logCalendar("Read stored token: \(token.isEmpty ? "missing" : "present"), value=\(maskedToken(token))")
        return token.isEmpty ? nil : token
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
        forceLoginOnLaunch = false
        isLoading = true
        Task {
            do {
                let response = try await backendSignIn(email: email, password: password)
                setAuthenticated(email: response.email, onboardingCompleted: response.onboarding_completed)
                setCurrentUserId(response.user_id)
                userDefaults.set(response.name, forKey: "currentUserName")
                isLoading = false
            } catch {
                authErrorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func signInDemo() {
        let storedDemoId = UserDefaults.standard.integer(forKey: "demoUserId")
        guard storedDemoId > 0 else {
            authErrorMessage = "No demo user configured. Please sign in."
            return
        }
        demoUserId = storedDemoId
        currentUserId = nil
        forceLoginOnLaunch = false
        setAuthenticated(email: "demo", onboardingCompleted: false)
    }

    func signUp(email: String, password: String) {
        authErrorMessage = nil
        demoUserId = nil
        currentUserId = nil
        forceLoginOnLaunch = false
        isLoading = true
        Task {
            do {
                let response = try await backendSignUp(email: email, password: password, name: "New User")
                // Product rule: signup always routes to onboarding first.
                setAuthenticated(email: response.email, onboardingCompleted: false)
                setCurrentUserId(response.user_id)
                userDefaults.set(response.name, forKey: "currentUserName")
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
        forceLoginOnLaunch = true
        userDefaults.removeObject(forKey: "hasCompletedOnboarding")
        userDefaults.removeObject(forKey: "authToken")
        userDefaults.removeObject(forKey: "currentUserEmail")
        userDefaults.removeObject(forKey: "currentUserName")
        userDefaults.removeObject(forKey: "currentUserId")
        userDefaults.removeObject(forKey: googleAccessTokenKey)
    }

    func forceShowLoginOnLaunch() {
        isAuthenticated = false
        hasCompletedOnboarding = false
        demoUserId = nil
        currentUserId = nil
        currentUser = nil
        forceLoginOnLaunch = true
        userDefaults.removeObject(forKey: "hasCompletedOnboarding")
        userDefaults.removeObject(forKey: "authToken")
        userDefaults.removeObject(forKey: "currentUserEmail")
        userDefaults.removeObject(forKey: "currentUserName")
        userDefaults.removeObject(forKey: "currentUserId")
        userDefaults.removeObject(forKey: googleAccessTokenKey)
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

        forceLoginOnLaunch = false
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
                let callbackResponse = try await backendOAuthCallback(
                    accessToken: session.accessToken,
                    fallbackEmail: email,
                    fallbackName: name
                )
                setAuthenticated(
                    email: callbackResponse.email,
                    onboardingCompleted: callbackResponse.onboarding_completed
                )
                setCurrentUserId(callbackResponse.user_id)
                userDefaults.set(callbackResponse.name, forKey: "currentUserName")
                isLoading = false
            } catch {
                isAuthenticated = false
                currentUser = nil
                currentUserId = nil
                authErrorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func connectGoogleCalendar(completion: @escaping (Result<Void, Error>) -> Void) {
        logCalendar("connectGoogleCalendar() called")
        guard let clientID = SupabaseConfig.googleClientID, !clientID.isEmpty else {
            logCalendar("Missing Google client ID")
            completion(.failure(NSError(
                domain: "Auth",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Google client ID is missing."]
            )))
            return
        }
        guard let presenting = topViewController() else {
            logCalendar("Missing presenting view controller")
            completion(.failure(NSError(
                domain: "Auth",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Cannot present Google sign-in right now."]
            )))
            return
        }

        let requiredScopes = ["https://www.googleapis.com/auth/calendar.events"]
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        logCalendar("Starting Google calendar scope flow with required scopes: \(requiredScopes)")

        func finishWithScopes(for user: GIDGoogleUser) {
            let granted = user.grantedScopes ?? []
            let missing = requiredScopes.filter { !granted.contains($0) }
            self.logCalendar("finishWithScopes granted=\(granted.count), missing=\(missing.count)")
            guard !missing.isEmpty else {
                userDefaults.set(user.accessToken.tokenString, forKey: googleAccessTokenKey)
                self.logCalendar("Stored token after existing scopes: \(self.maskedToken(user.accessToken.tokenString))")
                completion(.success(()))
                return
            }
            user.addScopes(missing, presenting: presenting) { result, error in
                if let error {
                    self.logCalendar("addScopes failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let token = result?.user.accessToken.tokenString, !token.isEmpty else {
                    self.logCalendar("addScopes succeeded but access token missing")
                    completion(.failure(NSError(
                        domain: "Auth",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Google calendar permission granted but access token is missing."]
                    )))
                    return
                }
                self.userDefaults.set(token, forKey: self.googleAccessTokenKey)
                self.logCalendar("Stored token after addScopes: \(self.maskedToken(token))")
                completion(.success(()))
            }
        }

        if let current = GIDSignIn.sharedInstance.currentUser {
            logCalendar("Using existing GID currentUser session")
            finishWithScopes(for: current)
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { result, error in
            if let error {
                self.logCalendar("Initial Google signIn failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let user = result?.user else {
                self.logCalendar("Initial Google signIn returned nil user")
                completion(.failure(NSError(
                    domain: "Auth",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Google sign-in did not return a user."]
                )))
                return
            }
            self.logCalendar("Initial Google signIn succeeded")
            finishWithScopes(for: user)
        }
    }
    
    func freshGoogleCalendarAccessToken(completion: @escaping (String?) -> Void) {
        let fallback = googleAccessToken
        
        func finalize(_ token: String?) {
            let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                completion(fallback)
                return
            }
            userDefaults.set(trimmed, forKey: googleAccessTokenKey)
            logCalendar("freshGoogleCalendarAccessToken() returning token=\(maskedToken(trimmed))")
            completion(trimmed)
        }
        
        if let current = GIDSignIn.sharedInstance.currentUser {
            logCalendar("Refreshing token from currentUser")
            current.refreshTokensIfNeeded { [weak self] user, error in
                if let error {
                    self?.logCalendar("refreshTokensIfNeeded failed: \(error.localizedDescription)")
                    finalize(nil)
                    return
                }
                finalize(user?.accessToken.tokenString)
            }
            return
        }
        
        logCalendar("No currentUser; attempting restorePreviousSignIn")
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            if let error {
                self?.logCalendar("restorePreviousSignIn failed: \(error.localizedDescription)")
                finalize(nil)
                return
            }
            guard let user else {
                self?.logCalendar("restorePreviousSignIn returned nil user")
                finalize(nil)
                return
            }
            user.refreshTokensIfNeeded { refreshedUser, refreshError in
                if let refreshError {
                    self?.logCalendar("refresh after restore failed: \(refreshError.localizedDescription)")
                    finalize(user.accessToken.tokenString)
                    return
                }
                finalize(refreshedUser?.accessToken.tokenString ?? user.accessToken.tokenString)
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
                    self?.setCurrentUserId(response.user_id)
                }
            )
            .store(in: &cancellables)
    }

    private func setCurrentUserId(_ id: Int?) {
        guard let id else { return }
        currentUserId = id
        userDefaults.set(id, forKey: "currentUserId")
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var root = windowScene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return root
    }

    private func backendSignIn(email: String, password: String) async throws -> BackendAuthResponse {
        guard let url = URL(string: "\(BackendConfig.baseURL)/auth/signin") else {
            throw URLError(.badURL)
        }
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw NSError(domain: "Auth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail ?? "Sign in failed"])
        }
        return try JSONDecoder().decode(BackendAuthResponse.self, from: data)
    }

    private func backendSignUp(email: String, password: String, name: String) async throws -> BackendAuthResponse {
        guard let url = URL(string: "\(BackendConfig.baseURL)/auth/signup") else {
            throw URLError(.badURL)
        }
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password, "name": name])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw NSError(domain: "Auth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail ?? "Sign up failed"])
        }
        return try JSONDecoder().decode(BackendAuthResponse.self, from: data)
    }

    private func backendOAuthCallback(
        accessToken: String,
        fallbackEmail: String,
        fallbackName: String
    ) async throws -> BackendAuthResponse {
        guard let url = URL(string: "\(BackendConfig.baseURL)/auth/callback") else {
            throw URLError(.badURL)
        }
        let payload: [String: Any] = [
            "access_token": accessToken,
            "email": fallbackEmail,
            "name": fallbackName
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw NSError(domain: "Auth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail ?? "Google sign in failed"])
        }
        return try JSONDecoder().decode(BackendAuthResponse.self, from: data)
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
        userDefaults.set(onboardingCompleted, forKey: "hasCompletedOnboarding")
        currentUser = email
        hasCompletedOnboarding = onboardingCompleted
        isAuthenticated = true
    }

    func handleAuthCallback(url: URL) {
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }
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
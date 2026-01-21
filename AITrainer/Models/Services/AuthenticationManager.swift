//
//  AuthenticationManager.swift
//  AITrainer
//
//  Authentication and user session management
//

import Foundation
import Combine

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var currentUser: String?

    init() {
        checkAuthenticationStatus()
    }

    func checkAuthenticationStatus() {
        let token = UserDefaults.standard.string(forKey: "authToken")
        isAuthenticated = token != nil
        currentUser = UserDefaults.standard.string(forKey: "currentUserEmail")
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    func signIn(email: String, password: String) {
        // Simulate sign in
        UserDefaults.standard.set(UUID().uuidString, forKey: "authToken")
        UserDefaults.standard.set(email, forKey: "currentUserEmail")
        currentUser = email
        isAuthenticated = true
    }

    func signUp(name: String, email: String, password: String) {
        // Simulate sign up
        UserDefaults.standard.set(UUID().uuidString, forKey: "authToken")
        UserDefaults.standard.set(email, forKey: "currentUserEmail")
        UserDefaults.standard.set(name, forKey: "currentUserName")
        currentUser = email
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        hasCompletedOnboarding = false
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "currentUserEmail")
        UserDefaults.standard.removeObject(forKey: "currentUserName")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}
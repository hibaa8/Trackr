import Foundation

enum SupabaseConfig {
    static var supabaseURL: URL? {
        guard let value = value(forKey: "SupabaseURL") ?? value(forKey: "SUPABASE_URL"),
              let url = URL(string: value) else {
            return nil
        }
        return url
    }

    static var anonKey: String? {
        let value = value(forKey: "SupabaseAnonKey") ?? value(forKey: "SUPABASE_ANON_KEY")
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static var googleClientID: String? {
        let value = value(forKey: "GIDClientID") ?? value(forKey: "GOOGLE_CLIENT_ID")
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static var authRedirectURL: URL? {
        let value = value(forKey: "OAuthRedirectURL") ?? value(forKey: "GOOGLE_IOS_URL_SCHEME")
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "\(trimmed)://login-callback")
    }

    private static func value(forKey key: String) -> String? {
        if let envValue = ProcessInfo.processInfo.environment[key], !envValue.isEmpty {
            return envValue
        }
        if let plistValue = Bundle.main.infoDictionary?[key] as? String, !plistValue.isEmpty {
            return plistValue
        }
        return nil
    }
}

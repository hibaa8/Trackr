import Foundation

enum BackendConfig {
    static var baseURL: String {
        if let env = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"], !env.isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let info = Bundle.main.infoDictionary?["BackendBaseURL"] as? String, !info.isEmpty {
            return info.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "http://localhost:8000"
    }
}

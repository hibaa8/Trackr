import Foundation

enum BackendConfig {
    static var baseURL: String {
        if let env = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"], !env.isEmpty {
            return env
        }
        if let info = Bundle.main.infoDictionary?["BackendBaseURL"] as? String, !info.isEmpty {
            return info
        }
        return "https://vaylo-fitness.onrender.com"
    }
}

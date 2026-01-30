import Foundation

enum BackendConfig {
    static var baseURL: String {
        if let env = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"], !env.isEmpty {
            return env
        }
        if let info = Bundle.main.infoDictionary?["BackendBaseURL"] as? String, !info.isEmpty {
            return info
        }
        #if targetEnvironment(simulator)
        return "http://localhost:8000"
        #else
        return "http://localhost:8000"
        #endif
    }
}

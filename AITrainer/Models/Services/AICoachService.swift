import Foundation

struct CoachChatResponse: Decodable {
    let reply: String
    let thread_id: String
    let requires_feedback: Bool
    let plan_text: String?
}

struct CoachFeedbackResponse: Decodable {
    let reply: String
    let thread_id: String
}

final class AICoachService {
    static let shared = AICoachService()

    private var baseURL: String { BackendConfig.baseURL }
    private let session: URLSession
    
    private func logCalendar(_ message: String) {
        print("[GoogleCalendar][AICoachService] \(message)")
    }

    private func maskedToken(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "nil" }
        if token.count <= 10 { return "\(token.prefix(2))...\(token.suffix(2))" }
        return "\(token.prefix(6))...\(token.suffix(4))"
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        // Calendar sync requests can legitimately take longer (many events).
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }

    func sendMessage(
        _ message: String,
        threadId: String?,
        agentId: Int? = nil,
        userId: Int,
        googleAccessToken: String? = nil,
        imageBase64: String? = nil,
        completion: @escaping (Result<CoachChatResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/coach/chat") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var payload: [String: Any] = [
            "message": message,
            "user_id": userId,
            "thread_id": threadId as Any
        ]
        if let agentId {
            payload["agent_id"] = agentId
        }
        if let imageBase64, !imageBase64.isEmpty {
            payload["image_base64"] = imageBase64
        }
        if let googleAccessToken, !googleAccessToken.isEmpty {
            payload["google_access_token"] = googleAccessToken
        }
        logCalendar(
            "Sending chat payload user_id=\(userId), thread_id=\(threadId ?? "nil"), token=\(maskedToken(googleAccessToken))"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data
            else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(CoachChatResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func sendFeedback(
        threadId: String,
        approve: Bool,
        completion: @escaping (Result<CoachFeedbackResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/coach/feedback") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let payload: [String: Any] = [
            "thread_id": threadId,
            "approve_plan": approve
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data
            else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(CoachFeedbackResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

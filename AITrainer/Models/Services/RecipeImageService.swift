import Foundation

struct RecipeImageResponse: Codable {
    let image_url: String
}

final class RecipeImageService {
    static let shared = RecipeImageService()

    private var baseURL: String { BackendConfig.baseURL }
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration)
    }

    func fetchImageURL(prompt: String, size: CGSize = CGSize(width: 800, height: 600), completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/recipes/image") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let body: [String: Any] = [
            "prompt": prompt,
            "width": Int(size.width),
            "height": Int(size.height)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(RecipeImageResponse.self, from: data)
                completion(.success(decoded.image_url))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

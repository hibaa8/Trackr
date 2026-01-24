import Foundation

final class RecipeSearchService {
    static let shared = RecipeSearchService()

    private let baseURL = "http://localhost:8000"
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    func searchRecipes(
        query: String,
        ingredients: String?,
        cuisine: String?,
        flavor: String?,
        dietary: [String],
        completion: @escaping (Result<RecipeSearchResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/recipes/search") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var body: [String: Any] = [
            "query": query,
            "dietary": dietary,
            "max_results": 8
        ]
        if let ingredients = ingredients, !ingredients.isEmpty {
            body["ingredients"] = ingredients
        }
        if let cuisine = cuisine, !cuisine.isEmpty {
            body["cuisine"] = cuisine
        }
        if let flavor = flavor, !flavor.isEmpty {
            body["flavor"] = flavor
        }

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

            // Check if response is an error
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                if let errorString = String(data: data, encoding: .utf8) {
                    if errorString.contains("quota") {
                        completion(.failure(NSError(domain: "RecipeSearch", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API quota exceeded. Please try again later."])))
                    } else {
                        completion(.failure(NSError(domain: "RecipeSearch", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error (code: \(httpResponse.statusCode))"])))
                    }
                } else {
                    completion(.failure(URLError(.badServerResponse)))
                }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(RecipeSearchResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

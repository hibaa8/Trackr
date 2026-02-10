import Foundation

final class FoodScanService {
    static let shared = FoodScanService()

    private var baseURL: String { BackendConfig.baseURL }
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }

    func scanFood(imageData: Data, completion: @escaping (Result<FoodScanResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/food/scan") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"meal.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(FoodScanResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func logMeal(
        _ payload: FoodScanResponse,
        userId: Int,
        nameOverride: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/food/logs") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let body: [String: Any] = [
            "user_id": userId,
            "food_name": (nameOverride?.isEmpty == false ? nameOverride! : payload.food_name),
            "total_calories": payload.total_calories,
            "protein_g": payload.protein_g,
            "carbs_g": payload.carbs_g,
            "fat_g": payload.fat_g,
            "items": payload.items.map {
                [
                    "name": $0.name,
                    "category": $0.category as Any,
                    "amount": $0.amount,
                    "calories": $0.calories,
                    "protein_g": $0.protein_g,
                    "carbs_g": $0.carbs_g,
                    "fat_g": $0.fat_g,
                    "confidence": $0.confidence
                ]
            }
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            completion(.success(()))
        }.resume()
    }

    func getDailyIntake(date: Date, userId: Int, completion: @escaping (Result<DailyIntakeResponse, Error>) -> Void) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        guard let url = URL(string: "\(baseURL)/food/intake?day=\(dateString)&user_id=\(userId)") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        session.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(DailyIntakeResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func getDailyMeals(date: Date, userId: Int, completion: @escaping (Result<DailyMealLogsResponse, Error>) -> Void) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        guard let url = URL(string: "\(baseURL)/food/logs?day=\(dateString)&user_id=\(userId)") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        session.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(DailyMealLogsResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

import Foundation

enum ApiError: Error {
    case invalidURL
    case requestFailed(Int)
    case decodingFailed
    case unauthorized
}

struct ApiRequest {
    let path: String
    let method: String
    let body: Encodable?
    let headers: [String: String]

    init(path: String, method: String = "GET", body: Encodable? = nil, headers: [String: String] = [:]) {
        self.path = path
        self.method = method
        self.body = body
        self.headers = headers
    }
}

final class ApiClient {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://api.example.com")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func send<T: Decodable>(_ request: ApiRequest, decode type: T.Type = T.self, token: String? = nil) async throws -> T {
        let cleanPath = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        let url = baseURL.appendingPathComponent(cleanPath)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = request.body {
            urlRequest.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApiError.requestFailed(-1)
        }
        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(type, from: data)
        case 401:
            throw ApiError.unauthorized
        default:
            throw ApiError.requestFailed(httpResponse.statusCode)
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init(_ encodable: Encodable) {
        self.encodeFunc = encodable.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}

import Foundation

enum MonzoError: Error, LocalizedError {
    case invalidURL
    case networkFailure(underlying: Error)
    case httpError(statusCode: Int, body: String)
    case decodingFailure(underlying: Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to construct a valid API request URL."
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let body):
            return "Monzo API returned HTTP \(code): \(body)"
        case .decodingFailure(let error):
            return "Failed to decode API response: \(error.localizedDescription)"
        case .unauthorized:
            return "Session expired. Sign in again."
        }
    }
}

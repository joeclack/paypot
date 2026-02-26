import Foundation

struct MonzoService {

    private let session: URLSession
    private let baseURL: URL
    private let authManager: AuthManager

    init(
        authManager: AuthManager,
        baseURL: URL = Config.monzoBaseURL,
        session: URLSession = .shared
    ) {
        self.authManager = authManager
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Public API

    func whoAmI() async throws -> WhoAmIResponse {
        let url = baseURL.appendingPathComponent("ping/whoami")
        let request = authorisedRequest(url: url)
        return try await perform(request)
    }

    func getAccounts() async throws -> [Account] {
        let url = baseURL.appendingPathComponent("accounts")
        let request = authorisedRequest(url: url)
        let response: AccountsResponse = try await perform(request)
        return response.accounts
    }

    func getBalance(accountId: String) async throws -> Balance {
        var components = URLComponents(url: baseURL.appendingPathComponent("balance"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "account_id", value: accountId)]
        guard let url = components.url else { throw MonzoError.invalidURL }
        let request = authorisedRequest(url: url)
        return try await perform(request)
    }

    /// Returns only non-deleted pots.
    func getPots(accountId: String) async throws -> [Pot] {
        var components = URLComponents(url: baseURL.appendingPathComponent("pots"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "current_account_id", value: accountId)]
        guard let url = components.url else { throw MonzoError.invalidURL }
        let request = authorisedRequest(url: url)
        let response: PotsResponse = try await perform(request)
        return response.pots.filter { !$0.deleted }
    }

    func getTransactions(accountId: String, since: Date) async throws -> [Transaction] {
        var components = URLComponents(url: baseURL.appendingPathComponent("transactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "account_id", value: accountId),
            URLQueryItem(name: "since", value: Self.iso8601Formatter.string(from: since)),
            URLQueryItem(name: "expand[]", value: "merchant"),
        ]
        guard let url = components.url else { throw MonzoError.invalidURL }
        let request = authorisedRequest(url: url)
        let response: TransactionsResponse = try await perform(request)
        return response.transactions
    }

    /// Withdraws `amount` pence from `potId` back into `accountId`.
    /// Returns the updated pot.
    func withdrawFromPot(potId: String, accountId: String, amount: Int) async throws -> Pot {
        let url = baseURL
            .appendingPathComponent("pots")
            .appendingPathComponent(potId)
            .appendingPathComponent("withdraw")

        var request = authorisedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyFields: [(String, String)] = [
            ("destination_account_id", accountId),
            ("amount", String(amount)),
            ("dedupe_id", UUID().uuidString),
        ]
        request.httpBody = formURLEncoded(bodyFields)

        return try await perform(request)
    }

    /// Deposits `amount` pence from `accountId` into `potId`.
    /// Returns the updated pot.
    func depositToPot(potId: String, accountId: String, amount: Int) async throws -> Pot {
        let url = baseURL
            .appendingPathComponent("pots")
            .appendingPathComponent(potId)
            .appendingPathComponent("deposit")

        var request = authorisedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Stamp dedupe_id before calling perform so all retries reuse the same ID.
        let bodyFields: [(String, String)] = [
            ("source_account_id", accountId),
            ("amount", String(amount)),
            ("dedupe_id", UUID().uuidString),
        ]
        request.httpBody = formURLEncoded(bodyFields)

        return try await perform(request)
    }

    // MARK: - Private Helpers

    private func authorisedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(authManager.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Handles 401 by refreshing the token and retrying once.
    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            return try await performRetrying(request)
        } catch MonzoError.unauthorized {
            try await authManager.refreshAccessToken()
            var refreshedRequest = request
            refreshedRequest.setValue(
                "Bearer \(authManager.accessToken ?? "")",
                forHTTPHeaderField: "Authorization"
            )
            return try await performRetrying(refreshedRequest)
        }
    }

    /// Up to 3 attempts with exponential backoff for network / 5xx failures.
    /// Throws `.unauthorized` immediately on 401 (handled by `perform`).
    private func performRetrying<T: Decodable>(_ request: URLRequest) async throws -> T {
        let maxAttempts = 3
        let backoffSeconds = [1.0, 2.0, 4.0]

        for attempt in 0..<maxAttempts {
            let isLast = attempt == maxAttempts - 1

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                if isLast { throw MonzoError.networkFailure(underlying: error) }
                try await Task.sleep(for: .seconds(backoffSeconds[attempt]))
                continue
            }

            guard let http = response as? HTTPURLResponse else {
                if isLast { throw MonzoError.networkFailure(underlying: URLError(.badServerResponse)) }
                try await Task.sleep(for: .seconds(backoffSeconds[attempt]))
                continue
            }

            if http.statusCode == 401 {
                throw MonzoError.unauthorized
            }

            if (500...599).contains(http.statusCode) {
                if isLast {
                    let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                    throw MonzoError.httpError(statusCode: http.statusCode, body: body)
                }
                try await Task.sleep(for: .seconds(backoffSeconds[attempt]))
                continue
            }

            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                throw MonzoError.httpError(statusCode: http.statusCode, body: body)
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw MonzoError.decodingFailure(underlying: error)
            }
        }

        preconditionFailure("Exhausted retry loop without returning or throwing")
    }

    private func formURLEncoded(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        let encoded = fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    // MARK: - Decoder

    // Computed to avoid JSONDecoder Sendable issues in Swift 6.
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.iso8601Formatter.date(from: string) { return date }
            if let date = Self.iso8601FormatterNoMillis.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        return d
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601FormatterNoMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Who Am I

struct WhoAmIResponse: Decodable {
    let authenticated: Bool
    let clientId: String
    let userId: String
}

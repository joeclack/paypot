import Foundation
import UIKit

@MainActor
@Observable
class AuthManager {
    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    var isAuthenticated: Bool { accessToken != nil && !isAwaitingScaApproval }
    var isSigningIn: Bool { pendingState != nil }
    var isAwaitingScaApproval = false
    var hasReceivedCode: Bool { pendingCode != nil }
    var signInError: String?

    private(set) var connectedAt: Date?

    private(set) var tokenExpiresAt: Date?

    private let accessTokenKey   = "monzo.accessToken"
    private let refreshTokenKey  = "monzo.refreshToken"
    private let connectedAtKey   = "monzo.connectedAt"
    private let tokenExpiryKey   = "monzo.tokenExpiresAt"
    private var pendingState: String?
    private var pendingCode: String?
    private var pollingTask: Task<Void, Never>?
    private var scaPollingTask: Task<Void, Never>?
    private var lastPollingStart: Date = .distantPast

    init() {
        accessToken = KeychainHelper.load(for: accessTokenKey)
        refreshToken = KeychainHelper.load(for: refreshTokenKey)
        if let interval = UserDefaults.standard.object(forKey: connectedAtKey) as? Double {
            connectedAt = Date(timeIntervalSince1970: interval)
        }
        if let interval = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Double {
            tokenExpiresAt = Date(timeIntervalSince1970: interval)
        }
    }

    /// Refreshes the access token if it expires within the next 5 minutes.
    /// Safe to call on every launch — no-ops if the token is still healthy.
    func refreshIfNeeded() async {
        guard isAuthenticated else { return }
        if let expiry = tokenExpiresAt, expiry.timeIntervalSinceNow > 300 {
            // Token still has more than 5 minutes left — no refresh needed
            return
        }
        #if DEBUG
        print("[Auth] refreshIfNeeded — token expiring soon or expiry unknown, refreshing…")
        #endif
        try? await refreshAccessToken()
    }

    // MARK: - Public API

    func signIn() {
        pollingTask?.cancel()
        pollingTask = nil
        pendingCode = nil
        let state = UUID().uuidString
        pendingState = state
        signInError = nil
        #if DEBUG
        print("[Auth] signIn() — state=\(state)")
        #endif

        var components = URLComponents(string: "https://auth.monzo.com")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Config.monzoClientId),
            URLQueryItem(name: "redirect_uri", value: Config.monzoRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = components.url else {
            signInError = MonzoError.invalidURL.localizedDescription
            pendingState = nil
            return
        }
        UIApplication.shared.open(authURL, options: [:], completionHandler: nil)
    }

    /// Called from RootView's onOpenURL. Stores the auth code and begins polling
    /// the token endpoint until the exchange succeeds.
    func handleIncomingURL(_ url: URL) {
        #if DEBUG
        print("[Auth] handleIncomingURL — \(url.absoluteString)")
        #endif
        guard url.scheme == "paypot" else {
            #if DEBUG
            print("[Auth] ❌ wrong scheme: \(url.scheme ?? "nil")")
            #endif
            return
        }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            #if DEBUG
            print("[Auth] ❌ failed to parse URL components")
            #endif
            return
        }
        guard let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            #if DEBUG
            print("[Auth] ❌ no 'code' param — items: \(comps.queryItems ?? [])")
            #endif
            return
        }
        guard let expectedState = pendingState else {
            #if DEBUG
            print("[Auth] ❌ no pendingState — was signIn() called?")
            #endif
            return
        }
        let receivedState = comps.queryItems?.first(where: { $0.name == "state" })?.value
        guard receivedState == expectedState else {
            #if DEBUG
            print("[Auth] ❌ state mismatch — expected=\(expectedState) got=\(receivedState ?? "nil")")
            #endif
            return
        }
        #if DEBUG
        print("[Auth] ✅ code received, starting polling")
        #endif
        pendingCode = code
        startPolling(code: code)
    }

    /// Called when the app returns to foreground while waiting for the code exchange.
    func retryPendingExchange() {
        guard let code = pendingCode else {
            #if DEBUG
            print("[Auth] retryPendingExchange — no pendingCode, nothing to do")
            #endif
            return
        }
        guard Date.now.timeIntervalSince(lastPollingStart) > 5 else {
            #if DEBUG
            print("[Auth] retryPendingExchange — polling started recently, skipping")
            #endif
            return
        }
        #if DEBUG
        print("[Auth] retryPendingExchange — restarting polling")
        #endif
        startPolling(code: code)
    }

    /// Called when the app returns to foreground while waiting for SCA approval.
    func retryScaApprovalCheck() {
        guard isAwaitingScaApproval else { return }
        #if DEBUG
        print("[Auth] retryScaApprovalCheck — restarting SCA poll")
        #endif
        startScaPolling()
    }

    func cancelSignIn() {
        pollingTask?.cancel()
        pollingTask = nil
        pendingState = nil
        pendingCode = nil
        signInError = nil
        if isAwaitingScaApproval {
            signOut()
        }
    }

    func refreshAccessToken() async throws {
        guard let refreshToken else { throw MonzoError.unauthorized }
        try await postTokenRequest([
            ("grant_type", "refresh_token"),
            ("client_id", Config.monzoClientId),
            ("client_secret", Config.monzoClientSecret),
            ("refresh_token", refreshToken),
        ])
    }

    func signOut() {
        scaPollingTask?.cancel()
        scaPollingTask = nil
        isAwaitingScaApproval = false
        accessToken = nil
        refreshToken = nil
        connectedAt = nil
        tokenExpiresAt = nil
        KeychainHelper.delete(for: accessTokenKey)
        KeychainHelper.delete(for: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: connectedAtKey)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
    }

    // MARK: - Private Helpers

    private func startPolling(code: String) {
        pollingTask?.cancel()
        lastPollingStart = .now
        #if DEBUG
        print("[Auth] startPolling — code=\(code.prefix(8))…")
        #endif
        pollingTask = Task {
            var attempt = 0
            while !Task.isCancelled && pendingState != nil {
                attempt += 1
                #if DEBUG
                print("[Auth] polling attempt \(attempt)…")
                #endif
                do {
                    try await postTokenRequest([
                        ("grant_type", "authorization_code"),
                        ("client_id", Config.monzoClientId),
                        ("client_secret", Config.monzoClientSecret),
                        ("redirect_uri", Config.monzoRedirectURI),
                        ("code", code),
                    ])
                    #if DEBUG
                    print("[Auth] ✅ token exchange succeeded on attempt \(attempt)")
                    #endif
                    pendingState = nil
                    pendingCode = nil
                    isAwaitingScaApproval = true
                    startScaPolling()
                    return
                } catch {
                    if case .httpError(let status, let body) = error as? MonzoError,
                       status == 401, body.contains("bad_authorization_code") {
                        #if DEBUG
                        print("[Auth] ❌ code already consumed — stopping poll")
                        #endif
                        signInError = "Sign-in timed out. Please try again."
                        pendingState = nil
                        pendingCode = nil
                        return
                    }
                    #if DEBUG
                    print("[Auth] attempt \(attempt) failed: \(error)")
                    #endif
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            #if DEBUG
            print("[Auth] polling loop exited — cancelled=\(Task.isCancelled)")
            #endif
        }
    }

    /// Polls GET /accounts every 2 s. When the response is 2xx, SCA has been approved
    /// and isAwaitingScaApproval is cleared, making isAuthenticated true.
    private func startScaPolling() {
        scaPollingTask?.cancel()
        #if DEBUG
        print("[Auth] startScaPolling — waiting for Monzo SCA approval")
        #endif
        scaPollingTask = Task {
            var attempt = 0
            while !Task.isCancelled && isAwaitingScaApproval {
                attempt += 1
                #if DEBUG
                print("[Auth] SCA check \(attempt)…")
                #endif
                do {
                    var request = URLRequest(url: URL(string: "https://api.monzo.com/accounts")!)
                    request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        #if DEBUG
                        print("[Auth] ✅ SCA approved — navigating to dashboard")
                        #endif
                        isAwaitingScaApproval = false
                        connectedAt = Date()
                        UserDefaults.standard.set(connectedAt!.timeIntervalSince1970, forKey: connectedAtKey)
                        return
                    }
                    #if DEBUG
                    print("[Auth] SCA not yet approved — retrying in 2s")
                    #endif
                } catch {
                    #if DEBUG
                    print("[Auth] SCA check error: \(error)")
                    #endif
                }
                try? await Task.sleep(for: .seconds(0.6))
            }
            #if DEBUG
            print("[Auth] SCA polling exited — cancelled=\(Task.isCancelled)")
            #endif
        }
    }

    private func postTokenRequest(_ fields: [(String, String)]) async throws {
        var request = URLRequest(url: URL(string: "https://api.monzo.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(fields)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MonzoError.networkFailure(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MonzoError.networkFailure(underlying: URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
            throw MonzoError.httpError(statusCode: http.statusCode, body: body)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(access: tokenResponse.accessToken, refresh: tokenResponse.refreshToken, expiresIn: tokenResponse.expiresIn)
        #if DEBUG
        print("[Auth] postTokenRequest — access=\(tokenResponse.accessToken.prefix(8))… refresh=\(tokenResponse.refreshToken != nil ? "yes" : "none") expiresIn=\(tokenResponse.expiresIn.map(String.init) ?? "unknown")")
        #endif
    }

    private func storeTokens(access: String, refresh: String?, expiresIn: Int? = nil) {
        accessToken = access
        KeychainHelper.save(access, for: accessTokenKey)
        if let refresh {
            refreshToken = refresh
            KeychainHelper.save(refresh, for: refreshTokenKey)
        }
        if let seconds = expiresIn {
            tokenExpiresAt = Date().addingTimeInterval(TimeInterval(seconds))
            UserDefaults.standard.set(tokenExpiresAt!.timeIntervalSince1970, forKey: tokenExpiryKey)
        }
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
}

// MARK: - Private Models

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?   // absent in Monzo's pre-SCA response
    let expiresIn: Int?         // seconds until access token expires

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
    }
}

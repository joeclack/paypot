import Foundation

enum Config {
    static let monzoClientId: String = {
        guard let value = Bundle.main.infoDictionary?["MonzoClientId"] as? String, !value.isEmpty else {
            fatalError("MONZO_CLIENT_ID not set — copy Secrets.xcconfig.example to Secrets.xcconfig and fill in your credentials")
        }
        return value
    }()

    static let monzoClientSecret: String = {
        guard let value = Bundle.main.infoDictionary?["MonzoClientSecret"] as? String, !value.isEmpty else {
            fatalError("MONZO_CLIENT_SECRET not set — copy Secrets.xcconfig.example to Secrets.xcconfig and fill in your credentials")
        }
        return value
    }()

    static let monzoRedirectURI = "https://joeclack.github.io/auth-paypot"
    static let monzoBaseURL = URL(string: "https://api.monzo.com")!
}

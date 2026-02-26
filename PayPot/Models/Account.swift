import Foundation

struct Account: Codable, Identifiable {
    let id: String
    let description: String
    let type: String
    let currency: String
    let countryCode: String
    let owners: [Owner]

    struct Owner: Codable {
        let userId: String
        let preferredName: String
        let preferredFirstName: String
    }
}

struct AccountsResponse: Codable {
    let accounts: [Account]
}

import Foundation

struct Transaction: Codable, Identifiable {
    let id: String
    let created: Date
    let description: String
    /// Amount in pence. Negative = debit (money out), positive = credit (money in).
    let amount: Int
    let currency: String
    let notes: String
    let category: String
    let metadata: [String: String]
    /// Present when expand[]=merchant is passed and a merchant was matched.
    let merchant: Merchant?
    /// Present for bank transfers, standing orders, etc.
    let counterparty: Counterparty?

    struct Merchant: Codable {
        let name: String
    }

    struct Counterparty: Codable {
        let name: String?
    }
}

struct TransactionsResponse: Codable {
    let transactions: [Transaction]
}

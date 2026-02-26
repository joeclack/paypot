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

// MARK: - Transaction Helpers (non-breaking)
extension Transaction {
    /// True if the transaction is money out (negative amount)
    var isDebit: Bool { amount < 0 }

    /// The absolute value of the amount in pence
    var absoluteAmount: Int { abs(amount) }

    /// A user-facing primary name for the transaction
    var displayName: String {
        if let merchantName = merchant?.name, !merchantName.isEmpty {
            return merchantName
        }
        if let cpName = counterparty?.name, !cpName.isEmpty {
            return cpName
        }
        return description
    }

    /// Merchant or counterparty name if available, else nil
    var merchantOrCounterparty: String? {
        if let merchantName = merchant?.name, !merchantName.isEmpty { return merchantName }
        if let cpName = counterparty?.name, !cpName.isEmpty { return cpName }
        return nil
    }

    /// Formatted amount string using the provided or intrinsic currency
    func formattedAmount(currency overrideCode: String? = nil) -> String {
        let pounds = Double(absoluteAmount) / 100.0
        let code = overrideCode ?? currency
        let formatted = pounds.formatted(.currency(code: code))
        return isDebit ? "-\(formatted)" : formatted
    }

    /// A medium-style date string for the created date
    var createdDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: created)
    }

    /// A date + time string for the created date (abbreviated date, short time)
    var createdDateTimeString: String {
        created.formatted(date: .abbreviated, time: .shortened)
    }

    /// Amount expressed as a pounds string without currency symbol (e.g., 12.34)
    var amountPoundsString: String {
        String(format: "%.2f", Double(absoluteAmount) / 100.0)
    }

    /// True if a merchant or counterparty name is available and non-empty
    var hasMerchantOrCounterparty: Bool {
        if let merchantName = merchant?.name, !merchantName.isEmpty { return true }
        if let cpName = counterparty?.name, !cpName.isEmpty { return true }
        return false
    }

    /// Lowercased strings useful for client-side searching
    var searchableStrings: [String] {
        var values: [String] = []
        values.append(description.lowercased())
        values.append(createdDateString.lowercased())
        if let m = merchant?.name { values.append(m.lowercased()) }
        if let c = counterparty?.name { values.append(c.lowercased()) }
        values.append(category.lowercased())
        // Amount as pounds string (e.g., 12.34)
        values.append(amountPoundsString)
        return values
    }
}

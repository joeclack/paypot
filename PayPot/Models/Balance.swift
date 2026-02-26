import Foundation

struct Balance: Codable {
    /// Current cleared balance in pence.
    let balance: Int
    /// Balance including pending transactions, in pence.
    let totalBalance: Int
    let currency: String
    /// Amount spent today in pence. Monzo returns this as a negative integer.
    let spendToday: Int
}

import Foundation

struct SavingsAccount: Codable, Identifiable {
    let id: String
    var name: String
    var balancePence: Int
    var lastUpdated: Date
    var quickAddAmounts: [Int]  // pence — e.g. [40000] = £400 button
}

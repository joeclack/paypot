import Foundation

struct Pot: Codable, Identifiable {
    let id: String
    let name: String
    let style: String
    /// Current balance in pence.
    let balance: Int
    let currency: String
    /// Soft-deleted pots still appear in the API — filtered out by MonzoService.
    let deleted: Bool
}

struct PotsResponse: Codable {
    let pots: [Pot]
}

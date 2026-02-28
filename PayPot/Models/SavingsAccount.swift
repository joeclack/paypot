import Foundation

enum AccountType: String, Codable, CaseIterable {
    case generalSavings      = "generalSavings"
    case cashISA             = "cashISA"
    case lisa                = "lisa"
    case stocksAndSharesISA  = "stocksAndSharesISA"
    case helpToBuyISA        = "helpToBuyISA"
    case pension             = "pension"

    var label: String {
        switch self {
        case .generalSavings:     return "Savings"
        case .cashISA:            return "Cash ISA"
        case .lisa:               return "LISA"
        case .stocksAndSharesISA: return "Stocks & Shares ISA"
        case .helpToBuyISA:       return "Help to Buy ISA"
        case .pension:            return "Pension"
        }
    }

    var icon: String {
        switch self {
        case .generalSavings:     return "building.columns"
        case .cashISA:            return "banknote"
        case .lisa:               return "house"
        case .stocksAndSharesISA: return "chart.line.uptrend.xyaxis"
        case .helpToBuyISA:       return "key"
        case .pension:            return "person.crop.circle.badge.clock"
        }
    }

    /// Fraction of balance accessible as cash, accounting for penalties.
    var cashFraction: Double {
        switch self {
        case .lisa:    return 0.75  // 25% withdrawal penalty outside qualifying circumstances
        case .pension: return 0.0   // Inaccessible until retirement age
        default:       return 1.0
        }
    }

    var cashNote: String? {
        switch self {
        case .lisa:    return "25% penalty on withdrawal — only 75% is accessible"
        case .pension: return "Not accessible until retirement age"
        default:       return nil
        }
    }
}

struct SavingsAccount: Codable, Identifiable {
    let id: String
    var name: String
    var balancePence: Int
    var lastUpdated: Date
    var quickAddAmounts: [Int]  // pence — e.g. [40000] = £400 button
    var accountType: AccountType

    init(id: String, name: String, balancePence: Int, lastUpdated: Date, quickAddAmounts: [Int], accountType: AccountType = .generalSavings) {
        self.id = id
        self.name = name
        self.balancePence = balancePence
        self.lastUpdated = lastUpdated
        self.quickAddAmounts = quickAddAmounts
        self.accountType = accountType
    }

    // Custom decoder so existing saved accounts without accountType default to .generalSavings
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,     forKey: .id)
        name            = try c.decode(String.self,     forKey: .name)
        balancePence    = try c.decode(Int.self,        forKey: .balancePence)
        lastUpdated     = try c.decode(Date.self,       forKey: .lastUpdated)
        quickAddAmounts = try c.decode([Int].self,      forKey: .quickAddAmounts)
        accountType     = try c.decodeIfPresent(AccountType.self, forKey: .accountType) ?? .generalSavings
    }
}

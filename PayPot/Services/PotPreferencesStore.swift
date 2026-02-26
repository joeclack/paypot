import Foundation

struct StoredPot: Codable, Identifiable {
    let id: String
    let name: String
}

enum PotCategory: String, Codable, CaseIterable {
    case daily   = "daily"
    case monthly = "monthly"
    var label: String { rawValue.capitalized }
}

enum PaydaySchedule: Equatable {
    case fixedDay(Int)
    case lastWorkingDay
}

extension PaydaySchedule: Codable {
    private enum CodingKeys: String, CodingKey { case type, day }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixedDay(let d):
            try c.encode("fixedDay", forKey: .type)
            try c.encode(d, forKey: .day)
        case .lastWorkingDay:
            try c.encode("lastWorkingDay", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "fixedDay":
            self = .fixedDay(try c.decode(Int.self, forKey: .day))
        default:
            self = .lastWorkingDay
        }
    }
}

@MainActor
@Observable
final class PotPreferencesStore {
    enum PotFilter: String { case all, favourites }

    private(set) var favouriteOrder: [String]       // ordered list of budgeted pot IDs
    private(set) var showEmptyPots: Bool
    private(set) var potFilter: PotFilter
    private(set) var salaryPence: Int
    private(set) var potAllocations: [String: Int]
    private(set) var useBalanceForSpending: Bool
    private(set) var customPots: [StoredPot]
    private(set) var paydaySchedule: PaydaySchedule?
    private(set) var bacsEarlyPayment: Bool
    private(set) var potCategories: [String: PotCategory]
    private(set) var cachedPotNames: [String: String]
    private(set) var cachedPotBalances: [String: Int]
    private(set) var cachedAccountBalance: Balance?

    private enum Keys {
        static let favouritePotIds        = "pot.favouriteIds"
        static let showEmptyPots          = "pot.showEmpty"
        static let potFilter              = "pot.filter"
        static let favouriteNames         = "pot.favouriteNames"
        static let salaryPence            = "budget.salaryPence"
        static let potAllocations         = "budget.potAllocations"
        static let useBalanceForSpending  = "budget.useBalanceForSpending"
        static let customPots             = "budget.customPots"
        static let paydaySchedule         = "budget.paydaySchedule"
        static let bacsEarlyPayment       = "budget.bacsEarlyPayment"
        static let potCategories          = "budget.potCategories"
        static let cachedPotNames         = "cache.potNames"
        static let cachedPotBalances      = "cache.potBalances"
        static let cachedAccountBalance   = "cache.accountBalance"
    }

    init() {
        favouriteOrder        = UserDefaults.standard.stringArray(forKey: Keys.favouritePotIds) ?? []
        showEmptyPots         = UserDefaults.standard.bool(forKey: Keys.showEmptyPots)
        potFilter             = PotFilter(rawValue: UserDefaults.standard.string(forKey: Keys.potFilter) ?? "") ?? .all
        salaryPence           = UserDefaults.standard.integer(forKey: Keys.salaryPence)
        potAllocations        = (UserDefaults.standard.dictionary(forKey: Keys.potAllocations) as? [String: Int]) ?? [:]
        useBalanceForSpending = UserDefaults.standard.bool(forKey: Keys.useBalanceForSpending)
        if let data = UserDefaults.standard.data(forKey: Keys.customPots),
           let stored = try? JSONDecoder().decode([StoredPot].self, from: data) {
            customPots = stored
        } else {
            customPots = []
        }
        if let data = UserDefaults.standard.data(forKey: Keys.paydaySchedule),
           let stored = try? JSONDecoder().decode(PaydaySchedule.self, from: data) {
            paydaySchedule = stored
        } else {
            paydaySchedule = nil
        }
        bacsEarlyPayment = UserDefaults.standard.bool(forKey: Keys.bacsEarlyPayment)
        if let data = UserDefaults.standard.data(forKey: Keys.potCategories),
           let stored = try? JSONDecoder().decode([String: PotCategory].self, from: data) {
            potCategories = stored
        } else {
            potCategories = [:]
        }
        cachedPotNames    = (UserDefaults.standard.dictionary(forKey: Keys.cachedPotNames) as? [String: String]) ?? [:]
        cachedPotBalances = (UserDefaults.standard.dictionary(forKey: Keys.cachedPotBalances) as? [String: Int]) ?? [:]
        if let data = UserDefaults.standard.data(forKey: Keys.cachedAccountBalance),
           let stored = try? JSONDecoder().decode(Balance.self, from: data) {
            cachedAccountBalance = stored
        } else {
            cachedAccountBalance = nil
        }
    }

    func cacheLiveData(pots: [Pot], balance: Balance) {
        for pot in pots {
            cachedPotNames[pot.id] = pot.name
            cachedPotBalances[pot.id] = pot.balance
        }
        cachedAccountBalance = balance
        UserDefaults.standard.set(cachedPotNames, forKey: Keys.cachedPotNames)
        UserDefaults.standard.set(cachedPotBalances, forKey: Keys.cachedPotBalances)
        if let data = try? JSONEncoder().encode(balance) {
            UserDefaults.standard.set(data, forKey: Keys.cachedAccountBalance)
        }
    }

    var totalAllocatedPence: Int { potAllocations.values.reduce(0, +) }
    var unbudgetedPence: Int { salaryPence - totalAllocatedPence }

    func isFavourite(_ id: String) -> Bool { favouriteOrder.contains(id) }

    func addFavourite(id: String, name: String) {
        guard !favouriteOrder.contains(id) else { return }
        favouriteOrder.append(id)
        persistOrder()
        persistName(id: id, name: name)
    }

    func removeFavourite(id: String) {
        favouriteOrder.removeAll { $0 == id }
        persistOrder()
    }

    func moveFavourite(from source: IndexSet, to destination: Int) {
        let moved = source.sorted(by: >).map { favouriteOrder.remove(at: $0) }.reversed()
        let adjusted = destination - source.filter { $0 < destination }.count
        favouriteOrder.insert(contentsOf: moved, at: min(adjusted, favouriteOrder.count))
        persistOrder()
    }

    func setShowEmptyPots(_ show: Bool) {
        showEmptyPots = show
        UserDefaults.standard.set(show, forKey: Keys.showEmptyPots)
    }

    func setFilter(_ filter: PotFilter) {
        potFilter = filter
        UserDefaults.standard.set(filter.rawValue, forKey: Keys.potFilter)
    }

    func setSalary(_ pence: Int) {
        salaryPence = pence
        UserDefaults.standard.set(pence, forKey: Keys.salaryPence)
    }

    func setAllocation(potId: String, amountPence: Int) {
        if amountPence == 0 { potAllocations.removeValue(forKey: potId) }
        else { potAllocations[potId] = amountPence }
        UserDefaults.standard.set(potAllocations, forKey: Keys.potAllocations)
    }

    func setUseBalanceForSpending(_ value: Bool) {
        useBalanceForSpending = value
        UserDefaults.standard.set(value, forKey: Keys.useBalanceForSpending)
    }

    func addCustomPot(name: String) {
        let pot = StoredPot(id: UUID().uuidString, name: name)
        customPots.append(pot)
        saveCustomPots()
    }

    func removeCustomPot(id: String) {
        customPots.removeAll { $0.id == id }
        removeFavourite(id: id)
        potAllocations.removeValue(forKey: id)
        UserDefaults.standard.set(potAllocations, forKey: Keys.potAllocations)
        potCategories.removeValue(forKey: id)
        if let data = try? JSONEncoder().encode(potCategories) {
            UserDefaults.standard.set(data, forKey: Keys.potCategories)
        }
        saveCustomPots()
    }

    func setPotCategory(potId: String, category: PotCategory) {
        potCategories[potId] = category
        if let data = try? JSONEncoder().encode(potCategories) {
            UserDefaults.standard.set(data, forKey: Keys.potCategories)
        }
    }

    func setPaydaySchedule(_ schedule: PaydaySchedule?) {
        paydaySchedule = schedule
        if let schedule, let data = try? JSONEncoder().encode(schedule) {
            UserDefaults.standard.set(data, forKey: Keys.paydaySchedule)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.paydaySchedule)
        }
    }

    func setBacsEarlyPayment(_ value: Bool) {
        bacsEarlyPayment = value
        UserDefaults.standard.set(value, forKey: Keys.bacsEarlyPayment)
    }

    func resetBudgetData() {
        salaryPence = 0
        potAllocations = [:]
        favouriteOrder = []
        customPots = []
        potFilter = .all
        paydaySchedule = nil
        bacsEarlyPayment = false
        potCategories = [:]

        for key in [Keys.salaryPence, Keys.potAllocations, Keys.favouritePotIds,
                    Keys.favouriteNames, Keys.customPots, Keys.potFilter,
                    Keys.paydaySchedule, Keys.bacsEarlyPayment, Keys.potCategories] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func persistOrder() {
        UserDefaults.standard.set(favouriteOrder, forKey: Keys.favouritePotIds)
    }

    private func persistName(id: String, name: String) {
        var names = (UserDefaults.standard.dictionary(forKey: Keys.favouriteNames) as? [String: String]) ?? [:]
        names[id] = name
        UserDefaults.standard.set(names, forKey: Keys.favouriteNames)
    }

    private func saveCustomPots() {
        if let data = try? JSONEncoder().encode(customPots) {
            UserDefaults.standard.set(data, forKey: Keys.customPots)
        }
    }
}

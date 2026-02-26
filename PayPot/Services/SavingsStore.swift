import Foundation

@MainActor
@Observable
final class SavingsStore {

    private(set) var accounts: [SavingsAccount]

    private enum Keys {
        static let accounts = "savings.accounts"
    }

    var totalBalancePence: Int { accounts.map(\.balancePence).reduce(0, +) }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.accounts),
           let stored = try? JSONDecoder().decode([SavingsAccount].self, from: data) {
            accounts = stored
        } else {
            accounts = []
        }
    }

    func addAccount(name: String, initialBalancePence: Int) {
        let account = SavingsAccount(
            id: UUID().uuidString,
            name: name,
            balancePence: initialBalancePence,
            lastUpdated: Date(),
            quickAddAmounts: []
        )
        accounts.append(account)
        save()
    }

    func updateBalance(id: String, newBalancePence: Int) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].balancePence = newBalancePence
        accounts[idx].lastUpdated = Date()
        save()
    }

    func renameAccount(id: String, name: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].name = name
        save()
    }

    func setQuickAddAmounts(id: String, amounts: [Int]) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].quickAddAmounts = amounts
        save()
    }

    func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Keys.accounts)
        }
    }
}

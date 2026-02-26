import Foundation

enum ConnectionStatus {
    case unchecked
    case checking
    case active
    case expired
}

@MainActor
@Observable
class DashboardViewModel {
    var balance: Balance?
    var pots: [Pot] = []
    var transactions: [Transaction] = []
    var isLoading = false
    var errorMessage: String?
    var isSessionExpired = false
    private(set) var lastUpdated: Date?
    private(set) var connectionStatus: ConnectionStatus = .unchecked

    private let service: MonzoService
    private let authManager: AuthManager
    private(set) var accountId: String?

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.service = MonzoService(authManager: authManager)
    }

    /// Loads data only if not already cached. Safe to call on every view appearance.
    func load() async {
        guard authManager.isAuthenticated else { return }
        await authManager.refreshIfNeeded()
        guard balance == nil else { return }
        await fetch()
    }

    /// Clears all cached data. Call when budget data is deleted.
    func reset() {
        balance = nil
        pots = []
        transactions = []
        lastUpdated = nil
        errorMessage = nil
        isSessionExpired = false
        accountId = nil
    }

    /// Withdraws the full pot balance back to the main account, then refreshes.
    func emptyPot(_ pot: Pot) async throws {
        guard let accountId else { throw MonzoError.invalidURL }
        _ = try await service.withdrawFromPot(potId: pot.id, accountId: accountId, amount: pot.balance)
        await refresh()
    }

    func checkConnection() async {
        guard authManager.isAuthenticated else {
            connectionStatus = .expired
            return
        }
        connectionStatus = .checking
        do {
            let result = try await service.whoAmI()
            connectionStatus = result.authenticated ? .active : .expired
        } catch {
            connectionStatus = .expired
        }
    }

    /// Always fetches fresh data. Call from pull-to-refresh.
    func refresh() async {
        guard authManager.isAuthenticated else { return }
        await fetch()
    }

    private func fetch() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        isSessionExpired = false
        defer { isLoading = false }

        do {
            let accounts = try await service.getAccounts()
            guard let account = accounts.first(where: { $0.type == "uk_retail" }) ?? accounts.first else {
                errorMessage = "No account found."
                return
            }
            accountId = account.id

            async let balanceFetch = service.getBalance(accountId: account.id)
            async let potsFetch = service.getPots(accountId: account.id)
            (balance, pots) = try await (balanceFetch, potsFetch)

            // Fetch recent transactions (last 3 days)
            let sinceDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date().addingTimeInterval(-3*24*60*60)
            let fetchedTransactions = try await service.getTransactions(accountId: account.id, since: sinceDate)
            transactions = fetchedTransactions

            lastUpdated = Date()
            connectionStatus = .active
        } catch is CancellationError {
            // Pull-to-refresh was cancelled — ignore silently
        } catch MonzoError.unauthorized {
            isSessionExpired = true
            connectionStatus = .expired
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

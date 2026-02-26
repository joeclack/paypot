import SwiftUI
import LocalAuthentication

struct BudgetView: View {
    let viewModel: DashboardViewModel
    let prefsStore: PotPreferencesStore

    @State private var showEditSheet = false
    @State private var showPaydaySheet = false
    @State private var sortOrder: PotSortOrder = .manual
    @State private var showPaydayConfetti = false
    @State private var showSortSalary = false
    @AppStorage("app.paydayConfettiDate") private var paydayConfettiDate = ""

    enum PotSortOrder {
        case manual, balanceHigh, balanceLow
        var label: String {
            switch self {
            case .manual:      return "Default"
            case .balanceHigh: return "Balance: High to Low"
            case .balanceLow:  return "Balance: Low to High"
            }
        }
    }

    private var isOffline: Bool { viewModel.pots.isEmpty && !viewModel.isLoading }

    /// Monzo pots merged with user-created custom pots.
    /// Falls back to cached names/balances when offline.
    private var allPots: [Pot] {
        let customAsPots = prefsStore.customPots.map {
            Pot(id: $0.id, name: $0.name, style: "", balance: 0, currency: "GBP", deleted: false)
        }
        if !viewModel.pots.isEmpty {
            return viewModel.pots + customAsPots
        }
        // Offline: reconstruct favourited pots from last-known cache
        let cached = prefsStore.favouriteOrder.compactMap { id -> Pot? in
            guard let name = prefsStore.cachedPotNames[id] else { return nil }
            return Pot(id: id, name: name, style: "", balance: prefsStore.cachedPotBalances[id] ?? 0, currency: "GBP", deleted: false)
        }
        return cached + customAsPots
    }

    private func pots(for category: PotCategory) -> [Pot] {
        let ordered = prefsStore.favouriteOrder.compactMap { id in allPots.first { $0.id == id } }
        let filtered = ordered.filter { (prefsStore.potCategories[$0.id] ?? .daily) == category }
        switch sortOrder {
        case .manual:      return filtered
        case .balanceHigh: return filtered.sorted { $0.balance > $1.balance }
        case .balanceLow:  return filtered.sorted { $0.balance < $1.balance }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default:     return "Good evening"
        }
    }

    private var isPopulated: Bool {
        prefsStore.salaryPence > 0 && !prefsStore.favouriteOrder.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                incomeCard
                    .padding()
                    .padding(.bottom, 8)

                if prefsStore.favouriteOrder.isEmpty {
                    ContentUnavailableView(
                        "No Budget Set",
                        systemImage: "star",
                        description: Text("Tap ★ to set your salary and choose pots.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView {
                        potPage(for: .daily)
                        potPage(for: .monthly)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
            }
            .navigationTitle(greeting)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showPaydaySheet.toggle() } label: {
                        Image(systemName: prefsStore.paydaySchedule == nil ? "calendar" : "calendar.badge.checkmark")
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: showPaydaySheet)
                }
                if let countdown = paydayCountdown {
                    ToolbarItem(placement: .principal) {
                        Text(nextPaydayLabel(for: countdown.next))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(countdown.days == 0 ? Color.green : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassEffect(in: Capsule())
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            Text("Default").tag(PotSortOrder.manual)
                            Label("Balance: High to Low", systemImage: "arrow.down").tag(PotSortOrder.balanceHigh)
                            Label("Balance: Low to High", systemImage: "arrow.up").tag(PotSortOrder.balanceLow)
                        }
                    } label: {
                        Image(systemName: sortOrder == .manual ? "arrow.up.arrow.down" : "arrow.up.arrow.down.circle.fill")
                    }
                    Button { showEditSheet.toggle() } label: {
                        Image(systemName: "pencil")
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: showEditSheet)
                }
            }
            .sheet(isPresented: $showEditSheet) {
                BudgetEditSheet(viewModel: viewModel, prefsStore: prefsStore)
            }
            .sheet(isPresented: $showPaydaySheet) {
                PaydayEditSheet(prefsStore: prefsStore)
            }
//            .sheet(isPresented: $showSortSalary) {
//                SortSalarySheet()
//            }
            .overlay {
                if viewModel.isLoading {
                    LoadingOverlay()
                }
            }
            .overlay {
                if showPaydayConfetti {
                    ConfettiView()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .task {
                await viewModel.load()
                triggerPaydayConfettiIfNeeded()
            }
            .onChange(of: viewModel.lastUpdated) { _, _ in
                if let balance = viewModel.balance, !viewModel.pots.isEmpty {
                    prefsStore.cacheLiveData(pots: viewModel.pots, balance: balance)
                }
            }
        }
    }

    // MARK: - Payday Confetti

    private func triggerPaydayConfettiIfNeeded() {
        guard let schedule = prefsStore.paydaySchedule,
              let next = nextPayday(schedule: schedule, bacsEarly: prefsStore.bacsEarlyPayment),
              Calendar.current.isDateInToday(next) else { return }
        let today = Date().formatted(.iso8601.year().month().day())
        guard paydayConfettiDate != today else { return }
        paydayConfettiDate = today
        showPaydayConfetti = true
        showSortSalary = true
    }

    // MARK: - Pot Page

    @ViewBuilder
    private func potPage(for category: PotCategory) -> some View {
        let items = pots(for: category)
        VStack(spacing: 0) {
            HStack {
                Label(category.label, systemImage: category == .daily ? "sun.max" : "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(items.count) pot\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if items.isEmpty {
                ContentUnavailableView(
                    "No \(category.label) Pots",
                    systemImage: category == .daily ? "sun.max" : "calendar",
                    description: Text("Tap a pot and set its category to \"\(category.label)\".")
                )
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(items) { pot in
                            PotCard(pot: pot, prefsStore: prefsStore, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .refreshable { await viewModel.refresh() }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .tag(category)
    }

    // MARK: - Income Card

    private var paydayCountdown: (days: Int, next: Date)? {
        guard let schedule = prefsStore.paydaySchedule,
              let next = nextPayday(schedule: schedule, bacsEarly: prefsStore.bacsEarlyPayment) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: next)).day ?? 0
        guard days <= 7 else { return nil }
        return (days, next)
    }

    private var spendingProgress: Double {
        let budget = prefsStore.unbudgetedPence
        guard budget > 0 else { return 0 }
        let balance = (viewModel.balance ?? prefsStore.cachedAccountBalance)?.balance ?? 0
        return min(1.0, Double(balance) / Double(budget))
    }

    @ViewBuilder
    private var incomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Account balance
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let balance = viewModel.balance ?? prefsStore.cachedAccountBalance {
                    Text(pence: balance.balance)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    if viewModel.balance == nil {
                        Text("Offline")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("--")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            // Spending progress bar
            if prefsStore.unbudgetedPence > 0 {
                VStack(spacing: 6) {
                    ProgressView(value: spendingProgress)
                        .tint(spendingProgress < 0.25 ? .red : .green)
                    HStack {
                        Text("Spending balance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("of \(Text(pence: prefsStore.unbudgetedPence).monospacedDigit()) budget")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PotCard

private struct PotCard: View {
    let pot: Pot
    let prefsStore: PotPreferencesStore
    let viewModel: DashboardViewModel
    @State private var showSheet = false
    @State private var tapped = false

    private var allocation: Int { prefsStore.potAllocations[pot.id] ?? 0 }
    private var progress: Double {
        guard allocation > 0 else { return 0 }
        return min(1.0, Double(pot.balance) / Double(allocation))
    }

    var body: some View {
        Button {
            tapped.toggle()
            showSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(pot.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer()
                ProgressView(value: progress)
                    .tint(.green)
                HStack {
                    Text(pence: pot.balance)
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Spacer()
                    if allocation > 0 {
                        Text(pence: allocation)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Tap to budget")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapped)
        .sheet(isPresented: $showSheet) {
            PotEditSheet(pot: pot, prefsStore: prefsStore, viewModel: viewModel)
        }
    }
}

#Preview {
    BudgetView(
        viewModel: DashboardViewModel(authManager: AuthManager()),
        prefsStore: PotPreferencesStore()
    )
}

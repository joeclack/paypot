import SwiftUI

struct BudgetView: View {
    let viewModel: DashboardViewModel
    let prefsStore: PotPreferencesStore

    @State private var showEditSheet = false
    @State private var showPaydayConfetti = false
    @State private var showSortSalary = false
    @AppStorage("app.paydayConfettiDate") private var paydayConfettiDate = ""

    private var currentBalance: Balance? {
        viewModel.balance ?? prefsStore.cachedAccountBalance
    }

    private var spendingProgress: Double {
        let budget = prefsStore.unbudgetedPence
        guard budget > 0 else { return 0 }
        let balance = currentBalance?.balance ?? 0
        return min(1.0, max(0.0, Double(balance) / Double(budget)))
    }

    private var gaugeColor: Color {
        if spendingProgress > 0.5 { return .green }
        if spendingProgress > 0.25 { return .orange }
        return .red
    }

    private var budgetString: String {
        (Double(prefsStore.unbudgetedPence) / 100.0).formatted(.currency(code: "GBP"))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if !viewModel.isLoading && prefsStore.salaryPence == 0 {
                    ContentUnavailableView {
                        Label("No Budget Set", systemImage: "chart.pie")
                    } description: {
                        Text("Tap the pencil icon to set your salary and configure your spending pots.")
                    }
                } else {
                    VStack(spacing: 0) {
                        Spacer()
                        Button {
                            showEditSheet = true
                        } label: {
                            spendingGauge
                                .padding(.horizontal, 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .light), trigger: showEditSheet)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Budget")
            .navigationDestination(isPresented: $showEditSheet) {
                BudgetEditSheet(viewModel: viewModel, prefsStore: prefsStore)
            }
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
            .refreshable { await viewModel.refresh() }
            .onChange(of: viewModel.lastUpdated) { _, _ in
                if let balance = viewModel.balance, !viewModel.pots.isEmpty {
                    prefsStore.cacheLiveData(pots: viewModel.pots, balance: balance)
                }
            }
        }
    }

    // MARK: - Spending Gauge

    @ViewBuilder
    private var spendingGauge: some View {
        VStack(spacing: 28) {
            ZStack {
                // Track
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 24)

                // Progress arc
                Circle()
                    .trim(from: 0, to: spendingProgress)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: spendingProgress)

                // Center
                VStack(spacing: 6) {
                    if let balance = currentBalance {
                        Text(pence: balance.balance)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .contentTransition(.numericText())

                        if prefsStore.unbudgetedPence > 0 {
                            Text("of \(budgetString)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            let isAbove = (currentBalance?.balance ?? 0) >= prefsStore.unbudgetedPence
                            Text(isAbove ? "Above budget" : "")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(gaugeColor)
                                .contentTransition(.numericText())
                        }

                        if let countdown = paydayCountdown, countdown.days > 0 {
                            let daily = Double(balance.balance) / Double(countdown.days) / 100.0
                            Divider().padding(.horizontal, 24).padding(.vertical, 2)
                            Text("Spent today")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(daily, format: .currency(code: "GBP"))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }

                        if viewModel.balance == nil {
                            Text("Offline")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                        }
                    } else if !viewModel.isLoading {
                        Text("--")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(36)
            }
        }
    }

    // MARK: - Payday

    private var paydayCountdown: (days: Int, next: Date)? {
        guard let schedule = prefsStore.paydaySchedule,
              let next = nextPayday(schedule: schedule, bacsEarly: prefsStore.bacsEarlyPayment) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: next)).day ?? 0
        return (days, next)
    }

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
}

// MARK: - Preview

#Preview {
    BudgetView(
        viewModel: DashboardViewModel(authManager: AuthManager()),
        prefsStore: PotPreferencesStore()
    )
}

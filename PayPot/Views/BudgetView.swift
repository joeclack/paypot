import SwiftUI
import LocalAuthentication

struct BudgetView: View {
    let viewModel: DashboardViewModel
    let prefsStore: PotPreferencesStore

    @State private var showEditSheet = false
    @State private var showPaydaySheet = false
    @State private var sortOrder: PotSortOrder = .manual

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
                }
            }
            .sheet(isPresented: $showEditSheet) {
                BudgetEditSheet(viewModel: viewModel, prefsStore: prefsStore)
            }
            .sheet(isPresented: $showPaydaySheet) {
                PaydayEditSheet(prefsStore: prefsStore)
            }
            .overlay {
                if viewModel.isLoading {
                    LoadingOverlay()
                }
            }
            .task { await viewModel.load() }
            .onChange(of: viewModel.lastUpdated) { _, _ in
                if let balance = viewModel.balance, !viewModel.pots.isEmpty {
                    prefsStore.cacheLiveData(pots: viewModel.pots, balance: balance)
                }
            }
        }
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
            // Greeting

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

// MARK: - PotEditSheet

private struct PotEditSheet: View {
    let pot: Pot
    let prefsStore: PotPreferencesStore
    let viewModel: DashboardViewModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.biometricLockEnabled") private var biometricLockEnabled = false
    @State private var text: String
    @State private var selectedCategory: PotCategory
    @State private var showEmptyConfirm = false
    @State private var isEmptying = false
    @State private var actionError: String?
    @State private var successAmountPence: Int?
    @FocusState private var focused: Bool

    init(pot: Pot, prefsStore: PotPreferencesStore, viewModel: DashboardViewModel) {
        self.pot = pot
        self.prefsStore = prefsStore
        self.viewModel = viewModel
        let pence = prefsStore.potAllocations[pot.id] ?? 0
        _text = State(initialValue: pence == 0 ? "" : String(format: "%.2f", Double(pence) / 100.0))
        _selectedCategory = State(initialValue: prefsStore.potCategories[pot.id] ?? .daily)
    }

    private var allocation: Int { prefsStore.potAllocations[pot.id] ?? 0 }
    private var progress: Double {
        guard allocation > 0 else { return 0 }
        return min(1.0, Double(pot.balance) / Double(allocation))
    }
    private var formattedBalance: String {
        (Double(pot.balance) / 100.0).formatted(.currency(code: "GBP"))
    }

    var body: some View {
        if let amount = successAmountPence {
            EmptyPotSuccessView(amountPence: amount) { dismiss() }
        } else {
        NavigationStack {
            List {
                // Balance summary
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Balance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(pence: pot.balance)
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                        }
                        Spacer()
                        if allocation > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Budget")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(pence: allocation)
                                    .font(.title2.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    ProgressView(value: progress)
                        .tint(.green)
                }

                // Category picker
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(PotCategory.allCases, id: \.self) { cat in
                            Text(cat.label).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Budget input
                Section("Monthly Budget") {
                    TextField("0.00", text: $text)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .monospacedDigit()
                }

                // Pot actions
                if pot.balance > 0 {
                    Section("Actions") {
                        Button {
                            showEmptyConfirm = true
                        } label: {
                            HStack {
                                if isEmptying {
                                    ProgressView()
                                        .font(.title3)
                                } else {
                                    Image(systemName: "arrow.uturn.left.circle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.title3)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Empty Pot")
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text("Move \(formattedBalance) back to your account")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isEmptying)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(pot.name)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Failed to Empty Pot", isPresented: .init(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .alert("Empty \(pot.name)?", isPresented: $showEmptyConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Empty Pot", role: .destructive) {
                    let amount = pot.balance
                    isEmptying = true
                    Task {
                        if biometricLockEnabled {
                            let context = LAContext()
                            guard (try? await context.evaluatePolicy(
                                .deviceOwnerAuthentication,
                                localizedReason: "Confirm emptying \(pot.name)"
                            )) == true else {
                                isEmptying = false
                                return
                            }
                        }
                        do {
                            try await viewModel.emptyPot(pot)
                            successAmountPence = amount
                        } catch {
                            actionError = error.localizedDescription
                        }
                        isEmptying = false
                    }
                }
            } message: {
                Text("This will move \(formattedBalance) back to your main account balance. Only proceed if you're sure — make sure you have enough left to cover any outstanding bills or direct debits.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        } // NavigationStack
        } // else
    }

    private func save() {
        let pence: Int
        if let pounds = Double(text) {
            pence = Int((pounds * 100).rounded())
        } else {
            pence = 0
        }
        prefsStore.setAllocation(potId: pot.id, amountPence: pence)
        prefsStore.setPotCategory(potId: pot.id, category: selectedCategory)
        dismiss()
    }
}

// MARK: - BudgetEditSheet

private struct BudgetEditSheet: View {
    let viewModel: DashboardViewModel
    let prefsStore: PotPreferencesStore

    @Environment(\.dismiss) private var dismiss
    @State private var salaryText: String
    @State private var newPotName = ""
    @FocusState private var salaryFocused: Bool

    init(viewModel: DashboardViewModel, prefsStore: PotPreferencesStore) {
        self.viewModel = viewModel
        self.prefsStore = prefsStore
        let pence = prefsStore.salaryPence
        _salaryText = State(initialValue: pence == 0 ? "" : String(format: "%.2f", Double(pence) / 100.0))
    }

    private var allPots: [Pot] {
        let custom = prefsStore.customPots.map {
            Pot(id: $0.id, name: $0.name, style: "", balance: 0, currency: "GBP", deleted: false)
        }
        return viewModel.pots + custom
    }

    private var budgetedPots: [Pot] {
        prefsStore.favouriteOrder.compactMap { id in allPots.first { $0.id == id } }
    }

    private var availablePots: [Pot] {
        allPots.filter { !prefsStore.isFavourite($0.id) }
    }

    private var isCustomPot: (String) -> Bool {
        { id in prefsStore.customPots.contains { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly Salary") {
                    TextField("e.g. 2500", text: $salaryText)
                        .keyboardType(.decimalPad)
                        .focused($salaryFocused)
                }

                Section {
                    if budgetedPots.isEmpty {
                        Text("Add pots below to start budgeting.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(budgetedPots) { pot in
                            HStack {
                                Text(pot.name)
                                Spacer()
                                if isCustomPot(pot.id) {
                                    Button(role: .destructive) {
                                        prefsStore.removeCustomPot(id: pot.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { prefsStore.removeFavourite(id: budgetedPots[$0].id) }
                        }
                        .onMove { prefsStore.moveFavourite(from: $0, to: $1) }
                    }
                } header: {
                    Text("Budgeted Pots")
                } footer: {
                    if !budgetedPots.isEmpty {
                        Text("Swipe to remove. Drag to reorder.")
                    }
                }

                if !availablePots.isEmpty {
                    Section("Available Pots") {
                        ForEach(availablePots) { pot in
                            Button {
                                prefsStore.addFavourite(id: pot.id, name: pot.name)
                            } label: {
                                HStack {
                                    Text(pot.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                Section("Custom Pots") {
                    ForEach(prefsStore.customPots) { pot in
                        if !prefsStore.isFavourite(pot.id) {
                            HStack {
                                Text(pot.name)
                                Spacer()
                                Button(role: .destructive) {
                                    prefsStore.removeCustomPot(id: pot.id)
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        TextField("New pot name…", text: $newPotName)
                        Button("Add") {
                            let trimmed = newPotName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            prefsStore.addCustomPot(name: trimmed)
                            newPotName = ""
                        }
                        .disabled(newPotName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Toggle("Use balance for spending", isOn: Binding(
                        get: { prefsStore.useBalanceForSpending },
                        set: { prefsStore.setUseBalanceForSpending($0) }
                    ))
                }
            }
            .navigationTitle("Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if let pounds = Double(salaryText) {
                            prefsStore.setSalary(Int((pounds * 100).rounded()))
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { salaryFocused = false }
                }
            }
        }
    }
}

// MARK: - PaydayEditSheet

private struct PaydayEditSheet: View {
    let prefsStore: PotPreferencesStore

    @Environment(\.dismiss) private var dismiss

    enum ScheduleType: Hashable {
        case fixedDay, lastWorkingDay
        var label: String {
            switch self {
            case .fixedDay:       return "Fixed Day of Month"
            case .lastWorkingDay: return "Last Working Day"
            }
        }
    }

    @State private var scheduleType: ScheduleType
    @State private var fixedDay: Int
    @State private var fixedDayText: String
    @State private var bacsEarly: Bool

    init(prefsStore: PotPreferencesStore) {
        self.prefsStore = prefsStore
        switch prefsStore.paydaySchedule {
        case .fixedDay(let d):
            _scheduleType = State(initialValue: .fixedDay)
            _fixedDay = State(initialValue: d)
            _fixedDayText = State(initialValue: String(d))
        case .lastWorkingDay, nil:
            _scheduleType = State(initialValue: .lastWorkingDay)
            _fixedDay = State(initialValue: 1)
            _fixedDayText = State(initialValue: "1")
        }
        _bacsEarly = State(initialValue: prefsStore.bacsEarlyPayment)
    }

    private var currentSchedule: PaydaySchedule {
        switch scheduleType {
        case .fixedDay:       return .fixedDay(fixedDay)
        case .lastWorkingDay: return .lastWorkingDay
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pay Schedule") {
                    Picker("Type", selection: $scheduleType) {
                        ForEach([ScheduleType.fixedDay, .lastWorkingDay], id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if scheduleType == .fixedDay {
                        HStack {
                            Text("Day of the month")
                            Spacer()
                            TextField("1–31", text: $fixedDayText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 52)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                                .onChange(of: fixedDayText) { _, new in
                                    let digits = new.filter(\.isNumber)
                                    if let val = Int(digits) {
                                        let clamped = min(max(1, val), 31)
                                        fixedDay = clamped
                                        if val != clamped { fixedDayText = String(clamped) }
                                    } else {
                                        fixedDayText = digits
                                    }
                                }
                        }
                    }
                }

                Section {
                    Toggle("BACS early payment", isOn: $bacsEarly)
                } footer: {
                    Text("Monzo and some banks release BACS payroll a working day before the official payment date.")
                }

                Section("Next Payday") {
                    if let next = nextPayday(schedule: currentSchedule, bacsEarly: bacsEarly) {
                        HStack {
                            Text(nextPaydayLabel(for: next))
                                .font(.body.weight(.medium))
                                .foregroundStyle(Calendar.current.isDateInToday(next) ? .green : .primary)
                            Spacer()
                            Text(next, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                }

                if prefsStore.paydaySchedule != nil {
                    Section {
                        Button("Remove Pay Schedule", role: .destructive) {
                            prefsStore.setPaydaySchedule(nil)
                            prefsStore.setBacsEarlyPayment(false)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Payday Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        prefsStore.setPaydaySchedule(currentSchedule)
                        prefsStore.setBacsEarlyPayment(bacsEarly)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Payday helpers

private func nextPayday(schedule: PaydaySchedule, bacsEarly: Bool = false, after today: Date = Date()) -> Date? {
    let cal = Calendar.current
    let start = cal.startOfDay(for: today)
    for offset in 0...1 {
        guard let monthDate = cal.date(byAdding: .month, value: offset, to: start),
              let candidate = paydayInMonth(of: monthDate, schedule: schedule, bacsEarly: bacsEarly, cal: cal) else { continue }
        if candidate >= start { return candidate }
    }
    return nil
}

private func paydayInMonth(of date: Date, schedule: PaydaySchedule, bacsEarly: Bool, cal: Calendar) -> Date? {
    let year = cal.component(.year, from: date)
    let month = cal.component(.month, from: date)
    guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
          let range = cal.range(of: .day, in: .month, for: first),
          let lastDay = cal.date(from: DateComponents(year: year, month: month, day: range.count)) else { return nil }

    let base: Date
    switch schedule {
    case .fixedDay(let day):
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: min(day, range.count))) else { return nil }
        base = d
    case .lastWorkingDay:
        base = lastWorkingDay(before: lastDay, cal: cal)
    }

    return bacsEarly ? previousWorkingDay(before: base, cal: cal) : base
}

private func lastWorkingDay(before date: Date, cal: Calendar) -> Date {
    var d = date
    while [1, 7].contains(cal.component(.weekday, from: d)) {
        d = cal.date(byAdding: .day, value: -1, to: d)!
    }
    return d
}

private func previousWorkingDay(before date: Date, cal: Calendar) -> Date {
    var d = cal.date(byAdding: .day, value: -1, to: date)!
    while [1, 7].contains(cal.component(.weekday, from: d)) {
        d = cal.date(byAdding: .day, value: -1, to: d)!
    }
    return d
}

private func nextPaydayLabel(for date: Date) -> String {
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
    switch days {
    case 0:    return "Payday today!"
    case 1:    return "Payday tomorrow"
    case 2...6: return "Payday in \(days) days"
    default:   return "Next payday"
    }
}

// MARK: - EmptyPotSuccessView

private struct EmptyPotSuccessView: View {
    let amountPence: Int
    let onDone: () -> Void

    @State private var showCheck = false
    @State private var showText = false
    @State private var showConfetti = false

    private var formattedAmount: String {
        (Double(amountPence) / 100.0).formatted(.currency(code: "GBP"))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.green)
                        .scaleEffect(showCheck ? 1 : 0.1)
                        .opacity(showCheck ? 1 : 0)
                }

                VStack(spacing: 8) {
                    Text("Done!")
                        .font(.title.weight(.bold))
                    Text("\(formattedAmount) moved to your account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 12)

                Spacer()

                Button("Close") { onDone() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
                    .opacity(showText ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                showCheck = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                showText = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showConfetti = true
            }
        }
    }
}

// MARK: - ConfettiView

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
    let xDrift: CGFloat
    let speed: Double
    let delay: Double
}

private struct ConfettiView: View {
    private let pieces: [ConfettiPiece] = (0..<50).map { _ in
        ConfettiPiece(
            x: CGFloat.random(in: 0...1),
            color: [Color.green, .yellow, .orange, .pink, .blue, .purple, .mint].randomElement()!,
            size: CGFloat.random(in: 6...12),
            rotation: Double.random(in: 0...360),
            xDrift: CGFloat.random(in: -60...60),
            speed: Double.random(in: 0.8...1.4),
            delay: Double.random(in: 0...0.4)
        )
    }

    @State private var startDate: Date = .now

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                guard elapsed < 1.8 else { return }
                for piece in pieces {
                    let pieceElapsed = max(0, elapsed - piece.delay)
                    let progress = min(pieceElapsed / piece.speed, 1.0)
                    guard progress > 0 else { continue }
                    let x = piece.x * size.width + piece.xDrift * progress
                    let y = -20 + (size.height + 40) * progress
                    let angle = CGFloat((piece.rotation + progress * 540) * .pi / 180)
                    let transform = CGAffineTransform(translationX: x, y: y).rotated(by: angle)
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4,
                                     width: piece.size, height: piece.size / 2)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 2).applying(transform),
                        with: .color(piece.color)
                    )
                }
            }
        }
    }
}

#Preview {
    BudgetView(
        viewModel: DashboardViewModel(authManager: AuthManager()),
        prefsStore: PotPreferencesStore()
    )
}

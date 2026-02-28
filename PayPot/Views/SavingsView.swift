import SwiftUI

// MARK: - SavingsView

struct SavingsView: View {
    let store: SavingsStore

    @State private var showAddSheet = false
    @State private var selectedAccount: SavingsAccount?

    private var hasPenalties: Bool {
        store.accounts.contains { $0.accountType.cashFraction < 1.0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.accounts.isEmpty {
                        ContentUnavailableView(
                            "No Savings Accounts",
                            systemImage: "chart.line.uptrend.xyaxis.circle",
                            description: Text("Tap + to add your first savings account.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(store.accounts) { account in
                            SavingsAccountCard(account: account)
                                .onTapGesture { selectedAccount = account }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if hasPenalties {
                        HStack(spacing: 12) {
                            VStack(spacing: 1) {
                                Text(savingsPoundsString(store.totalBalancePence))
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                Text("Saved")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Divider().frame(height: 24)
                            VStack(spacing: 1) {
                                Text(savingsPoundsString(store.totalCashPence))
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.green)
                                Text("Cash")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .glassEffect(in: Capsule())
                    } else {
                        VStack(spacing: 1) {
                            Text(savingsPoundsString(store.totalBalancePence))
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                            Text("Total Savings")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .glassEffect(in: Capsule())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: showAddSheet)
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddAccountSheet(store: store)
            }
            .sheet(item: $selectedAccount) { account in
                AccountDetailSheet(store: store, account: account)
            }
        }
    }
}

// MARK: - Savings Account Card

private struct SavingsAccountCard: View {
    let account: SavingsAccount

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: account.accountType.icon)
                        .font(.caption2)
                    Text(account.accountType.label)
                        .font(.caption2.weight(.medium))
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(account.name)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                Text(savingsPoundsString(account.balancePence))
                    .font(.title.weight(.bold))
                    .monospacedDigit()

                if account.accountType.cashFraction < 1.0 {
                    let cashPence = Int(Double(account.balancePence) * account.accountType.cashFraction)
                    Text("Cash: \(savingsPoundsString(cashPence))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Text(savingsRelativeDate(account.lastUpdated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .cardGlow(cornerRadius: 12)
        .padding(.horizontal)
    }
}

// MARK: - Add Account Sheet

private struct AddAccountSheet: View {
    let store: SavingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var balanceText = ""
    @State private var accountType: AccountType = .generalSavings

    private var initialBalancePence: Int {
        let cleaned = balanceText.filter { $0.isNumber || $0 == "." }
        return Int((Double(cleaned) ?? 0) * 100)
    }

    private var canAdd: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $name)
                    HStack {
                        Text("£")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Account Type") {
                    Picker("Type", selection: $accountType) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    if let note = accountType.cashNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addAccount(
                            name: name.trimmingCharacters(in: .whitespaces),
                            initialBalancePence: initialBalancePence,
                            accountType: accountType
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }
}

// MARK: - Account Detail Sheet

struct AccountDetailSheet: View {
    let store: SavingsStore
    let account: SavingsAccount
    @Environment(\.dismiss) private var dismiss

    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var setBalanceText = ""
    @State private var customAddText = ""
    @State private var showCustomAdd = false

    private var displayAccount: SavingsAccount {
        store.accounts.first { $0.id == account.id } ?? account
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Balance header
                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: displayAccount.accountType.icon)
                            .font(.caption)
                        Text(displayAccount.accountType.label)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)

                    Text(displayAccount.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(savingsPoundsString(displayAccount.balancePence))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()

                    if displayAccount.accountType.cashFraction < 1.0 {
                        let balance = displayAccount.balancePence
                        let cashPence = Int(Double(balance) * displayAccount.accountType.cashFraction)
                        let penaltyPence = balance - cashPence

                        HStack(spacing: 0) {
                            VStack(spacing: 3) {
                                Text("You'd receive")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(savingsPoundsString(cashPence))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.green)
                            }
                            .frame(maxWidth: .infinity)

                            Divider().frame(height: 32)

                            VStack(spacing: 3) {
                                Text("Penalty")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(savingsPoundsString(penaltyPence))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        Text(displayAccount.accountType.cashNote ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    } else {
                        Text(savingsRelativeDate(displayAccount.lastUpdated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

                Divider()

                List {
                    // Quick-add
                    Section {
                        if !displayAccount.quickAddAmounts.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(displayAccount.quickAddAmounts, id: \.self) { amount in
                                        Button("+\(savingsPoundsString(amount))") {
                                            store.updateBalance(
                                                id: account.id,
                                                newBalancePence: displayAccount.balancePence + amount
                                            )
                                        }
                                        .buttonStyle(QuickAddButtonStyle())
                                    }
                                    Button {
                                        showCustomAdd.toggle()
                                    } label: {
                                        Label("Custom", systemImage: "plus")
                                    }
                                    .buttonStyle(QuickAddButtonStyle())
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        } else {
                            Button {
                                showCustomAdd.toggle()
                            } label: {
                                Label("Add Custom Amount", systemImage: "plus.circle")
                            }
                        }

                        if showCustomAdd {
                            HStack {
                                Text("£")
                                    .foregroundStyle(.secondary)
                                TextField("Amount to add", text: $customAddText)
                                    .keyboardType(.decimalPad)
                                Button("Add") {
                                    let cleaned = customAddText.filter { $0.isNumber || $0 == "." }
                                    let pence = Int((Double(cleaned) ?? 0) * 100)
                                    if pence > 0 {
                                        store.updateBalance(
                                            id: account.id,
                                            newBalancePence: displayAccount.balancePence + pence
                                        )
                                    }
                                    customAddText = ""
                                    showCustomAdd = false
                                }
                                .disabled(customAddText.isEmpty)
                            }
                        }
                    } header: {
                        Text("Quick Add")
                    }

                    // Set absolute balance
                    Section("Set Balance") {
                        HStack {
                            Text("£")
                                .foregroundStyle(.secondary)
                            TextField("New balance", text: $setBalanceText)
                                .keyboardType(.decimalPad)
                        }
                        Button("Save Balance") {
                            let cleaned = setBalanceText.filter { $0.isNumber || $0 == "." }
                            let pence = Int((Double(cleaned) ?? 0) * 100)
                            store.updateBalance(id: account.id, newBalancePence: pence)
                            setBalanceText = ""
                        }
                        .disabled(setBalanceText.isEmpty)
                    }

                    // Edit & Delete
                    Section {
                        Button("Edit Account") {
                            showEditSheet = true
                        }
                        Button("Delete Account", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditAccountSheet(store: store, account: displayAccount)
            }
            .alert("Delete \(displayAccount.name)?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    store.deleteAccount(id: account.id)
                    dismiss()
                }
            } message: {
                Text("This will permanently remove the account and its balance.")
            }
        }
    }
}

// MARK: - Edit Account Sheet

private struct EditAccountSheet: View {
    let store: SavingsStore
    let account: SavingsAccount
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var accountType: AccountType
    @State private var amounts: [Int]
    @State private var newAmountText = ""

    init(store: SavingsStore, account: SavingsAccount) {
        self.store = store
        self.account = account
        _name = State(initialValue: account.name)
        _accountType = State(initialValue: account.accountType)
        _amounts = State(initialValue: account.quickAddAmounts)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Account Name", text: $name)
                }

                Section("Account Type") {
                    Picker("Type", selection: $accountType) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    if let note = accountType.cashNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ForEach(amounts, id: \.self) { amount in
                        Text(savingsPoundsString(amount))
                    }
                    .onDelete { indexSet in
                        amounts.remove(atOffsets: indexSet)
                    }

                    HStack {
                        Text("£")
                            .foregroundStyle(.secondary)
                        TextField("New amount", text: $newAmountText)
                            .keyboardType(.decimalPad)
                        Button("Add") {
                            let cleaned = newAmountText.filter { $0.isNumber || $0 == "." }
                            let pence = Int((Double(cleaned) ?? 0) * 100)
                            if pence > 0 { amounts.append(pence) }
                            newAmountText = ""
                        }
                        .disabled(newAmountText.isEmpty)
                    }
                } header: {
                    Text("Quick Add Amounts")
                } footer: {
                    Text("These appear as one-tap buttons when updating your balance.")
                }
            }
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            store.renameAccount(id: account.id, name: trimmed)
                        }
                        store.setAccountType(id: account.id, accountType: accountType)
                        store.setQuickAddAmounts(id: account.id, amounts: amounts)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Quick Add Button Style

private struct QuickAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Helpers

func savingsPoundsString(_ pence: Int) -> String {
    let pounds = Double(pence) / 100.0
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencySymbol = "£"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 2
    return formatter.string(from: NSNumber(value: pounds)) ?? "£\(pounds)"
}

func savingsRelativeDate(_ date: Date) -> String {
    let seconds = Date().timeIntervalSince(date)
    if seconds < 60 { return "Just updated" }
    if seconds < 3600 { return "Updated \(Int(seconds / 60))m ago" }
    if seconds < 86400 { return "Updated \(Int(seconds / 3600))h ago" }
    let days = Int(seconds / 86400)
    if days == 1 { return "Updated yesterday" }
    if days < 30 { return "Updated \(days) days ago" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return "Updated \(formatter.string(from: date))"
}

// MARK: - Preview

#Preview {
    SavingsView(store: SavingsStore())
}

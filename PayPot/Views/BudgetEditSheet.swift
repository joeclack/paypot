import SwiftUI

struct BudgetEditSheet: View {
    let viewModel: DashboardViewModel
    let prefsStore: PotPreferencesStore

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

    var body: some View {
        Form {
            Section("Monthly Salary") {
                TextField("e.g. 2500", text: $salaryText)
                    .keyboardType(.decimalPad)
                    .focused($salaryFocused)
                    .onChange(of: salaryText) { _, new in
                        if let pounds = Double(new) {
                            prefsStore.setSalary(Int((pounds * 100).rounded()))
                        } else if new.isEmpty {
                            prefsStore.setSalary(0)
                        }
                    }
                Toggle("Use balance for spending", isOn: Binding(
                    get: { prefsStore.useBalanceForSpending },
                    set: { prefsStore.setUseBalanceForSpending($0) }
                ))
            }

            Section {
                if budgetedPots.isEmpty {
                    Text("Add pots below to start budgeting.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(budgetedPots) { pot in
                        PotBudgetRow(
                            pot: pot,
                            prefsStore: prefsStore,
                            isCustomPot: prefsStore.customPots.contains { $0.id == pot.id }
                        )
                    }
                    .onDelete { indexSet in
                        indexSet.forEach {
                            let pot = budgetedPots[$0]
                            prefsStore.setAllocation(potId: pot.id, amountPence: 0)
                            prefsStore.removeFavourite(id: pot.id)
                        }
                    }
                    .onMove { prefsStore.moveFavourite(from: $0, to: $1) }
                }
            } header: {
                Text("Budgeted Pots")
            } footer: {
                if !budgetedPots.isEmpty {
                    Text("Swipe to remove. Drag to reorder. Enter a monthly budget per pot.")
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

        }
        .navigationTitle("Edit Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

// MARK: - Pot Budget Row

private struct PotBudgetRow: View {
    let pot: Pot
    let prefsStore: PotPreferencesStore
    let isCustomPot: Bool

    @State private var text: String

    init(pot: Pot, prefsStore: PotPreferencesStore, isCustomPot: Bool) {
        self.pot = pot
        self.prefsStore = prefsStore
        self.isCustomPot = isCustomPot
        let pence = prefsStore.potAllocations[pot.id] ?? 0
        _text = State(initialValue: pence == 0 ? "" : String(format: "%.2f", Double(pence) / 100.0))
    }

    var body: some View {
        HStack {
            Text(pot.name)
            Spacer()
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .foregroundStyle(.tint)
                .fontWeight(.semibold)
                .onChange(of: text) { _, new in
                    if let pounds = Double(new) {
                        prefsStore.setAllocation(potId: pot.id, amountPence: Int((pounds * 100).rounded()))
                    } else if new.isEmpty {
                        prefsStore.setAllocation(potId: pot.id, amountPence: 0)
                    }
                }
            if isCustomPot {
                Button(role: .destructive) {
                    prefsStore.removeCustomPot(id: pot.id)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
    }
}

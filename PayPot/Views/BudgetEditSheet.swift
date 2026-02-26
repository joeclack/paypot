import SwiftUI

struct BudgetEditSheet: View {
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

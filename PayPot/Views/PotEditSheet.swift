import SwiftUI
import LocalAuthentication

struct PotEditSheet: View {
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

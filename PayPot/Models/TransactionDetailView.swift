import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Name", value: transaction.displayName)
                    LabeledContent("Description", value: transaction.description)
                    LabeledContent("Amount", value: transaction.formattedAmount())
                    LabeledContent("Type", value: transaction.isDebit ? "Debit" : "Credit")
                }

                Section("When") {
                    LabeledContent("Created", value: transaction.createdDateTimeString)
                }

                Section("Parties") {
                    if let merchant = transaction.merchant?.name, !merchant.isEmpty {
                        LabeledContent("Merchant", value: merchant)
                    }
                    if let cp = transaction.counterparty?.name, !cp.isEmpty {
                        LabeledContent("Counterparty", value: cp)
                    }
                }

                Section("Details") {
                    LabeledContent("Category", value: transaction.category)
                    LabeledContent("Notes", value: transaction.notes.isEmpty ? "—" : transaction.notes)
                    LabeledContent("Currency", value: transaction.currency)
                    LabeledContent("Raw Pence", value: String(transaction.amount))
                    LabeledContent("Amount (GBP)", value: transaction.amountPoundsString)
                }

                if !transaction.metadata.isEmpty {
                    Section("Metadata") {
                        ForEach(transaction.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(key, value: value)
                        }
                    }
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    TransactionDetailView(transaction: .init(
        id: "tx_123",
        created: .now,
        description: "Card payment to COFFEE SHOP",
        amount: -345,
        currency: "GBP",
        notes: "Oat latte",
        category: "eating_out",
        metadata: ["mcc": "5814"],
        merchant: .init(name: "Coffee Shop"),
        counterparty: nil
    ))
}

// Usage:
// In your list view, track a selected Transaction and present this view with:
// .sheet(item: $selectedTransaction) { tx in
//     TransactionDetailView(transaction: tx)
//         .presentationDetents([.medium, .large])
// }

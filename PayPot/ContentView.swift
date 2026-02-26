//
//  ContentView.swift
//  PayPot
//
//  Created by Joe Clack on 19/02/2026.
//

import SwiftUI

struct ContentView: View {
    let authManager: AuthManager
    @Bindable var viewModel: DashboardViewModel
    var onGoToSettings: (() -> Void)? = nil
    @State var searchText = ""
    @State private var selectedTransaction: Transaction?
    @State private var hideTransfers = false
    @State private var selectedCategory: String? = nil
    @State private var showCategoryPicker = false

    private var uniqueCategories: [String] {
        let categories = Set(viewModel.transactions.map { $0.category.lowercased() })
        return categories.sorted()
    }
    
    private var filteredTransactions: [Transaction] {
        // Sort newest first
        let sorted = viewModel.transactions.sorted { $0.created > $1.created }

        // Apply category filters first
        let categoryFiltered = sorted.filter { txn in
            let category = txn.category.lowercased()

            // Hide transfers toggle
            if hideTransfers && category == "transfers" {
                return false
            }

            // Specific category filter
            if let selected = selectedCategory {
                return category == selected.lowercased()
            }

            return true
        }

        // Apply search filtering
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categoryFiltered }

        let lcQuery = query.lowercased()

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return categoryFiltered.filter { txn in
            if txn.description.lowercased().contains(lcQuery) { return true }

            let absPoundsString = String(format: "%.2f", Double(abs(txn.amount)) / 100.0)
            if absPoundsString.contains(lcQuery) { return true }

            let dateString = formatter.string(from: txn.created).lowercased()
            if dateString.contains(lcQuery) { return true }

            return false
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if authManager.isAuthenticated {
                    Group {
                        if viewModel.balance == nil && viewModel.errorMessage != nil && !viewModel.isLoading {
                            networkErrorView
                        } else {
                            ScrollView {
                                VStack(spacing: 20) {
                                    if let message = viewModel.errorMessage {
                                        errorBanner(message: message)
                                    }
//                                    balanceCard
                                    transactionsSection
                                }
                                .padding()
                            }
                            .task { await viewModel.load() }
                            .refreshable { await viewModel.refresh() }
                            .overlay {
                                if viewModel.isLoading && viewModel.balance == nil {
                                    LoadingOverlay()
                                }
                            }
                        }
                    }
                    .alert("Session Expired", isPresented: $viewModel.isSessionExpired) {
                        Button("Reconnect") { authManager.signOut() }
                    } message: {
                        Text("Your Monzo session has expired. Reconnect in Settings.")
                    }
                } else {
                    notConnectedView
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Hide Transfers Toggle
                        Toggle("Hide Transfers", isOn: $hideTransfers)

                        Divider()

                        // Category Picker
                        Picker("Category", selection: $selectedCategory) {
                            Text("All Categories").tag(String?.none)

                            ForEach(uniqueCategories, id: \.self) { category in
                                Text(category.capitalized)
                                    .tag(Optional(category))
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }   
            .sheet(item: $selectedTransaction) { tx in
                TransactionDetailView(transaction: tx)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Not Connected

    private var notConnectedView: some View {
        ContentUnavailableView {
            Label("Monzo Not Connected", systemImage: "link.badge.plus")
        } description: {
            Text("Link your Monzo account to view your balance and transactions.")
        } actions: {
            Button {
                onGoToSettings?()
            } label: {
                Text("Go to Settings")
            }
            .buttonStyle(.primary)
        }
    }

    // MARK: - Network Error (full-screen, no cached data)

    private var networkErrorView: some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        } actions: {
            Button("Try Again") {
                viewModel.errorMessage = nil
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.primary)
        }
    }

    // MARK: - Error Banner (inline, stale data still visible)

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        VStack(spacing: 8) {
            Text("Current Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let balance = viewModel.balance {
                Text(pence: balance.balance)
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                HStack(spacing: 4) {
                    Text("Spent today:")
                        .foregroundStyle(.secondary)
                    Text(pence: abs(balance.spendToday))
                        .foregroundStyle(balance.spendToday != 0 ? .red : .secondary)
                }
                .font(.subheadline)

                if let lastUpdated = viewModel.lastUpdated {
                    TimelineView(.everyMinute) { context in
                        Text(relativeTime(from: lastUpdated, to: context.date))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            } else {
                Text("--")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .cardGlow(cornerRadius: 20)
    }

    // MARK: - Transactions Section

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transactions")
                .font(.title3.bold())
                .padding(.horizontal, 4)

            if filteredTransactions.isEmpty && !viewModel.isLoading {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No recent transactions found.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    VStack(spacing: 8) {
                        Text("No results for \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Clear Search") { searchText = "" }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredTransactions) { transaction in
                        Button {
                            selectedTransaction = transaction
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    let transaction: Transaction

    private var amountColor: Color {
        transaction.amount < 0 ? .red : .green
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: transaction.created)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(pence: abs(transaction.amount))
                .font(.body.weight(.semibold))
                .foregroundColor(amountColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Relative Time

private func relativeTime(from date: Date, to now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    if seconds < 60   { return "Updated just now" }
    let mins  = seconds / 60
    if mins   < 60    { return "Updated \(mins) min\(mins == 1 ? "" : "s") ago" }
    let hours = mins  / 60
    if hours  < 24    { return "Updated \(hours) hour\(hours == 1 ? "" : "s") ago" }
    let days  = hours / 24
    return "Updated \(days) day\(days == 1 ? "" : "s") ago"
}

// MARK: - Pence Formatting

extension Text {
    init(pence: Int) {
        let pounds = Double(pence) / 100.0
        let formatted = pounds.formatted(.currency(code: "GBP"))
        self.init(formatted)
    }
}

#Preview {
    ContentView(authManager: AuthManager(), viewModel: DashboardViewModel(authManager: AuthManager()))
}

import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    let authManager: AuthManager
    let prefsStore: PotPreferencesStore
    let viewModel: DashboardViewModel

    @AppStorage("app.colorScheme") private var appColorScheme: AppColorScheme = .system
    @AppStorage("app.biometricLockEnabled") private var biometricLockEnabled = false
    @AppStorage("app.lockDelay") private var lockDelay: LockDelay = .immediately

    @State private var showDisconnectConfirmation = false
    @State private var showConnectSheet = false
    @State private var showDeleteConfirmation = false
    #if DEBUG
    @State private var showLoginPreview = false
    @AppStorage("app.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("app.paydayConfettiDate") private var paydayConfettiDate = ""
    #endif

    private var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return context.biometryType
    }

    private var biometricLabel: String {
        switch biometricType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Device Passcode"
        }
    }

    private var biometricIcon: String {
        switch biometricType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.fill"
        }
    }

    private var paydayScheduleLabel: String {
        switch prefsStore.paydaySchedule {
        case .fixedDay(let day): return "\(day)\(ordinal(day)) of month"
        case .lastWorkingDay:    return "Last working day"
        case nil:                return "Not set"
        }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 11, 12, 13: return "th"
        default:
            switch n % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }

    var body: some View {
        NavigationStack {
        List {
                Section {
                    Toggle(isOn: $biometricLockEnabled) {
                        Label(biometricLabel, systemImage: biometricIcon)
                    }
                    if biometricLockEnabled {
                        Picker("Require After", selection: $lockDelay) {
                            ForEach(LockDelay.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    if biometricLockEnabled {
                        Text("\(biometricLabel) is used to unlock the app and to authenticate pot withdrawals.")
                    }
                }

                Section("Budget") {
                    NavigationLink(destination: PaydayEditSheet(prefsStore: prefsStore)) {
                        LabeledContent("Pay Schedule") {
                            Text(paydayScheduleLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appColorScheme) {
                        ForEach([AppColorScheme.system, .light, .dark], id: \.self) { scheme in
                            Text(scheme.label).tag(scheme)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Monzo Account") {
                    if authManager.isAuthenticated {
                        if let connectedAt = authManager.connectedAt {
                            HStack {
                                Text("Connected")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(connectedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        Button(role: .destructive) {
                            showDisconnectConfirmation = true
                        } label: {
                            Label {
                                Text("Disconnect Monzo")
                            } icon: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                            }
                        }
                    } else {
                        Button {
                            showConnectSheet = true
                        } label: {
                            Label("Connect with Monzo", systemImage: "link.badge.plus")
                        }
                    }
                }

                Section("Data") {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label {
                            Text("Delete Budget Data")
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }

                #if DEBUG
                Section("Dev") {
                    Button("Preview Login Screen") {
                        showLoginPreview = true
                    }
                    Button("Reset Onboarding") {
                        hasSeenOnboarding = false
                    }
                    Button("Reset Payday Confetti") {
                        paydayConfettiDate = ""
                    }
                    if let expiresAt = authManager.tokenExpiresAt {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Access token expires")
                                    .foregroundStyle(.secondary)
                                Text("Auto-refreshed on launch")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if expiresAt < Date() {
                                Text("Expired")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            } else {
                                Text(expiresAt, style: .relative)
                                    .font(.subheadline)
                                    .foregroundStyle(expiresAt.timeIntervalSinceNow < 3600 ? .orange : .secondary)
                            }
                        }
                    }
                    HStack {
                        switch viewModel.connectionStatus {
                        case .unchecked:
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("Token status unknown")
                                .foregroundStyle(.secondary)
                        case .checking:
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking token…")
                                .foregroundStyle(.secondary)
                        case .active:
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("Token active")
                        case .expired:
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Token expired")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button("Check") {
                            Task { await viewModel.checkConnection() }
                        }
                        .font(.subheadline)
                    }
                }
                #endif
            }
            #if DEBUG
            .sheet(isPresented: $showLoginPreview) {
                LoginView(authManager: authManager, previewOnly: true)
            }
            #endif
            .navigationTitle("Settings")
            .task {
                if authManager.isAuthenticated {
                    await viewModel.checkConnection()
                }
            }
            .alert("Disconnect Monzo?", isPresented: $showDisconnectConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("Your budget, salary settings, and favourite pots will be kept. Only your Monzo connection will be removed.")
            }
            .alert("Delete Budget Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    prefsStore.resetBudgetData()
                    viewModel.reset()
                }
            } message: {
                Text("Your salary, pot allocations, custom pots, and favourite selections will be removed. Your Monzo connection will not be affected.")
            }
            .sheet(isPresented: $showConnectSheet) {
                LoginView(authManager: authManager)
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated { showConnectSheet = false }
            }
        }
    }
}

#Preview {
    let auth = AuthManager()
    SettingsView(authManager: auth, prefsStore: PotPreferencesStore(), viewModel: DashboardViewModel(authManager: auth))
}

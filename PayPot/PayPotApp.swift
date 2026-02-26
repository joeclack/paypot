import SwiftUI
import LocalAuthentication

enum Tabs: Int {
    case monzo = 0, budget, settings, savings
}

enum LockDelay: String, CaseIterable {
    case immediately  = "immediately"
    case oneMinute    = "oneMinute"
    case fiveMinutes  = "fiveMinutes"
    case onRestart    = "onRestart"

    var label: String {
        switch self {
        case .immediately: return "Immediately"
        case .oneMinute:   return "After 1 Minute"
        case .fiveMinutes: return "After 5 Minutes"
        case .onRestart:   return "On App Restart"
        }
    }

    var threshold: TimeInterval? {
        switch self {
        case .immediately: return 0
        case .oneMinute:   return 60
        case .fiveMinutes: return 300
        case .onRestart:   return nil
        }
    }
}

enum AppColorScheme: String {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System Default"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

@main
struct PayPotApp: App {
    @State private var authManager = AuthManager()
    @State private var prefsStore = PotPreferencesStore()
    @State private var savingsStore = SavingsStore()
    @State private var appLockManager = AppLockManager()

    var body: some Scene {
        WindowGroup {
            RootView(authManager: authManager, prefsStore: prefsStore, savingsStore: savingsStore, appLockManager: appLockManager)
        }
    }
}

struct RootView: View {
    let authManager: AuthManager
    let prefsStore: PotPreferencesStore
    let savingsStore: SavingsStore
    let appLockManager: AppLockManager
    @State private var activeTab: Tabs = .budget
    @State private var dashboardViewModel: DashboardViewModel
    @State private var splashDone = false
    @AppStorage("app.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("app.colorScheme") private var appColorScheme: AppColorScheme = .system
    @AppStorage("app.biometricLockEnabled") private var biometricLockEnabled = false
    @AppStorage("app.lockDelay") private var lockDelay: LockDelay = .immediately
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false
    @State private var lockScreenVisible = true
    @State private var backgroundedAt: Date = .distantPast

    init(authManager: AuthManager, prefsStore: PotPreferencesStore, savingsStore: SavingsStore, appLockManager: AppLockManager) {
        self.authManager = authManager
        self.prefsStore = prefsStore
        self.savingsStore = savingsStore
        self.appLockManager = appLockManager
        self._dashboardViewModel = State(initialValue: DashboardViewModel(authManager: authManager))
    }

    var body: some View {
        ZStack {
            TabView(selection: $activeTab) {
                Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
                    BudgetView(viewModel: dashboardViewModel, prefsStore: prefsStore)
                }
                Tab("Transactions", systemImage: "list.bullet.rectangle", value: .monzo) {
                    ContentView(authManager: authManager, viewModel: dashboardViewModel) {
                        activeTab = .settings
                    }
                }
                Tab("Savings", systemImage: "chart.line.uptrend.xyaxis.circle", value: .savings) {
                    SavingsView(store: savingsStore)
                }
                Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                    SettingsView(authManager: authManager, prefsStore: prefsStore, viewModel: dashboardViewModel)
                }
            }
            .preferredColorScheme(appColorScheme.colorScheme)
            

            if !splashDone {
                AppSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            if biometricLockEnabled && lockScreenVisible {
                AppLockedView(appLockManager: appLockManager)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .task {
            async let load: Void = dashboardViewModel.load()
            if biometricLockEnabled {
                await appLockManager.authenticate()
            }
            await load
            withAnimation(.easeOut(duration: 0.4)) {
                splashDone = true
            }
        }
        .onChange(of: appLockManager.isUnlocked) { _, unlocked in
            if unlocked {
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    withAnimation(.easeIn(duration: 0.3)) {
                        lockScreenVisible = false
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                guard biometricLockEnabled else { break }
                backgroundedAt = Date()
                wasInBackground = true
                if lockDelay == .immediately {
                    appLockManager.isUnlocked = false
                    lockScreenVisible = true
                }
            case .active:
                guard wasInBackground && biometricLockEnabled else {
                    wasInBackground = false
                    break
                }
                wasInBackground = false
                if lockDelay == .onRestart { break }
                let elapsed = Date().timeIntervalSince(backgroundedAt)
                if elapsed >= (lockDelay.threshold ?? 0) {
                    appLockManager.isUnlocked = false
                    lockScreenVisible = true
                }
                if lockScreenVisible && !appLockManager.isUnlocked {
                    Task { await appLockManager.authenticate() }
                }
            default:
                break
            }
        }
        .onChange(of: biometricLockEnabled) { _, enabled in
            if enabled {
                // Already in the app — mark unlocked and don't show the lock screen.
                appLockManager.isUnlocked = true
                lockScreenVisible = false
            }
        }
        .onOpenURL { url in
            authManager.handleIncomingURL(url)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { _ in }
        )) {
            OnboardingView {
                hasSeenOnboarding = true
            }
        }
    }
}

// MARK: - App Splash

private struct AppSplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("PayPot")
                    .font(.largeTitle.weight(.bold))
                ProgressView()
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - App Locked

private struct AppLockedView: View {
    let appLockManager: AppLockManager

    private var biometricLabel: String {
        switch appLockManager.biometricType {
        case .faceID:  return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default:       return "Unlock with Passcode"
        }
    }

    private var biometricIcon: String {
        switch appLockManager.biometricType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.fill"
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: appLockManager.isUnlocked ? "lock.open.fill" : "faceid")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .contentTransition(.symbolEffect(.replace.offUp))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appLockManager.isUnlocked)
                    Text("PayPot")
                        .font(.largeTitle.weight(.bold))
                }
                Spacer()
//                Button {
//                    Task { await appLockManager.authenticate() }
//                } label: {
//                    Label(biometricLabel, systemImage: biometricIcon)
//                }
//                .buttonStyle(.primary)
//                .padding(.bottom, 40)
//                .opacity(appLockManager.isUnlocked ? 0 : 1)
//                .animation(.easeOut(duration: 0.2), value: appLockManager.isUnlocked)
            }
        }
    }
}

#Preview {
    RootView(authManager: AuthManager(), prefsStore: PotPreferencesStore(), savingsStore: SavingsStore(), appLockManager: AppLockManager())
}

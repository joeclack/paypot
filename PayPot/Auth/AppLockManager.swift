import LocalAuthentication

@MainActor
@Observable
final class AppLockManager {
    var isUnlocked = false
    private(set) var biometricType: LABiometryType = .none
    private var isAuthenticating = false

    init() {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        biometricType = context.biometryType
    }

    func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on device — don't block access
            isUnlocked = true
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock PayPot"
            )
            isUnlocked = success
        } catch {
            // User cancelled or authentication failed — stay locked
            isUnlocked = false
        }
    }
}

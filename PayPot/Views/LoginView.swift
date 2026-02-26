import SwiftUI

struct LoginView: View {
    let authManager: AuthManager
    var previewOnly: Bool = false

    @State private var previewIsWaiting = false
    @Environment(\.scenePhase) private var scenePhase

    private var isWaiting: Bool {
        previewOnly ? previewIsWaiting : (authManager.isSigningIn || authManager.isAwaitingScaApproval)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "banknote")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("PayPot")
                    .font(.largeTitle.bold())

                Text("Connect your Monzo account to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if isWaiting {
                stepsView
            }

            Spacer()

            VStack(spacing: 12) {
                if !previewOnly, let error = authManager.signInError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    if previewOnly {
                        previewIsWaiting.toggle()
                    } else {
                        authManager.signIn()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isWaiting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isWaiting ? "Waiting for approval…" : "Connect with Monzo")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!previewOnly && isWaiting)

                if isWaiting {
                    Button(previewOnly ? "Reset Preview" : "Cancel") {
                        if previewOnly {
                            previewIsWaiting = false
                        } else {
                            authManager.cancelSignIn()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer().frame(height: 32)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !previewOnly, newPhase == .active else { return }
            if authManager.isAwaitingScaApproval {
                authManager.retryScaApprovalCheck()
            } else {
                authManager.retryPendingExchange()
            }
        }
    }

    @ViewBuilder
    private var stepsView: some View {
        let stepsComplete = previewOnly ? false : (authManager.hasReceivedCode || authManager.isAwaitingScaApproval)
        VStack(alignment: .leading, spacing: 20) {
            StepRow(
                icon: "globe",
                title: "Enter your email",
                description: "Your browser will open to Monzo — enter your email to receive a magic link",
                isComplete: stepsComplete,
                isActive: !stepsComplete
            )
            StepRow(
                icon: "envelope.fill",
                title: "Check your email",
                description: "Tap the magic link Monzo sent you",
                isComplete: stepsComplete,
                isActive: !stepsComplete
            )
            StepRow(
                icon: "arrow.up.forward.app.fill",
                title: "Open in PayPot",
                description: "Tap \"Open\" when Safari asks",
                isComplete: stepsComplete,
                isActive: !stepsComplete
            )
            StepRow(
                icon: "checkmark.shield.fill",
                title: "Approve in Monzo",
                description: (!previewOnly && authManager.isAwaitingScaApproval)
                    ? "Tap the notification in your Monzo app to approve"
                    : "Confirm the access request in your Monzo app",
                isComplete: false,
                isActive: stepsComplete
            )
        }
        .padding(.horizontal)
    }
}

private struct StepRow: View {
    let icon: String
    let title: String
    let description: String
    let isComplete: Bool
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 40, height: 40)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(isActive ? .green : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(isActive || isComplete ? .semibold : .regular))
                    .foregroundStyle(isActive || isComplete ? .primary : .secondary)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 9)
        }
    }

    private var circleColor: Color {
        if isComplete { return .green }
        if isActive { return .green.opacity(0.15) }
        return Color(.systemFill)
    }
}

#Preview {
    LoginView(authManager: AuthManager())
}

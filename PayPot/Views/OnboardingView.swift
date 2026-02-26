import SwiftUI

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

private let pages: [OnboardingPage] = [
    OnboardingPage(
        icon: "banknote",
        iconColor: .green,
        title: "Welcome to PayPot",
        description: "Your simple, private finance companion. Plan your salary, track pot allocations, and sort your money on PayPot."
    ),
    OnboardingPage(
        icon: "chart.pie.fill",
        iconColor: .green,
        title: "Plan Your Budget",
        description: "Enter your monthly salary and decide exactly how much goes to each savings pot. Set it once and you're done."
    ),
    OnboardingPage(
        icon: "tray.2.fill",
        iconColor: .green,
        title: "Works Without Monzo",
        description: "Create your own pots and manage allocations entirely on device. No bank connection required to get started."
    ),
    OnboardingPage(
        icon: "sterlingsign.circle.fill",
        iconColor: .green,
        title: "Connect Monzo (Optional)",
        description: "Link your Monzo account to see your real balance and pots. You can connect at any time from Settings."
    ),
    OnboardingPage(
        icon: "lock.shield.fill",
        iconColor: .green,
        title: "Your Privacy Matters",
        description: "Everything is stored locally on this device. Nothing is shared or sent to any server — your data is yours alone."
    ),
]

struct OnboardingView: View {
    var onDismiss: () -> Void

    @State private var currentPage = 0

    private var isLastPage: Bool { currentPage == pages.count - 1 }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .toolbar {
                    if !isLastPage {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Skip") { onDismiss() }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: page.icon)
                    .font(.system(size: 72))
                    .foregroundStyle(page.iconColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text(page.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()

            if isLastPage {
                Button {
                    onDismiss()
                } label: {
                    Text("Get Started")
                }
                .buttonStyle(.primary)
                .padding(.bottom, 48)
            }
        }
    }
}

#Preview {
    OnboardingView(onDismiss: {})
}

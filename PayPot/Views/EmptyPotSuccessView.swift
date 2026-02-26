import SwiftUI

struct EmptyPotSuccessView: View {
    let amountPence: Int
    let onDone: () -> Void

    @State private var showCheck = false
    @State private var showText = false
    @State private var showConfetti = false

    private var formattedAmount: String {
        (Double(amountPence) / 100.0).formatted(.currency(code: "GBP"))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.green)
                        .scaleEffect(showCheck ? 1 : 0.1)
                        .opacity(showCheck ? 1 : 0)
                }

                VStack(spacing: 8) {
                    Text("Done!")
                        .font(.title.weight(.bold))
                    Text("\(formattedAmount) moved to your account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 12)

                Spacer()

                Button("Close") { onDone() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
                    .opacity(showText ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                showCheck = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                showText = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showConfetti = true
            }
        }
    }
}

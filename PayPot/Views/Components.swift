import SwiftUI

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
            ProgressView()
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(.green.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { old, new in
                old && !new // fire on finger lift (confirmed tap)
            }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

// MARK: - Card Glow Modifier (dark mode only)

struct CardGlow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if colorScheme == .dark {
                RadialGradient(
                    colors: [.white.opacity(0.07), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 160
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func cardGlow(cornerRadius: CGFloat) -> some View {
        modifier(CardGlow(cornerRadius: cornerRadius))
    }
}

// MARK: - Pot Accent Color

extension Color {
    /// Deterministic accent color for a pot, derived from its ID.
    static func accent(for potId: String) -> Color {
        let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo, .mint, .cyan]
        let hash = potId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

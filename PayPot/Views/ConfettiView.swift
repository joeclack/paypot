import SwiftUI

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
    let xDrift: CGFloat
    let speed: Double
    let delay: Double
}

struct ConfettiView: View {
    private let pieces: [ConfettiPiece] = (0..<50).map { _ in
        ConfettiPiece(
            x: CGFloat.random(in: 0...1),
            color: [Color.green, .yellow, .orange, .pink, .blue, .purple, .mint].randomElement()!,
            size: CGFloat.random(in: 6...12),
            rotation: Double.random(in: 0...360),
            xDrift: CGFloat.random(in: -60...60),
            speed: Double.random(in: 0.8...1.4),
            delay: Double.random(in: 0...0.4)
        )
    }

    @State private var startDate: Date = .now

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                guard elapsed < 1.8 else { return }
                for piece in pieces {
                    let pieceElapsed = max(0, elapsed - piece.delay)
                    let progress = min(pieceElapsed / piece.speed, 1.0)
                    guard progress > 0 else { continue }
                    let x = piece.x * size.width + piece.xDrift * progress
                    let y = -20 + (size.height + 40) * progress
                    let angle = CGFloat((piece.rotation + progress * 540) * .pi / 180)
                    let transform = CGAffineTransform(translationX: x, y: y).rotated(by: angle)
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4,
                                     width: piece.size, height: piece.size / 2)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 2).applying(transform),
                        with: .color(piece.color)
                    )
                }
            }
        }
    }
}

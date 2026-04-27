import SwiftUI

/// The pulsing rainbow border / glow that Apple uses in iOS 18's Siri
/// and Writing Tools to indicate "the AI is thinking." Pure SwiftUI,
/// no external assets. Applied as a `.overlay` or `.background`.
///
/// Usage:
///   SomeView()
///       .overlay(AIGlowBorder(active: isGenerating))
///
/// When `active == false` the view renders nothing (no perf cost).
struct AIGlowBorder: View {
    let active: Bool
    var cornerRadius: CGFloat = 28
    var lineWidth: CGFloat = 2.5

    @State private var rotation: Double = 0

    var body: some View {
        if active {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: Self.colors,
                        center: .center,
                        startAngle: .degrees(rotation),
                        endAngle: .degrees(rotation + 360)
                    ),
                    lineWidth: lineWidth
                )
                .blur(radius: 2)
                .shadow(color: .purple.opacity(0.35), radius: 12)
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    /// Apple Intelligence's signature palette — pink, orange, yellow,
    /// mint, cyan, blue, purple in a continuous loop.
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.35, blue: 0.58),  // pink
        Color(red: 1.00, green: 0.58, blue: 0.30),  // orange
        Color(red: 0.92, green: 0.92, blue: 0.36),  // yellow
        Color(red: 0.35, green: 0.92, blue: 0.71),  // mint
        Color(red: 0.29, green: 0.76, blue: 1.00),  // cyan
        Color(red: 0.42, green: 0.48, blue: 1.00),  // indigo
        Color(red: 0.74, green: 0.40, blue: 0.99),  // purple
        Color(red: 1.00, green: 0.35, blue: 0.58),  // loop
    ]
}

/// Full-screen ambient glow — a big soft gradient blob that pulses in
/// the background when Gemma is thinking. Lives behind the main
/// content, not over it.
struct AIAmbientGlow: View {
    let active: Bool

    @State private var phase: CGFloat = 0

    var body: some View {
        if active {
            GeometryReader { geo in
                ZStack {
                    radialBlob(color: .pink.opacity(0.35), at: CGPoint(x: geo.size.width * 0.2, y: geo.size.height * 0.3), radius: 180, offset: 0)
                    radialBlob(color: .cyan.opacity(0.30), at: CGPoint(x: geo.size.width * 0.8, y: geo.size.height * 0.7), radius: 200, offset: 0.33)
                    radialBlob(color: .purple.opacity(0.35), at: CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5), radius: 240, offset: 0.66)
                }
                .blur(radius: 60)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func radialBlob(color: Color, at point: CGPoint, radius: CGFloat, offset: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: point.x + sin(phase * .pi * 2 + offset * .pi) * 40,
                      y: point.y + cos(phase * .pi * 2 + offset * .pi) * 40)
    }
}

/// Sparkles icon with the Apple Intelligence rainbow fill.
struct SparkleAccent: View {
    var size: CGFloat = 20
    @State private var rotate = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size))
            .foregroundStyle(
                AngularGradient(
                    colors: AIGlowBorder.colors,
                    center: .center
                )
            )
            .rotationEffect(.degrees(rotate ? 20 : -20))
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: rotate)
            .onAppear { rotate = true }
    }
}

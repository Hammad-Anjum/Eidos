import SwiftUI

/// 3-slide tour shown once after model download. Introduces the user
/// to features that aren't immediately obvious from the chat screen:
/// voice input, morning briefings, app actions with confirmation.
/// Dismissable via Skip; persisted in UserDefaults so it only fires once.
struct FeatureTourView: View {

    static let seenKey = "eidos.featureTour.seen"

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private static let slides: [TourSlide] = [
        TourSlide(
            icon: "mic.fill",
            title: "Talk, don't type",
            body: "Tap the mic in the chat bar — Eidos transcribes on-device. Audio never leaves your iPhone."
        ),
        TourSlide(
            icon: "sun.max.fill",
            title: "Your mornings, briefed",
            body: "The Home tab pulls calendar, reminders, and yesterday's health into a single briefing. Enable the daily notification in Settings."
        ),
        TourSlide(
            icon: "arrow.up.right.square.fill",
            title: "Reaches into other apps — safely",
            body: "Ask Eidos to WhatsApp, text, call, or navigate. You always see the draft and tap Send yourself. Eidos never sends anything on its own."
        ),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(Self.slides.indices, id: \.self) { i in
                    slideView(Self.slides[i]).tag(i)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            Button {
                if page < Self.slides.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < Self.slides.count - 1 ? "Next" : "Start using Eidos")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .overlay(alignment: .topTrailing) {
            Button("Skip", action: finish)
                .padding()
                .foregroundStyle(.secondary)
        }
    }

    private func slideView(_ slide: TourSlide) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: slide.icon)
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text(slide.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(slide.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }
}

private struct TourSlide {
    let icon: String
    let title: String
    let body: String
}

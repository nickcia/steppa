import SwiftUI

/// Text that types itself out at a steady pace, however unevenly it arrives.
///
/// The on-device model streams in bursts of a few words. Showing each burst as it lands looks jerky, so this
/// reveals the text a few characters at a time on a steady clock, speeding up when it falls behind, and fades
/// in the newest characters.
struct PacedText: View {
    let text: String
    var font: Font = .body
    var color: Color = Theme.ink
    /// Called as more text shows, e.g. to keep a chat scrolled to the bottom.
    var onStep: (() -> Void)?
    @State private var shown: Int

    init(_ text: String, paced: Bool = true, font: Font = .body, color: Color = Theme.ink, onStep: (() -> Void)? = nil) {
        self.text = text
        self.font = font
        self.color = color
        self.onStep = onStep
        _shown = State(initialValue: paced ? 0 : text.count)
    }

    var body: some View {
        let visible = String(text.prefix(shown))
        Text(LocalizedStringKey(visible))
            .font(font)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                while shown < text.count, !Task.isCancelled {
                    let behind = text.count - shown
                    // About 60 characters a second when keeping up; up to five times that when far behind.
                    shown = min(text.count, shown + max(1, behind / 12))
                    onStep?()
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
    }
}

/// What shows while the coach is working: a softly pulsing orb and a shimmer passing over what it's doing.
struct ThinkingIndicator: View {
    let status: String

    var body: some View {
        HStack(spacing: 10) {
            CoachOrb(size: 22, animating: true)
            ShimmerText(text: status)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: status)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status)
    }
}

/// The coach's mark: a purple gradient orb that breathes while the coach works.
struct CoachOrb: View {
    var size: CGFloat = 40
    var animating = false

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breath = animating ? (sin(t * 2.4) + 1) / 2 : 0
            ZStack {
                Circle()
                    .fill(StrengthStyle.gradient)
                    .blur(radius: size * 0.25)
                    .opacity(0.35 + 0.35 * breath)
                    .scaleEffect(1.1 + 0.2 * breath)
                Circle()
                    .fill(AngularGradient(colors: [Color(hex: 0xC6B9FF), StrengthStyle.color, Color(hex: 0x5B47C9),
                                                   Color(hex: 0x9F8CFF), Color(hex: 0xC6B9FF)],
                                          center: .center, angle: .degrees(animating ? t * 90 : 0)))
                    .scaleEffect(0.94 + 0.06 * breath)
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Secondary text with a brighter band sweeping across it.
struct ShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryInk.opacity(0.55))
                .overlay {
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.5),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: UnitPoint(x: phase * 2.6 - 1.3, y: 0.5),
                                           endPoint: UnitPoint(x: phase * 2.6 - 0.3, y: 0.5))
                        }
                }
        }
    }
}

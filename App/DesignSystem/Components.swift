import SwiftUI
import PlanEngine

/// Rounded container used for most content.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.secondaryInk)
            .background {
                if isEnabled {
                    Capsule().fill(Theme.accent)
                } else {
                    Capsule().fill(Theme.subtle)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Theme.ink)
            .background(Color.white, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small capsule action, e.g. "Move" or "Send to watch" under today's workout.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static var chip: ChipButtonStyle { ChipButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Coloured circle with the workout kind's symbol.
struct KindIcon: View {
    let kind: WorkoutKind?
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: kind?.symbol ?? "bed.double.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(kind.map { _ in Color.white } ?? Theme.secondaryInk)
            .frame(width: size, height: size)
            .background {
                if let kind {
                    Circle().fill(kind.gradient)
                } else {
                    Circle().fill(Theme.subtle)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A large number with a small label underneath.
struct Metric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small rounded label, e.g. a phase or "Step-back week".
struct Pill: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .fontDesign(.rounded)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Standard screen background.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Covers the status bar area so scrolled content doesn't run under the clock (screens without a nav bar).
    func statusBarBackdrop() -> some View {
        overlay(alignment: .top) {
            LinearGradient(colors: [Theme.background, Theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
                .offset(y: 12)
                .background(Theme.background.ignoresSafeArea(edges: .top))
                .frame(height: 0, alignment: .top)
                .allowsHitTesting(false)
        }
    }
}

/// Black capsule with white text, e.g. "8 km" beside a workout.
struct ValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
    }
}

/// Small coloured change badge, e.g. "+12%".
struct DeltaBadge: View {
    let text: String
    let isGood: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isGood ? Theme.green : Theme.red, in: Capsule())
    }
}

/// A thin track filled from red through amber to green, up to `value` (0–1).
struct HeatBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtle)
                // The gradient spans the whole track, so a short bar stays red and a full one ends green.
                Theme.heat
                    .frame(width: width)
                    .mask(alignment: .leading) { Capsule().frame(width: max(4, width * min(max(value, 0), 1))) }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Circular icon button, as in a screen header.
struct CircleIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 46, height: 46)
                .background(Theme.card, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

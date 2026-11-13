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

/// Small capsule action, e.g. "Move" or "Add" in a card.
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

/// The workout kind's symbol on a small dark-glass tile (see ActivityIcon).
struct KindIcon: View {
    let kind: WorkoutKind?
    var size: CGFloat = 44
    /// On a dark card (today's workout, the goal race): a light glass tile instead.
    var onDark = false

    var body: some View {
        ActivityIcon(symbol: kind?.symbol ?? "bed.double.fill", colors: kind?.gradientStops, size: size, onDark: onDark)
    }
}

/// An activity's mark: a crisp rounded-square tile in dark glass, like the rest of the app's accents, with the
/// symbol in the activity's colour. Without colours (a rest day) it's a quiet grey tile.
struct ActivityIcon: View {
    let symbol: String
    /// Highlight, main and deep colour stops; the symbol uses the first two.
    var colors: [Color]?
    var size: CGFloat = 44
    var onDark = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(colors.map { LinearGradient(colors: [$0[0], $0[1]], startPoint: .top, endPoint: .bottom) }
                             ?? LinearGradient(colors: [Theme.secondaryInk], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .background {
                if colors == nil {
                    shape.fill(onDark ? Color.white.opacity(0.1) : Theme.subtle)
                } else if onDark {
                    shape.fill(Color.white.opacity(0.1))
                } else {
                    shape.fill(LinearGradient(colors: [Color(hex: 0x2B2B31), Color(hex: 0x0B0B0D)],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay {
                if colors != nil {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(onDark ? 0.25 : 0.18), .white.opacity(0.02)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
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

    /// Blurs scrolled content as it reaches the status bar: clear further down, more blurred towards the clock, so
    /// nothing reads under it and there's no hard edge (screens without a nav bar). Apply to the scroll view.
    @ViewBuilder
    func statusBarBackdrop() -> some View {
        if #available(iOS 26.0, *) {
            // The system's own soft edge: a progressive blur, as in Apple's apps.
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            overlay(alignment: .top) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: proxy.safeAreaInsets.top + 20)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: 0.55),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        .ignoresSafeArea(edges: .top)
                }
                .allowsHitTesting(false)
            }
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

/// A thin track filled with the logo's sheen up to `value` (0–1).
struct HeatBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.subtle)
                // The gradient spans the whole track, so the colours shift along as the bar fills.
                Theme.sheen
                    .frame(width: width)
                    .mask(alignment: .leading) { Capsule().frame(width: max(4, width * min(max(value, 0), 1))) }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}


// MARK: - Glass (the logo's material), for the few floating, important pieces

/// Dark glass, used only where it means something: today's workout and the Coach button. A deep smoky
/// gradient with a soft reflection across the top and a bright edge where the light catches the top left, like
/// the logo. No colour fringe: the logo's sheen is kept for progress and the coach.
struct DarkGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Frosted, so a little of the page shows through, then smoky glass over it.
                    shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    shape.fill(LinearGradient(colors: [Color(hex: 0x303036), Color(hex: 0x151518), Color(hex: 0x09090B)],
                                              startPoint: .top, endPoint: .bottom).opacity(0.78))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0)],
                                              startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.06), .white.opacity(0.14)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

/// The floating tab bar: the system's Liquid Glass on iOS 26 and later, tinted dark, so content scrolling behind
/// it shows through refracted; frosted dark glass on earlier iOS.
struct BarGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.black.opacity(0.52)).interactive(), in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Color.black.opacity(0.55))
                    }
                    .environment(\.colorScheme, .dark)
                }
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05), .white.opacity(0.12)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    func darkGlass<S: InsettableShape>(_ shape: S) -> some View { modifier(DarkGlass(shape: shape)) }
    func barGlass<S: InsettableShape>(_ shape: S) -> some View { modifier(BarGlass(shape: shape)) }
}

// MARK: - "Now" highlights

/// A small capsule label in the logo's sheen, marking what's current: this week, the next race.
struct SheenPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.sheen, in: Capsule())
            .shadow(color: Theme.sheenColors[1].opacity(0.3), radius: 6, y: 2)
    }
}

extension View {
    /// Lifts the current item off the page: a solid white card with a soft shadow, where the others sit flatter.
    func currentHighlight(_ isCurrent: Bool, cornerRadius: CGFloat) -> some View {
        background {
            if isCurrent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            }
        }
    }
}

/// A big figure with its units set smaller, so "90.7 km" or "9 h 32 min" reads as one figure instead of a number,
/// a wide gap and a word as big as the number. Digits and their punctuation stay at `size`; units and the spaces
/// around them shrink to `unitScale` of it.
struct FigureText: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var unitScale: CGFloat = 0.55

    var body: Text {
        Self.parts(text).reduce(Text(verbatim: "")) { result, part in
            result + Text(verbatim: part.text)
                .font(.system(size: part.isNumber ? size : size * unitScale, weight: weight))
        }
    }

    /// Splits "9 h 32 min" into runs of number ("9", "32") and everything else (" h ", " min").
    static func parts(_ text: String) -> [(text: String, isNumber: Bool)] {
        var parts: [(text: String, isNumber: Bool)] = []
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            // Punctuation inside a figure ("90.7", "2:09:18", "0/3", "24%") stays full size; after a space it's a
            // unit ("/km") and shrinks. A sign right before a digit ("−31", "+6%") is part of the number.
            let isSign = "+−-".contains(character) && index + 1 < characters.count && characters[index + 1].isNumber
            let isNumber = character.isNumber || isSign
                || (".,:%−-/".contains(character) && parts.last?.isNumber == true)
            if let last = parts.last, last.isNumber == isNumber {
                parts[parts.count - 1].text.append(character)
            } else {
                parts.append((String(character), isNumber))
            }
        }
        return parts
    }
}

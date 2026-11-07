import SwiftUI
import UIKit
import PlanEngine

/// The app's visual language. Everything colour- and spacing-related lives here so the look
/// can be changed in one place.
enum Theme {
    // A light, calm look: soft grey page, near-white cards, near-black type and pills, and one signature
    // gradient (red → amber → green) for progress and effort. The app always uses light mode (see SteppaApp).
    /// Selected states and main actions are near-black pills.
    static let accent = Color(hex: 0x141414)
    /// Text and icons on an accent fill.
    static let onAccent = Color.white
    static let ink = Color(hex: 0x111111)
    static let secondaryInk = Color(hex: 0x8C8C8C)
    static let background = Color(hex: 0xECECEC)
    static let card = Color(hex: 0xF8F8F8)
    /// Tracks, empty bars and quiet fills.
    static let subtle = Color(hex: 0xE1E1E1)
    static let hairline = Color.black.opacity(0.04)
    static let warning = Color(hex: 0xE59A1F)

    static let red = Color(hex: redHex)
    static let amber = Color(hex: amberHex)
    static let green = Color(hex: greenHex)
    private static let redHex: UInt32 = 0xF26D6D
    private static let amberHex: UInt32 = 0xF5B13D
    private static let greenHex: UInt32 = 0x5CCB6A

    /// The signature gradient, low to high: red, amber, green.
    static let heat = LinearGradient(colors: [red, amber, green], startPoint: .leading, endPoint: .trailing)

    /// The heat colour for a value from 0 (red) to 1 (green).
    static func heat(_ value: Double) -> Color {
        let v = min(max(value, 0), 1)
        return v < 0.5 ? blend(redHex, amberHex, v * 2) : blend(amberHex, greenHex, (v - 0.5) * 2)
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return (x + (y - x) * t) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }

    enum Radius {
        static let card: CGFloat = 28
        static let control: CGFloat = 20
        static let chip: CGFloat = 12
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension Color {
    /// A colour that adapts to light and dark mode, from 0xRRGGBB values.
    ///
    /// `nonisolated` matters: SwiftUI resolves dynamic colours on its render thread, and with
    /// main-actor default isolation the provider closure would otherwise trap at runtime.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(UIColor { @Sendable traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Semantic colours and symbols for engine types

extension WorkoutKind {
    /// Highlight, main and deep stops; `color` is the main one.
    var gradientStops: [Color] {
        switch self {
        case .easy: [Color(hex: 0x9FE6A8), Color(hex: 0x5CCB6A), Color(hex: 0x3A9E4A)]
        case .long: [Color(hex: 0xA9C6FF), Color(hex: 0x5B8DEF), Color(hex: 0x3A62C4)]
        case .tempo: [Color(hex: 0xFFD58A), Color(hex: 0xF5B13D), Color(hex: 0xD9861A)]
        case .intervals: [Color(hex: 0xFFADAD), Color(hex: 0xF26D6D), Color(hex: 0xD04545)]
        case .marathonPaceLong: [Color(hex: 0xCDB8FF), Color(hex: 0x9A78F0), Color(hex: 0x6F4FD0)]
        case .race: [Color(hex: 0xFFB3CF), Color(hex: 0xEC5D93), Color(hex: 0xC23A6E)]
        case .hills: [Color(hex: 0xF4C7A1), Color(hex: 0xD98A55), Color(hex: 0xA85A2C)]
        }
    }

    var color: Color { gradientStops[1] }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var symbol: String {
        switch self {
        case .easy: "figure.run"
        case .long: "road.lanes"
        case .tempo: "gauge.with.dots.needle.67percent"
        case .intervals: "repeat"
        case .marathonPaceLong: "speedometer"
        case .race: "flag.checkered"
        case .hills: "mountain.2"
        }
    }

    /// For sentences: "Ready for your threshold run?"
    var casualName: String {
        switch self {
        case .easy: String(localized: "easy run")
        case .long: String(localized: "long run")
        case .tempo: String(localized: "threshold run")
        case .intervals: String(localized: "intervals")
        case .marathonPaceLong: String(localized: "marathon-pace long run")
        case .race: String(localized: "race")
        case .hills: String(localized: "hill session")
        }
    }

    var name: String {
        switch self {
        case .easy: String(localized: "Easy run")
        case .long: String(localized: "Long run")
        case .tempo: String(localized: "Threshold")
        case .intervals: String(localized: "Intervals")
        case .marathonPaceLong: String(localized: "Marathon-pace long run")
        case .race: String(localized: "Race day")
        case .hills: String(localized: "Hills")
        }
    }

    var purpose: String {
        switch self {
        case .easy: String(localized: "Builds your aerobic engine. Keep it conversational.")
        case .long: String(localized: "Builds endurance. Steady and relaxed; finish feeling you could go further.")
        case .tempo: String(localized: "Raises the pace you can hold for longer. Comfortably hard, controlled breathing.")
        case .intervals: String(localized: "Develops top-end fitness. Hard but even efforts; jog the recoveries.")
        case .marathonPaceLong: String(localized: "Practises race pace on tired legs. Start easy, then settle into goal pace.")
        case .race: String(localized: "This is what you trained for. Start controlled and enjoy it.")
        case .hills: String(localized: "Builds strength and power with less pounding than flat speedwork. Run the climbs hard but controlled, about 5K effort, and jog back down.")
        }
    }
}

extension Phase {
    var color: Color {
        switch self {
        case .base: Color(hex: 0x5CCB6A)
        case .build: Color(hex: 0xF5B13D)
        case .peak: Color(hex: 0xF26D6D)
        case .taper: Color(hex: 0xA9A9A9)
        }
    }

    var name: String {
        switch self {
        case .base: String(localized: "Base")
        case .build: String(localized: "Build")
        case .peak: String(localized: "Peak")
        case .taper: String(localized: "Taper")
        }
    }
}

extension PaceZone {
    var name: String {
        switch self {
        case .easy: String(localized: "easy")
        case .marathon: String(localized: "marathon pace")
        case .threshold: String(localized: "threshold")
        case .interval: String(localized: "interval pace")
        case .repetition: String(localized: "rep pace")
        case .race: String(localized: "race pace")
        case .stride: String(localized: "stride")
        case .hill: String(localized: "uphill")
        }
    }

    var color: Color {
        switch self {
        case .easy: WorkoutKind.easy.color
        case .marathon: WorkoutKind.marathonPaceLong.color
        case .threshold: WorkoutKind.tempo.color
        case .interval, .repetition: WorkoutKind.intervals.color
        case .race: WorkoutKind.race.color
        case .stride: WorkoutKind.easy.color
        case .hill: WorkoutKind.hills.color
        }
    }
}

extension RaceDistance {
    var name: String {
        switch self {
        case .fiveK: String(localized: "5K")
        case .tenK: String(localized: "10K")
        case .halfMarathon: String(localized: "Half marathon")
        case .marathon: String(localized: "Marathon")
        }
    }
}

extension Experience {
    var name: String {
        switch self {
        case .beginner: String(localized: "New to running")
        case .intermediate: String(localized: "Regular runner")
        case .advanced: String(localized: "Experienced")
        }
    }

    var detail: String {
        switch self {
        case .beginner: String(localized: "Running for under a year, or new to structured training.")
        case .intermediate: String(localized: "Running most weeks and have done a few races.")
        case .advanced: String(localized: "Training consistently with sessions like intervals and tempo runs.")
        }
    }
}

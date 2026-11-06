import SwiftUI
import UIKit
import PlanEngine

/// The app's visual language. Everything colour- and spacing-related lives here so the look
/// can be changed in one place.
enum Theme {
    static let accent = Color.accentColor
    static let ink = Color(light: 0x10242B, dark: 0xEEF4F3)
    static let secondaryInk = Color(light: 0x5B6D72, dark: 0x9DB0B2)
    static let background = Color(light: 0xF3F6F5, dark: 0x0A1113)
    static let card = Color(light: 0xFFFFFF, dark: 0x141F22)
    static let subtle = Color(light: 0xE5ECEA, dark: 0x203034)
    static let warning = Color(light: 0xB86E00, dark: 0xF2B24C)

    enum Radius {
        static let card: CGFloat = 22
        static let control: CGFloat = 16
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
    var color: Color {
        switch self {
        case .easy: Color(light: 0x2E9E7E, dark: 0x4CC7A2)
        case .long: Color(light: 0x2F63C9, dark: 0x6E98F0)
        case .tempo: Color(light: 0xD98A12, dark: 0xF2AE45)
        case .intervals: Color(light: 0xE04B3A, dark: 0xF5786A)
        case .marathonPaceLong: Color(light: 0x7A55C7, dark: 0xA88AF0)
        case .race: Color(light: 0xD23A73, dark: 0xF06A9B)
        }
    }

    var symbol: String {
        switch self {
        case .easy: "figure.run"
        case .long: "road.lanes"
        case .tempo: "gauge.with.dots.needle.67percent"
        case .intervals: "repeat"
        case .marathonPaceLong: "speedometer"
        case .race: "flag.checkered"
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
        }
    }
}

extension Phase {
    var color: Color {
        switch self {
        case .base: Color(light: 0x6FB5A2, dark: 0x5FA493)
        case .build: Color(light: 0x3F86D1, dark: 0x5E9BE0)
        case .peak: Color(light: 0xE06D3C, dark: 0xF08A5D)
        case .taper: Color(light: 0x9483D6, dark: 0xA999E6)
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
        }
    }

    var color: Color {
        switch self {
        case .easy: WorkoutKind.easy.color
        case .marathon: WorkoutKind.marathonPaceLong.color
        case .threshold: WorkoutKind.tempo.color
        case .interval, .repetition: WorkoutKind.intervals.color
        case .race: WorkoutKind.race.color
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

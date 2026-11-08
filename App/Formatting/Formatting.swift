import Foundation
import SwiftUI
import PlanEngine

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric, imperial

    var id: String { rawValue }

    static var localeDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    var distanceUnit: String { self == .metric ? String(localized: "km") : String(localized: "mi") }
    var metersPerUnit: Double { self == .metric ? 1000 : 1609.344 }
    /// Treadmill speed unit.
    var speedUnit: String { self == .metric ? "km/h" : "mph" }
    var name: String { self == .metric ? String(localized: "Kilometres") : String(localized: "Miles") }
}

extension EnvironmentValues {
    @Entry var unitSystem: UnitSystem = .metric
}

/// Turns engine values (metres, seconds, s/km) into display strings.
struct DisplayFormat {
    let units: UnitSystem

    /// "8 km", "12.5 km", "0.8 km". Whole numbers drop the decimal.
    func distance(_ meters: Double) -> String {
        let value = meters / units.metersPerUnit
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : rounded.formatted(.number.precision(.fractionLength(1)))
        return "\(text) \(units.distanceUnit)"
    }

    /// Interval reps read better in metres on any unit system ("800 m").
    func repDistance(_ meters: Double) -> String {
        meters < 2_000 ? "\(Int(meters)) m" : distance(meters)
    }

    /// Converts s/km to seconds per display unit.
    func paceSeconds(_ secondsPerKm: Double) -> Double { secondsPerKm * units.metersPerUnit / 1000 }

    func pace(_ secondsPerKm: Double) -> String {
        "\(Self.clock(paceSeconds(secondsPerKm))) /\(units.distanceUnit)"
    }

    func paceRange(_ range: PaceRange) -> String {
        "\(Self.clock(paceSeconds(range.fast)))–\(Self.clock(paceSeconds(range.slow))) /\(units.distanceUnit)"
    }

    /// "4:05", "1:32:05".
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 { return "\(h):\(m < 10 ? "0" : "")\(m):\(ss)" }
        return "\(m):\(ss)"
    }

    /// "45 min", "1 h 20 min".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return String(localized: "\(minutes) min") }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? String(localized: "\(h) h") : String(localized: "\(h) h \(m) min")
    }

    /// Short duration for recoveries: "90 s", "2 min", "2:30".
    /// Minutes for run/walk steps: "1 min", "1:30 min", "12 min".
    static func minutes(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s % 60 == 0 ? String(localized: "\(s / 60) min") : String(localized: "\(clock(seconds)) min")
    }

    static func shortDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 120 { return "\(s) s" }
        return s % 60 == 0 ? String(localized: "\(s / 60) min") : clock(seconds)
    }
}

extension LocalDate {
    nonisolated static var today: LocalDate { LocalDate(Date()) }

    func formatted(_ style: Date.FormatStyle) -> String { date().formatted(style) }

    /// "Fri 6 Nov" in the user's locale.
    var shortDayMonth: String { formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
    var dayMonth: String { formatted(.dateTime.day().month(.wide)) }
}

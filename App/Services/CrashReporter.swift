import Foundation
import MetricKit
import Observation

/// A crash from a previous run, as iOS reported it. Kept on the phone until the athlete sends or dismisses it.
nonisolated struct CrashReport: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var appVersion: String
    /// One line a person can read, e.g. "Crashed (SIGTRAP, a Swift runtime error)".
    var summary: String
    /// iOS's full diagnostic as JSON: the call stack (as code addresses), exception codes, app and OS versions.
    /// No personal data, health data or runs.
    var details: String

    /// Builds the readable line from the signal and termination reason iOS gives.
    static func summary(signal: Int?, terminationReason: String?) -> String {
        let names: [Int: String] = [
            4: "SIGILL, an illegal instruction", 5: "SIGTRAP, a Swift runtime error", 6: "SIGABRT, the app stopped itself",
            9: "SIGKILL, the system ended the app", 10: "SIGBUS, a memory error", 11: "SIGSEGV, a memory error",
        ]
        var text = "Crashed"
        if let signal { text += " (\(names[signal] ?? "signal \(signal)"))" }
        if let terminationReason, !terminationReason.isEmpty { text += ": \(terminationReason)" }
        return text
    }

    /// A made-up report, for checking the screens in debug builds.
    static let sample = CrashReport(date: .now, appVersion: "0.1.0 (1)",
                                    summary: summary(signal: 5, terminationReason: nil),
                                    details: #"{"crashDiagnostics":[{"diagnosticMetaData":{"signal":5}}]}"#)
}

/// Collects crash reports from iOS (MetricKit), which hands them to the app on a later launch, and keeps the latest
/// one until the athlete decides what to do with it. Nothing is sent anywhere: the report only leaves the phone if
/// the athlete emails it.
@Observable
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    private(set) var pending: CrashReport?
    private let file: URL
    private let defaults: UserDefaults
    private static let lastSeenKey = "crashReporter.lastSeen"

    init(directory: URL = URL.applicationSupportDirectory, defaults: UserDefaults = .standard) {
        file = directory.appending(path: "pending-crash.json")
        self.defaults = defaults
        super.init()
        if let data = try? Data(contentsOf: file) { pending = try? JSONDecoder().decode(CrashReport.self, from: data) }
    }

    /// Starts listening, and picks up any reports iOS already delivered.
    func start() {
        MXMetricManager.shared.add(self)
        accept(Self.reports(from: MXMetricManager.shared.pastDiagnosticPayloads))
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = Self.reports(from: payloads)
        Task { @MainActor in self.accept(reports) }
    }

    /// Keeps the newest report not seen before (iOS can hand the same payload over again on later launches).
    func accept(_ reports: [CrashReport]) {
        let lastSeen = defaults.object(forKey: Self.lastSeenKey) as? Date ?? .distantPast
        guard let newest = reports.filter({ $0.date > lastSeen }).max(by: { $0.date < $1.date }) else { return }
        defaults.set(newest.date, forKey: Self.lastSeenKey)
        pending = newest
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(newest).write(to: file, options: .atomic)
    }

    /// The athlete sent it or doesn't want to: forget it.
    func clear() {
        pending = nil
        try? FileManager.default.removeItem(at: file)
    }

    nonisolated private static func reports(from payloads: [MXDiagnosticPayload]) -> [CrashReport] {
        payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map { crash in
                let meta = crash.metaData
                return CrashReport(
                    date: payload.timeStampEnd,
                    appVersion: "\(meta.applicationBuildVersion)",
                    summary: CrashReport.summary(signal: crash.signal?.intValue, terminationReason: crash.terminationReason),
                    details: String(decoding: crash.jsonRepresentation(), as: UTF8.self))
            }
        }
    }
}

import Foundation
import Testing
@testable import TrackStar

@MainActor
struct CrashReporterTests {
    func reporter(_ name: String = UUID().uuidString) -> (CrashReporter, URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crash-tests-\(name)")
        let defaults = UserDefaults(suiteName: "crash-tests-\(name)")!
        return (CrashReporter(directory: directory, defaults: defaults), directory, defaults)
    }

    func report(_ minutesAgo: Double, _ summary: String = "Crashed") -> CrashReport {
        CrashReport(date: Date.now.addingTimeInterval(-minutesAgo * 60), appVersion: "1.0 (1)", summary: summary, details: "{}")
    }

    @Test func summariesAreReadable() {
        #expect(CrashReport.summary(signal: 5, terminationReason: nil) == "Crashed (SIGTRAP, a Swift runtime error)")
        #expect(CrashReport.summary(signal: 99, terminationReason: "Namespace SIGNAL") == "Crashed (signal 99): Namespace SIGNAL")
        #expect(CrashReport.summary(signal: nil, terminationReason: nil) == "Crashed")
    }

    @Test func keepsTheNewestAndSurvivesARelaunch() {
        let name = UUID().uuidString
        let (reporter, directory, defaults) = reporter(name)
        reporter.accept([report(30, "older"), report(5, "newer")])
        #expect(reporter.pending?.summary == "newer")

        let relaunched = CrashReporter(directory: directory, defaults: defaults)
        #expect(relaunched.pending?.summary == "newer")
        relaunched.clear()
        #expect(CrashReporter(directory: directory, defaults: defaults).pending == nil)
    }

    @Test func aReportIsOnlyOfferedOnce() {
        let (reporter, _, _) = reporter()
        let crash = report(10)
        reporter.accept([crash])
        reporter.clear()
        // iOS can deliver the same payload again on a later launch.
        reporter.accept([crash])
        #expect(reporter.pending == nil)
        reporter.accept([report(1, "a new one")])
        #expect(reporter.pending?.summary == "a new one")
    }

    @Test func crashReportsSayWhatHappened() {
        let crash = report(2, "Crashed (SIGSEGV, a memory error)")
        let mail = BugReport(appVersion: "1.0 (1)", device: "iPhone17,3, iOS 18.7", planDetails: nil, crash: crash)
        #expect(mail.mailSubject.contains("crash report"))
        #expect(mail.mailBody.contains("Crash: Crashed (SIGSEGV, a memory error)"))
        #expect(BugReport(appVersion: "1", device: "d", planDetails: nil).mailSubject.contains("bug report"))
    }
}

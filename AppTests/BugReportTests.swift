import Foundation
import Testing
import PlanEngine
@testable import Steppa

@MainActor
struct BugReportTests {
    @Test func urlFillsTheIssueTemplate() throws {
        let report = BugReport(appVersion: "0.1.0 (1)", device: "iPhone17,3, iOS 26.1", planDetails: "Half marathon & more")
        let components = try #require(URLComponents(url: report.url, resolvingAgainstBaseURL: false))
        #expect(components.host == "github.com")
        #expect(components.path == "/\(BugReport.repository)/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["template"] == "bug_report.yml")
        #expect(items["app-version"] == "0.1.0 (1)")
        #expect(items["device"] == "iPhone17,3, iOS 26.1")
        #expect(items["plan"] == "Half marathon & more")
        #expect(report.url.absoluteString.contains("%26")) // "&" in a value stays inside it
    }

    @Test func mailIsAddressedAndFilledIn() throws {
        let report = BugReport(appVersion: "0.1.0 (1)", device: "iPhone17,3, iOS 26.1", planDetails: "Half & more")
        #expect(report.mailSubject.contains("0.1.0 (1)"))
        #expect(report.mailBody.contains("What happened:"))
        #expect(report.mailBody.contains("Device: iPhone17,3, iOS 26.1"))
        let components = try #require(URLComponents(url: report.mailtoURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == BugReport.email)
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"] == report.mailSubject)
        #expect(items["body"] == report.mailBody)
    }

    @Test func planDetailsAreOptionalAndNeverPersonal() throws {
        let report = BugReport(appVersion: "1", device: "d", planDetails: nil)
        #expect(!report.url.absoluteString.contains("plan="))
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let summary = BugReport.planSummary(plan, today: AppModelTests.start)
        #expect(summary.hasPrefix(RaceDistance.halfMarathon.name))
        #expect(summary.contains("engine v\(plan.engineVersion)"))
    }

    @Test func templateFieldIDsExist() throws {
        // The URL's field names must match the issue form, or GitHub silently ignores them.
        let template = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".github/ISSUE_TEMPLATE/bug_report.yml"), encoding: .utf8)
        for id in ["app-version", "device", "plan"] {
            #expect(template.contains("id: \(id)\n"), "missing field \(id)")
        }
    }
}

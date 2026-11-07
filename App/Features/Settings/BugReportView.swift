import SwiftUI
import UIKit
import PlanEngine

/// A bug report as a pre-filled GitHub issue. Nothing is sent by the app: the report opens in the browser,
/// where the athlete reads it, edits it and submits it themselves (with a free GitHub account).
struct BugReport: Equatable {
    /// Where issues go. Forks: change this to your own repository.
    static let repository = "nickcia/steppa"

    var appVersion: String
    var device: String
    var planDetails: String?

    /// The new-issue page with the bug template's fields filled in (field ids from
    /// .github/ISSUE_TEMPLATE/bug_report.yml).
    var url: URL {
        var components = URLComponents(string: "https://github.com/\(Self.repository)/issues/new")!
        var items = [URLQueryItem(name: "template", value: "bug_report.yml"),
                     URLQueryItem(name: "app-version", value: appVersion),
                     URLQueryItem(name: "device", value: device)]
        if let planDetails { items.append(URLQueryItem(name: "plan", value: planDetails)) }
        components.queryItems = items
        return components.url!
    }

    /// The same details as text, for pasting into an email or message instead.
    var text: String {
        var lines = ["App version: \(appVersion)", "Device: \(device)"]
        if let planDetails { lines.append("Plan: \(planDetails)") }
        return lines.joined(separator: "\n")
    }

    static func planSummary(_ plan: TrainingPlan, today: LocalDate) -> String {
        let weeksLeft = max(0, today.days(until: plan.inputs.raceDate) / 7)
        let days = plan.inputs.runDays.sorted().map(\.mediumName).joined(separator: ", ")
        return "\(plan.inputs.goal.name), \(plan.weeks.count) weeks (\(weeksLeft) to go), runs on \(days), long run \(plan.inputs.longRunDay.mediumName), \(plan.inputs.experience.name), engine v\(plan.engineVersion)"
    }

    /// e.g. "iPhone17,3, iOS 18.7.3". The model identifier is what the system reports; it maps to a marketing name
    /// (iPhone17,3 is an iPhone 16).
    static var currentDevice: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\($0) simulator" } ?? machine
        return "\(model), iOS \(UIDevice.current.systemVersion)"
    }
}

struct BugReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var includePlan = true
    @State private var copied = false

    private var report: BugReport {
        BugReport(appVersion: Bundle.main.versionString, device: BugReport.currentDevice,
                  planDetails: includePlan ? model.plan.map { BugReport.planSummary($0, today: model.today) } : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Reports go to the project's public page on GitHub, where you describe what happened and submit it. You'll need a free GitHub account. Nothing is sent from the app.")
                        .font(.subheadline)
                }
                Section {
                    LabeledContent("App version", value: report.appVersion)
                    LabeledContent("Device", value: report.device)
                    if model.plan != nil {
                        Toggle("Include plan details", isOn: $includePlan)
                        if let details = report.planDetails {
                            Text(details).font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                } header: {
                    Text("Added to the report")
                } footer: {
                    Text("Reports are public. No health data, runs or personal details are included, and you can edit everything before submitting.")
                }
                Section {
                    Button {
                        openURL(report.url)
                        dismiss()
                    } label: {
                        Label("Continue to GitHub", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        UIPasteboard.general.string = report.text
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy details instead", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Report a bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

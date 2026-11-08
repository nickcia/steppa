import MessageUI
import SwiftUI
import UIKit
import PlanEngine

/// A bug report as a pre-filled email, or a GitHub issue for people who have an account. Nothing is sent by the
/// app itself: the athlete reads the message, edits it and sends it from their own Mail app.
struct BugReport: Equatable {
    /// Where issues go. Forks: change this to your own repository.
    static let repository = "nickcia/trackstar"
    /// Where emailed reports go. Forks: change this to your own address.
    static let email = "nickseeya@gmail.com"

    var appVersion: String
    var device: String
    var planDetails: String?
    /// A crash from a previous run, sent along with the report (attached in full when Mail is set up).
    var crash: CrashReport?

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

    var mailSubject: String { crash == nil ? "TrackStar bug report (\(appVersion))" : "TrackStar crash report (\(appVersion))" }

    /// Prompts for the description, then the details.
    var mailBody: String {
        if crash != nil {
            return """
            What were you doing when it closed? (optional)


            ---
            \(text)
            """
        }
        return """
        What happened:


        What you expected to happen:


        Steps to get there (if you know them):


        ---
        \(text)
        """
    }

    /// For phones without the Mail app set up: opens whichever email app handles mailto links.
    var mailtoURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.email
        components.queryItems = [URLQueryItem(name: "subject", value: mailSubject), URLQueryItem(name: "body", value: mailBody)]
        return components.url!
    }

    /// The same details as text, for pasting into an email or message instead.
    var text: String {
        var lines = ["App version: \(appVersion)", "Device: \(device)"]
        if let planDetails { lines.append("Plan: \(planDetails)") }
        if let crash {
            lines.append("Crash: \(crash.summary), \(crash.date.formatted(date: .abbreviated, time: .shortened)), version \(crash.appVersion)")
        }
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
    /// Set when this is the "TrackStar closed unexpectedly" report after a crash.
    var crash: CrashReport?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var includePlan = true
    @State private var copied = false
    @State private var composing = false

    private var report: BugReport {
        BugReport(appVersion: Bundle.main.versionString, device: BugReport.currentDevice,
                  planDetails: includePlan ? model.plan.map { BugReport.planSummary($0, today: model.today) } : nil,
                  crash: crash)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let crash {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TrackStar closed unexpectedly").font(.headline)
                            Text("Sorry about that. Sending the crash report helps fix it. Your email app opens with it ready to go; nothing is sent from TrackStar itself.")
                                .font(.subheadline)
                            Text(crash.summary).font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                    } else {
                        Text("Your email app opens with a message ready to go. Describe what happened, add a screenshot if it helps, and send. Nothing is sent from TrackStar itself.")
                            .font(.subheadline)
                    }
                }
                Section {
                    LabeledContent("App version", value: report.appVersion)
                    LabeledContent("Device", value: report.device)
                    if crash != nil {
                        LabeledContent("Crash report", value: String(localized: "Attached"))
                    }
                    if model.plan != nil {
                        Toggle("Include plan details", isOn: $includePlan)
                        if let details = report.planDetails {
                            Text(details).font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                } header: {
                    Text("Added to the report")
                } footer: {
                    Text("No health data, runs or personal details are included, and you can edit everything before sending.")
                }
                Section {
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            composing = true
                        } else {
                            openURL(report.mailtoURL) { opened in
                                if !opened {
                                    UIPasteboard.general.string = "\(BugReport.email)\n\n\(report.text)"
                                    copied = true
                                }
                            }
                        }
                    } label: {
                        Label("Email the report", systemImage: "envelope")
                    }
                    Button {
                        UIPasteboard.general.string = "\(BugReport.email)\n\n\(report.text)"
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy details instead", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } footer: {
                    Text(copied ? "Copied the address and details. Paste them into any email to \(BugReport.email)." : "Reports go to \(BugReport.email).")
                }
                if crash == nil {
                    Section {
                        Button {
                            openURL(report.url)
                            dismiss()
                        } label: {
                            Label("Report on GitHub instead", systemImage: "arrow.up.right.square")
                        }
                    } footer: {
                        Text("For people with a GitHub account. Reports there are public.")
                    }
                }
            }
            .navigationTitle(crash == nil ? "Report a bug" : "Crash report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(crash == nil ? "Close" : "Not now") { dismiss() } }
            }
            .sheet(isPresented: $composing) {
                MailComposer(report: report) { sent in
                    composing = false
                    if sent { dismiss() }
                }
                .ignoresSafeArea()
            }
        }
    }
}

/// The system's mail sheet, filled in with the report.
private struct MailComposer: UIViewControllerRepresentable {
    let report: BugReport
    let finished: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([BugReport.email])
        controller.setSubject(report.mailSubject)
        controller.setMessageBody(report.mailBody, isHTML: false)
        if let crash = report.crash {
            controller.addAttachmentData(Data(crash.details.utf8), mimeType: "application/json", fileName: "crash-report.json")
        }
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let finished: (Bool) -> Void
        init(finished: @escaping (Bool) -> Void) { self.finished = finished }

        nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                               didFinishWith result: MFMailComposeResult, error: Error?) {
            let sent = result == .sent
            MainActor.assumeIsolated { finished(sent) }
        }
    }
}

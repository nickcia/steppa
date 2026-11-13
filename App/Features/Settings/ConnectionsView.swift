import AuthenticationServices
import SwiftUI
import PlanEngine

/// Everything TrackStar connects to, on one page: where runs come from, the watch workouts go to, and Strava.
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                if model.healthConnected {
                    LabeledContent("Apple Health", value: String(localized: "\(model.healthRuns.count) runs found"))
                    Button("Refresh runs") { Task { await model.refreshHealth() } }
                } else {
                    Button {
                        Task { await model.connectHealth() }
                    } label: {
                        Label("Connect Apple Health", systemImage: "heart.text.square")
                    }
                    .disabled(!model.healthAvailable)
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Works with any iPhone. Runs from Apple Watch, Garmin, COROS and other apps that save to Health tick off your workouts automatically. Manage access in the Health app under Sharing › Apps.")
            }

            if model.watchSupported {
                AppleWatchSection()
            }

            if model.garminAvailable {
                GarminSection()
            }

            if model.intervalsAvailable {
                IntervalsSection()
            }

            if model.stravaAvailable {
                StravaSection()
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension AppModel {
    /// What's connected, for the Connections row in Settings: "Apple Health, Garmin, Strava".
    var connectionsSummary: String {
        var names: [String] = []
        if healthConnected { names.append(String(localized: "Apple Health")) }
        if watchSupported, watchAutoSync { names.append(String(localized: "Apple Watch")) }
        if garminConnected { names.append("Garmin") }
        if intervalsAccount != nil { names.append("Intervals.icu") }
        if stravaAccount != nil { names.append("Strava") }
        return names.isEmpty ? String(localized: "Apple Health, watches and Strava") : names.formatted(.list(type: .and))
    }
}

/// Apple Watch: only shown when one is paired with this iPhone.
private struct AppleWatchSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle("Send the next 7 days automatically",
                   isOn: Binding(get: { model.watchAutoSync }, set: { on in Task { await model.setWatchAutoSync(on) } }))
            if let plan = model.plan {
                Button("Sync now") {
                    Task {
                        await model.sendToWatch(plan.workouts.filter {
                            $0.date >= model.today && model.today.days(until: $0.date) < 7
                        })
                    }
                }
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let problem = model.watchProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                }
                Text("Workouts appear in the Workout app on your watch with each step and pace alerts, ready to start.")
            }
        }
    }
}

/// Garmin Connect™: one sign-in, then workouts go to the watch and runs come back.
struct GarminSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var connecting = false
    @State private var confirmDisconnect = false
    @State private var error: String?

    var body: some View {
        Section {
            if model.garminConnected {
                LabeledContent("Garmin Connect™", value: String(localized: "Connected"))
                Button {
                    Task { await model.syncGarmin(force: true) }
                } label: {
                    HStack {
                        Text("Sync now")
                        Spacer()
                        if model.garminSyncing {
                            ProgressView()
                        } else if let last = model.garminLastSync {
                            Text(last, format: .relative(presentation: .named))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                }
                .disabled(model.garminSyncing)
                if let problem = model.garminProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Garmin watch").font(.headline).foregroundStyle(Theme.ink)
                        Text("Workouts appear on your watch with every step and pace, and runs you finish come back to tick off your plan. Sign in once; there's nothing else to set up.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { connect() } label: {
                        // Garmin's own app tile beside its full name, as Garmin's brand guidelines ask for sign-in.
                        HStack(spacing: 10) {
                            if connecting {
                                ProgressView().tint(.white).frame(width: 28, height: 28)
                            } else {
                                Image("GarminConnectTile")
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .accessibilityHidden(true)
                            }
                            Text("Connect with Garmin Connect™")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    .disabled(connecting)
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text("Garmin")
        } footer: {
            Text(model.garminConnected
                 ? "The next two weeks of workouts are on your Garmin Connect™ calendar and follow your plan as it changes. Runs from your Garmin show here, marked with your device. They're never shown to the coach."
                 : "You'll sign in on Garmin's own page. TrackStar never sees your Garmin password.")
        }
        .confirmationDialog("Disconnect Garmin Connect™?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnectGarmin() } }
        } message: {
            Text("TrackStar's upcoming workouts are removed from your Garmin Connect™ calendar, and your Garmin runs are deleted from this iPhone and from TrackStar's server.")
        }
        .alert("Couldn't connect to Garmin", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func connect() {
        connecting = true
        Task {
            defer { connecting = false }
            do {
                let url = try await model.garminSignInURL()
                let callback = try await webAuthenticationSession.authenticate(
                    using: url, callbackURLScheme: model.garminCallbackScheme, preferredBrowserSession: .shared)
                try await model.finishGarminSignIn(callback: callback)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Closed the sheet.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Garmin, COROS and other watches, through the athlete's own (free) Intervals.icu account.
struct IntervalsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openURL) private var openURL
    @State private var enteringKey = false
    @State private var signingIn = false
    @State private var confirmDisconnect = false
    @State private var signInError: String?
    @State private var settingUpWatch = false

    var body: some View {
        Section {
            if let account = model.intervalsAccount {
                LabeledContent("Intervals.icu", value: account.athleteName.isEmpty ? String(localized: "Connected") : account.athleteName)
                // With Garmin connected directly, Intervals.icu brings in runs and zones but doesn't send workouts.
                if model.intervalsSendsWorkouts {
                    watchRows
                    syncRow
                }
                if let problem = model.intervalsProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            } else {
                Button {
                    if model.intervalsOAuth != nil { signIn() } else { enteringKey = true }
                } label: {
                    HStack {
                        Label(model.garminAvailable ? "Connect COROS, Suunto or Wahoo" : "Connect Garmin, COROS and others",
                              systemImage: "applewatch.radiowaves.left.and.right")
                        if signingIn { Spacer(); ProgressView() }
                    }
                }
                .disabled(signingIn)
            }
        } header: {
            Text("Other watches")
        } footer: {
            if model.intervalsAccount == nil {
                Text(model.garminAvailable
                     ? "Workouts are sent through Intervals.icu, a free training site that passes them on to COROS, Suunto and Wahoo. You'll sign in to Intervals.icu (or create a free account), then link your watch there once."
                     : "Workouts are sent through Intervals.icu, a free training site that passes them on to Garmin Connect, COROS, Suunto and Wahoo. You'll sign in to Intervals.icu (or create a free account), then link your watch there once.")
            } else if model.intervalsSendsWorkouts {
                Text("Your upcoming workouts are on your Intervals.icu calendar and are kept in step with your plan. Linked watches get them a few days ahead.")
            } else {
                Text("Runs and heart-rate zones come in from Intervals.icu.")
            }
        }
        .sheet(isPresented: $enteringKey) { IntervalsAPIKeyView() }
        .sheet(isPresented: $settingUpWatch) { WatchSetupView() }
        .confirmationDialog("Disconnect Intervals.icu?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnectIntervals() } }
        } message: {
            Text("Upcoming workouts from this app are removed from your Intervals.icu calendar, and this iPhone forgets the connection.")
        }
        .alert("Couldn't connect", isPresented: Binding(get: { signInError != nil }, set: { if !$0 { signInError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInError ?? "")
        }
    }

    private var syncRow: some View {
        Button {
            Task { await model.syncIntervals(force: true) }
        } label: {
            HStack {
                Text("Sync now")
                Spacer()
                if model.intervalsSyncing {
                    ProgressView()
                } else if let last = model.intervalsLastSync {
                    Text(last, format: .relative(presentation: .named))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
        }
        .disabled(model.intervalsSyncing)
    }

    /// One row per linked watch service, or a prompt to link one.
    @ViewBuilder private var watchRows: some View {
        if let athlete = model.intervalsAthlete {
            ForEach(athlete.links) { link in
                // A plain row: LabeledContent with a Label value grew a large empty space below it on iOS 27, and a
                // Label here showed only its icon.
                HStack {
                    Text(link.name)
                    Spacer(minLength: 8)
                    if link.uploading {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Receiving workouts")
                        }
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    } else {
                        Button("Turn on") { Task { await model.enableIntervalsUpload(link) } }
                    }
                }
            }
            if !athlete.links.contains(where: { $0.service == .garmin }) {
                Button {
                    settingUpWatch = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(athlete.links.isEmpty ? "Link your watch" : "Link Garmin", systemImage: "link")
                        Text("A one-time step on Intervals.icu, about a minute. We'll walk you through it.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
        }
    }

    private func signIn() {
        guard let oauth = model.intervalsOAuth else { return }
        let attempt = oauth.start()
        signingIn = true
        Task {
            defer { signingIn = false }
            do {
                let callback = try await webAuthenticationSession.authenticate(
                    using: attempt.url, callbackURLScheme: oauth.callbackScheme, preferredBrowserSession: .shared)
                try await model.finishIntervalsSignIn(callback: callback, attempt: attempt)
                // Signed in: straight on to linking the watch (or confirming it's already linked).
                settingUpWatch = true
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // The athlete closed the sign-in sheet.
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}

/// Connect with a personal Intervals.icu API key: for builds without an OAuth client ID.
private struct IntervalsAPIKeyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("In Intervals.icu, open Settings, scroll to Developer Settings, tap Generate API key and copy it.")
                    Link(destination: AppModel.intervalsConnectionsURL) {
                        Label("Open Intervals.icu settings", systemImage: "safari")
                    }
                }

                Section {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("API key")
                } footer: {
                    Text("Your key is stored in this iPhone's Keychain and only ever sent to Intervals.icu.")
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Intervals.icu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Connect") { connect() }
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(working)
        }
    }

    private func connect() {
        working = true
        error = nil
        Task {
            do {
                try await model.connectIntervals(apiKey: apiKey)
                dismiss()
            } catch IntervalsError.unauthorized {
                self.error = String(localized: "Intervals.icu didn't accept that key. Check you copied all of it.")
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

/// Strava: phone runs upload to the athlete's account as they finish.
struct StravaSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openURL) private var openURL
    @State private var connecting = false
    @State private var confirmDisconnect = false
    @State private var error: String?

    /// Strava's official "Connect with Strava" button (its artwork, unchanged, 48 pt tall as the guidelines say).
    private var connectButton: some View {
        Button { connect() } label: {
            Image("StravaConnectButton")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .opacity(connecting ? 0.5 : 1)
                .overlay { if connecting { ProgressView().tint(.white) } }
        }
        .buttonStyle(.plain)
        .disabled(connecting)
        .accessibilityLabel("Connect with Strava")
    }

    var body: some View {
        Section {
            if model.stravaPausedByServer {
                // Switched off on TrackStar's server, e.g. if Strava withdraws access: nothing to connect to for now.
                Label("Strava isn't available in TrackStar right now. Your runs are still saved to Apple Health, and your watch's own Strava sync still works.",
                      systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                if model.stravaAccount != nil {
                    if model.stravaQueuedCount > 0 {
                        LabeledContent("Waiting to upload", value: "\(model.stravaQueuedCount)")
                    }
                    Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                }
            } else if let account = model.stravaAccount {
                LabeledContent("Strava", value: account.athleteName.isEmpty ? String(localized: "Connected") : account.athleteName)
                Toggle("Upload phone runs", isOn: Binding(get: { model.stravaAutoUpload }, set: { model.setStravaAutoUpload($0) }))
                if account.canRead {
                    Toggle("Name watch runs after your plan", isOn: Binding(get: { model.stravaNamesWatchRuns },
                                                                           set: { model.setStravaNamesWatchRuns($0) }))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Name watch runs after your plan")
                        Text("Reconnect once to let TrackStar see your recent activities, so watch runs get your plan's name and phone runs aren't uploaded twice.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                        connectButton
                    }
                    .padding(.vertical, 4)
                }
                if model.stravaQueuedCount > 0 {
                    Button {
                        Task { await model.sendQueuedStravaUploads() }
                    } label: {
                        LabeledContent("Waiting to upload", value: "\(model.stravaQueuedCount)")
                    }
                }
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your runs on Strava").font(.headline).foregroundStyle(Theme.ink)
                        Text("Phone runs upload as you finish, with their route and your plan's title. Watch runs get the same title.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    connectButton
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text("Strava")
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.stravaAccount == nil
                     ? "Runs from Garmin and other watches reach Strava through their own apps; TrackStar doesn't upload them twice."
                     : "Phone runs upload as soon as you finish. If your watch recorded the same run, its copy is used instead, so nothing appears twice. Watch runs get your plan's name and steps unless you've renamed them.")
                // Strava's own mark, as its brand guidelines ask, kept small and apart from TrackStar's name.
                Image("StravaCompatibleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 12)
                    .accessibilityLabel("Compatible with Strava")
            }
        }
        .confirmationDialog("Disconnect Strava?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnectStrava() } }
        } message: {
            Text("Runs already on Strava stay there. New phone runs won't upload.")
        }
        .alert("Couldn't connect to Strava", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    /// With the Strava app installed, its own "Authorize" screen (one tap, no password); otherwise Strava's page in
    /// a sheet.
    private func connect() {
        guard let oauth = model.stravaOAuth else { return }
        let attempt = oauth.start()
        if UIApplication.shared.canOpenURL(attempt.appURL) {
            model.stravaPendingAttempt = attempt
            openURL(attempt.appURL)
            return
        }
        connecting = true
        Task {
            defer { connecting = false }
            do {
                let callback = try await webAuthenticationSession.authenticate(
                    using: attempt.webURL, callbackURLScheme: oauth.callbackScheme, preferredBrowserSession: .shared)
                try await model.finishStravaSignIn(callback: callback, attempt: attempt)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Closed the sheet.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

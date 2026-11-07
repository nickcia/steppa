import CryptoKit
import Foundation
import Security
import PlanEngine

// Intervals.icu sync: puts upcoming workouts on the athlete's Intervals.icu calendar, which can pass them on
// to Garmin Connect (and Coros, Suunto, Wahoo). The phone talks to Intervals.icu directly with the athlete's
// own API key; there's still no server of ours in between.
//
// API reference: https://intervals.icu/api/v1/docs (OpenAPI). The app signs in with OAuth as a public client
// using PKCE, so there's no client secret and no server: https://forum.intervals.icu/t/intervals-icu-oauth-support/2759
// People building the app themselves can paste a personal API key instead (HTTP Basic, username "API_KEY").

/// One planned workout as an Intervals.icu calendar event.
nonisolated struct IntervalsEvent: Codable, Hashable, Sendable {
    var category = "WORKOUT"
    var type = "Run"
    /// Local midnight of the workout day, e.g. "2026-11-08T00:00:00".
    var start_date_local: String
    var name: String
    /// The workout in Intervals.icu's workout-builder text format.
    var description: String
    /// "steppa-<workout id>-<content hash>": marks events this app owns, and changes whenever the workout does.
    var external_id: String
}

/// Converts plan workouts into Intervals.icu events. Pure, so it's unit-tested.
enum IntervalsWorkoutBuilder {
    nonisolated static let externalIDPrefix = "steppa-"

    static func event(for workout: Workout, format: DisplayFormat) -> IntervalsEvent {
        let name = "\(workout.kind.name) · \(WorkoutDescriber(format: format).summary(workout))"
        let text = description(for: workout, units: format.units)
        return IntervalsEvent(start_date_local: "\(workout.date.description)T00:00:00", name: name,
                              description: text, external_id: externalID(for: workout, name: name, text: text))
    }

    static func externalID(for workout: Workout, name: String, text: String) -> String {
        let digest = SHA256.hash(data: Data("\(workout.date)|\(name)|\(text)".utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(externalIDPrefix)\(workout.id)-\(hash)"
    }

    /// The workout-builder text, e.g.
    ///
    ///     Warmup
    ///     - 10m
    ///
    ///     Main set 5x
    ///     - 1km 4:10-4:00/km Pace
    ///     - 2m
    ///
    ///     Cooldown
    ///     - 10m
    static func description(for workout: Workout, units: UnitSystem) -> String {
        var sections: [String] = []
        if let warmup = workout.warmup {
            sections.append("Warmup\n" + line(warmup, units: units))
        }
        for (index, block) in workout.blocks.enumerated() {
            var header = workout.blocks.count > 1 ? "Main set \(index + 1)" : "Main set"
            if block.iterations > 1 { header += " \(block.iterations)x" }
            sections.append(([header] + block.steps.map { line($0.step, units: units) }).joined(separator: "\n"))
        }
        if let cooldown = workout.cooldown {
            sections.append("Cooldown\n" + line(cooldown, units: units))
        }
        return sections.joined(separator: "\n\n")
    }

    static func line(_ step: Step, units: UnitSystem) -> String {
        var parts = ["-", amount(step.goal)]
        if let target = step.target { parts.append(pace(target.range, units: units)) }
        return parts.joined(separator: " ")
    }

    /// Distances in km (a bare "m" means minutes in this format); times in whole minutes or seconds.
    static func amount(_ goal: StepGoal) -> String {
        switch goal {
        case .distance(let meters):
            // Always a "." decimal point, whatever the phone's locale: "0.4km", "1.609km", "16km".
            var text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), meters / 1000)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            return "\(text)km"
        case .time(let seconds):
            let whole = Int(seconds.rounded())
            return whole % 60 == 0 ? "\(whole / 60)m" : "\(whole)s"
        }
    }

    /// An absolute pace range, slow to fast: "5:10-4:50/km Pace".
    static func pace(_ range: PaceRange, units: UnitSystem) -> String {
        let format = DisplayFormat(units: units)
        let slow = DisplayFormat.clock(format.paceSeconds(range.slow))
        let fast = DisplayFormat.clock(format.paceSeconds(range.fast))
        return "\(slow)-\(fast)/\(units == .metric ? "km" : "mi") Pace"
    }
}

/// The athlete's Intervals.icu connection, kept in the Keychain on this device only.
nonisolated struct IntervalsCredentials: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// An OAuth access token from "Sign in with Intervals.icu".
        case oauth
        /// A personal API key, for people building the app themselves.
        case apiKey
    }

    var kind: Kind
    var token: String
    var athleteID: String
    var athleteName: String

    var authorization: String {
        switch kind {
        case .oauth: "Bearer \(token)"
        case .apiKey: "Basic \(Data("API_KEY:\(token)".utf8).base64EncodedString())"
        }
    }
}

/// Stores the Intervals.icu credentials in the Keychain (this device only, not synced).
nonisolated struct IntervalsKeychain: Sendable {
    var service = "io.github.nickcia.runcoach.intervals"

    func load() -> IntervalsCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(IntervalsCredentials.self, from: data)
    }

    func save(_ credentials: IntervalsCredentials) throws {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = try JSONEncoder().encode(credentials)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw IntervalsError.keychain(status) }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "default"]
    }
}

nonisolated enum IntervalsError: LocalizedError, Equatable {
    /// The token or key was refused (revoked, regenerated or mistyped).
    case unauthorized
    case server(Int)
    case offline
    case keychain(OSStatus)
    /// Sign-in didn't complete (declined, or the reply didn't match the request).
    case signInFailed

    var errorDescription: String? {
        switch self {
        case .unauthorized: String(localized: "Intervals.icu didn't accept this app's access. Disconnect and connect again in Settings.")
        case .server(let code): String(localized: "Intervals.icu couldn't sync right now (error \(code)). It'll try again next time you open the app.")
        case .offline: String(localized: "Couldn't reach Intervals.icu. Check your connection; it'll try again next time you open the app.")
        case .keychain: String(localized: "Couldn't save your Intervals.icu connection on this iPhone.")
        case .signInFailed: String(localized: "Signing in to Intervals.icu didn't finish. Please try again.")
        }
    }
}

/// "Sign in with Intervals.icu": OAuth 2 authorization code flow with PKCE, as a public client.
nonisolated struct IntervalsOAuth: Sendable {
    /// From Config/App.xcconfig (INTERVALS_CLIENT_ID). Not a secret: public clients have none.
    var clientID: String
    /// Where Intervals.icu sends the athlete back. Must be registered exactly on the app's management page.
    var redirectURI: String
    /// Planned workouts; settings, to check watch links and turn on workout upload; and completed runs, for
    /// run analysis with the full data the watch recorded.
    static let scopes = "CALENDAR:WRITE,SETTINGS:WRITE,ACTIVITY:READ"

    /// Reads INTERVALS_CLIENT_ID from Info.plist; nil when this build has no client ID (forks, local builds).
    static var configured: IntervalsOAuth? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "IntervalsClientID") as? String,
              !id.trimmingCharacters(in: .whitespaces).isEmpty,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return IntervalsOAuth(clientID: id, redirectURI: "\(bundleID.lowercased())://intervals-oauth")
    }

    var callbackScheme: String { String(redirectURI.prefix { $0 != ":" }) }

    /// One sign-in attempt: a fresh verifier and state.
    struct Attempt: Sendable {
        var verifier: String
        var state: String
        var url: URL
    }

    func start() -> Attempt {
        let verifier = Self.randomString(length: 64)
        let state = Self.randomString(length: 24)
        var components = URLComponents(string: "https://intervals.icu/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return Attempt(verifier: verifier, state: state, url: components.url!)
    }

    /// The authorization code from the redirect, after checking it answers this attempt.
    static func code(from callback: URL, attempt: Attempt) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == attempt.state, value("error") == nil, let code = value("code"), !code.isEmpty else {
            throw IntervalsError.signInFailed
        }
        return code
    }

    /// BASE64URL(SHA256(verifier)) without padding.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }
}

/// Watch services linked to the athlete's Intervals.icu account, and whether workouts are sent to each.
nonisolated struct IntervalsAthlete: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var icu_garmin_training: Bool?
    var icu_garmin_health: Bool?
    var icu_garmin_sync_activities: Bool?
    var icu_garmin_upload_workouts: Bool?
    var coros_user_id: String?
    var coros_upload_workouts: Bool?
    var suunto_user_id: String?
    var suunto_upload_workouts: Bool?
    var wahoo_user_id: String?
    var wahoo_upload_workouts: Bool?

    struct Link: Hashable, Sendable, Identifiable {
        enum Service: String, Sendable, CaseIterable { case garmin, coros, suunto, wahoo }
        var service: Service
        /// Workouts on the Intervals.icu calendar are passed on to this service.
        var uploading: Bool
        var id: Service { service }

        var name: String {
            switch service {
            case .garmin: "Garmin"
            case .coros: "COROS"
            case .suunto: "Suunto"
            case .wahoo: "Wahoo"
            }
        }

        /// The athlete-settings field that switches workout upload on.
        var uploadField: String {
            switch service {
            case .garmin: "icu_garmin_upload_workouts"
            case .coros: "coros_upload_workouts"
            case .suunto: "suunto_upload_workouts"
            case .wahoo: "wahoo_upload_workouts"
            }
        }
    }

    /// Services the athlete has linked. Garmin has no user ID in the API; a link shows up as granted
    /// permissions (icu_garmin_training is the one that lets Intervals.icu send workouts).
    var links: [Link] {
        var links: [Link] = []
        if icu_garmin_training == true || icu_garmin_health == true || icu_garmin_sync_activities == true {
            links.append(Link(service: .garmin, uploading: icu_garmin_upload_workouts == true))
        }
        if coros_user_id?.isEmpty == false { links.append(Link(service: .coros, uploading: coros_upload_workouts == true)) }
        if suunto_user_id?.isEmpty == false { links.append(Link(service: .suunto, uploading: suunto_upload_workouts == true)) }
        if wahoo_user_id?.isEmpty == false { links.append(Link(service: .wahoo, uploading: wahoo_upload_workouts == true)) }
        return links
    }
}

/// A completed run on Intervals.icu (only the fields the app uses).
nonisolated struct IntervalsActivity: Decodable, Hashable, Sendable {
    var id: String
    var start_date_local: String
    var type: String?
    var distance: Double?
    var moving_time: Double?
    var elapsed_time: Double?
    var device_name: String?

    var isRun: Bool { ["Run", "VirtualRun", "TrailRun"].contains(type ?? "") }

    var date: LocalDate? { LocalDate(iso: String(start_date_local.prefix(10))) }

    /// As a completed run, for activities with no matching run in Apple Health.
    var completedRun: CompletedRun? {
        guard isRun, let date, let distance, distance >= RunMatcher.minimumRunMeters,
              let seconds = moving_time ?? elapsed_time, seconds > 0 else { return nil }
        return CompletedRun(id: "icu-\(id)", date: date, distanceMeters: distance, durationSeconds: seconds)
    }
}

/// Sends HTTP requests. A protocol so tests can stand in for Intervals.icu.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw IntervalsError.offline }
        return (data, http)
    }
}

/// Talks to the Intervals.icu API.
nonisolated struct IntervalsClient: Sendable {
    var baseURL = URL(string: "https://intervals.icu/")!
    var transport: any HTTPTransport = URLSessionTransport()

    /// An event already on the calendar (only the fields sync needs).
    struct ExistingEvent: Decodable, Hashable, Sendable {
        var id: Int
        var external_id: String?
    }

    struct SyncResult: Hashable, Sendable {
        var added: Int
        var removed: Int
    }

    private struct TokenResponse: Decodable {
        struct Athlete: Decodable { var id: String; var name: String? }
        var access_token: String
        var athlete: Athlete?
    }

    /// Swaps the authorization code for an access token (PKCE: the verifier stands in for a client secret).
    func signIn(code: String, attempt: IntervalsOAuth.Attempt, oauth: IntervalsOAuth) async throws -> IntervalsCredentials {
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "client_id", value: oauth.clientID),
                           URLQueryItem(name: "code", value: code),
                           URLQueryItem(name: "code_verifier", value: attempt.verifier)]
        var request = URLRequest(url: baseURL.appending(path: "api/oauth/token"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let data = try await perform(request, failure: .signInFailed)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        var credentials = IntervalsCredentials(kind: .oauth, token: token.access_token,
                                               athleteID: token.athlete?.id ?? "0", athleteName: token.athlete?.name ?? "")
        if token.athlete == nil {
            let athlete = try await athlete(credentials)
            credentials.athleteID = athlete.id
            credentials.athleteName = athlete.name ?? athlete.id
        }
        return credentials
    }

    /// Checks a personal API key and returns credentials for the athlete it belongs to.
    func signIn(apiKey: String) async throws -> IntervalsCredentials {
        var credentials = IntervalsCredentials(kind: .apiKey, token: apiKey, athleteID: "0", athleteName: "")
        let athlete = try await athlete(credentials)
        credentials.athleteID = athlete.id
        credentials.athleteName = athlete.name ?? athlete.id
        return credentials
    }

    /// The athlete and their linked watch services. "0" means "the athlete these credentials belong to".
    func athlete(_ credentials: IntervalsCredentials) async throws -> IntervalsAthlete {
        let data = try await send("api/v1/athlete/0", method: "GET", credentials: credentials)
        return try JSONDecoder().decode(IntervalsAthlete.self, from: data)
    }

    /// Turns on workout upload for these linked services.
    func enableUpload(for links: [IntervalsAthlete.Link], credentials: IntervalsCredentials) async throws {
        guard !links.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: links.map { ($0.uploadField, true) }))
        _ = try await send("api/v1/athlete/0", method: "PUT", credentials: credentials, body: body)
    }

    /// Completed activities between two dates, newest first.
    func activities(from: LocalDate, through: LocalDate, credentials: IntervalsCredentials) async throws -> [IntervalsActivity] {
        let data = try await send(
            "api/v1/athlete/\(credentials.athleteID)/activities", method: "GET", credentials: credentials,
            query: [URLQueryItem(name: "oldest", value: from.description),
                    URLQueryItem(name: "newest", value: through.description),
                    URLQueryItem(name: "fields", value: "id,start_date_local,type,distance,moving_time,elapsed_time,device_name")])
        return try JSONDecoder().decode([IntervalsActivity].self, from: data)
    }

    private struct Stream: Decodable {
        var type: String
        var data: [Double?]?
    }

    /// The activity's recorded data over time.
    func series(activityID: String, credentials: IntervalsCredentials) async throws -> RunSeries? {
        let data = try await send(
            "api/v1/activity/\(activityID)/streams.json", method: "GET", credentials: credentials,
            query: [URLQueryItem(name: "types", value: "time,distance,heartrate,watts,cadence,altitude")])
        let streams = try JSONDecoder().decode([Stream].self, from: data)
        return Self.series(from: Dictionary(streams.map { ($0.type, $0.data ?? []) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Lines the streams up against the time stream, skipping gaps.
    static func series(from streams: [String: [Double?]]) -> RunSeries? {
        guard let time = streams["time"], !time.isEmpty else { return nil }
        func points(_ key: String, scale: Double = 1) -> [RunSeries.Point] {
            guard let values = streams[key] else { return [] }
            return zip(time, values).compactMap { t, v in
                guard let t, let v else { return nil }
                return RunSeries.Point(t, v * scale)
            }
        }
        // Garmin records running cadence per foot; double it to steps per minute when it looks that way.
        var cadence = points("cadence")
        let sorted = cadence.map(\.v).filter { $0 > 0 }.sorted()
        if !sorted.isEmpty, sorted[sorted.count / 2] < 120 {
            cadence = cadence.map { .init($0.t, $0.v * 2) }
        }
        let series = RunSeries(distance: points("distance"), heartRate: points("heartrate"), power: points("watts"),
                               cadence: cadence, altitude: points("altitude"))
        return series.isEmpty ? nil : series
    }

    /// Makes this app's events from `from` onwards match `events` exactly: adds what's missing and removes what
    /// changed or no longer exists. Events the athlete added themselves, and anything in the past, are left alone.
    func sync(_ events: [IntervalsEvent], from: LocalDate, through: LocalDate,
              credentials: IntervalsCredentials) async throws -> SyncResult {
        let athlete = "api/v1/athlete/\(credentials.athleteID)"
        let data = try await send(
            "\(athlete)/events", method: "GET", credentials: credentials,
            query: [URLQueryItem(name: "oldest", value: from.description),
                    URLQueryItem(name: "newest", value: through.description),
                    URLQueryItem(name: "category", value: "WORKOUT"),
                    URLQueryItem(name: "fields", value: "id,external_id")])
        let existing = try JSONDecoder().decode([ExistingEvent].self, from: data)
        let plan = Self.diff(wanted: events, existing: existing)

        if !plan.remove.isEmpty {
            let body = try JSONEncoder().encode(plan.remove.map { ["id": $0] })
            _ = try await send("\(athlete)/events/bulk-delete", method: "PUT", credentials: credentials, body: body)
        }
        if !plan.add.isEmpty {
            _ = try await send("\(athlete)/events/bulk", method: "POST", credentials: credentials,
                               body: try JSONEncoder().encode(plan.add))
        }
        return SyncResult(added: plan.add.count, removed: plan.remove.count)
    }

    /// What to add and what to remove (by event ID). Only events with this app's prefix are ever removed.
    static func diff(wanted: [IntervalsEvent], existing: [ExistingEvent]) -> (add: [IntervalsEvent], remove: [Int]) {
        let ours = existing.filter { $0.external_id?.hasPrefix(IntervalsWorkoutBuilder.externalIDPrefix) == true }
        let present = Set(ours.compactMap(\.external_id))
        let wantedIDs = Set(wanted.map(\.external_id))
        var seen: Set<String> = []
        // Drop stale events, and any duplicates of the same workout.
        let remove = ours.filter { event in
            guard let id = event.external_id, wantedIDs.contains(id) else { return true }
            return !seen.insert(id).inserted
        }.map(\.id)
        return (wanted.filter { !present.contains($0.external_id) }, remove)
    }

    // MARK: HTTP

    private func send(_ path: String, method: String, credentials: IntervalsCredentials,
                      query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request, failure: .unauthorized)
    }

    private func perform(_ request: URLRequest, failure: IntervalsError) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as IntervalsError {
            throw error
        } catch {
            throw IntervalsError.offline
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw failure
        case 400 where failure == .signInFailed: throw failure // e.g. an expired or reused code
        default: throw IntervalsError.server(response.statusCode)
        }
    }
}

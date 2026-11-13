import CoreLocation
import Foundation
import Security

// Strava: runs recorded on the phone (guided runs) go straight to the athlete's Strava account, with their route,
// as soon as they finish. Strava doesn't take runs that other apps save to Apple Health, so this is the only way
// they get there. Runs recorded on a watch reach Strava through Garmin Connect (or Apple's Health import), so they
// aren't uploaded again: TrackStar looks at the athlete's recent Strava activities to spot a watch's copy of the
// same run, and to give watch runs the plan's name ("Week 5 - Threshold 7 km") and steps. Only times, distances,
// names and descriptions are read, on the phone, and only the athlete's own planned runs are renamed.

/// The connection to the athlete's Strava account.
nonisolated struct StravaCredentials: Codable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// When the access token stops working (they last six hours).
    var expiresAt: Date
    var athleteID: Int
    var athleteName: String
    /// What the athlete allowed. nil for connections made before reading was asked for (upload only).
    var scope: String? = nil

    /// Allowed to read activities: needed to spot a watch's copy of a run and to name watch runs.
    var canRead: Bool { scope?.contains("activity:read") ?? false }

    /// Refreshed a few minutes early so a token never runs out mid-upload.
    func needsRefresh(at now: Date = .now) -> Bool { expiresAt.timeIntervalSince(now) < 5 * 60 }
}

nonisolated enum StravaError: LocalizedError, Equatable {
    /// The connection was revoked on Strava, or upload permission was unticked when connecting.
    case unauthorized
    case offline
    case server(Int)
    /// Strava couldn't read the activity (its own message).
    case rejected(String)
    case signInFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unauthorized: String(localized: "Strava didn't accept TrackStar's access. Disconnect and connect again in Settings, and leave \"Upload your activities\" ticked.")
        case .offline: String(localized: "Couldn't reach Strava. Your run will upload when you're back online.")
        case .server(429): String(localized: "Strava is busy right now. Your run will upload a bit later.")
        case .server(let code): String(localized: "Strava couldn't take the run right now (error \(code)). It'll try again later.")
        case .rejected(let message): String(localized: "Strava couldn't use this run: \(message)")
        case .signInFailed: String(localized: "Connecting to Strava didn't finish. Please try again.")
        case .keychain: String(localized: "Couldn't save your Strava connection on this iPhone.")
        }
    }

    /// Worth trying again later (no connection, or Strava having a moment).
    var isTemporary: Bool {
        switch self {
        case .offline, .server: true
        default: false
        }
    }
}

/// "Connect Strava": OAuth 2 authorization code flow. Strava has no PKCE, so the token swap needs the app's client
/// secret. TrackStar's own builds send the token requests through TrackStar's server, which adds the secret, so it
/// never ships in the app. Builds without a server (forks) can put their own secret in Config/Local.xcconfig.
nonisolated struct StravaOAuth: Sendable {
    var clientID: String
    /// Only for builds without a server; nil when `relay` is used.
    var clientSecret: String?
    /// Where Strava sends the athlete back. Its host must be the "Authorization Callback Domain" registered for the
    /// app on strava.com/settings/api.
    var redirectURI: String
    /// Adds the client secret on TrackStar's server; nil to send it from the app (forks).
    var relay: TrackStarServer? = nil
    /// Upload activities; read them to spot duplicates and name watch runs after the plan.
    static let scope = "activity:write,activity:read_all"

    /// From Info.plist (STRAVA_CLIENT_ID, STRAVA_CALLBACK_DOMAIN, and STRAVA_CLIENT_SECRET for builds without a
    /// server); nil when this build has no Strava app, which hides the option.
    static func configured(server: TrackStarServer?) -> StravaOAuth? {
        func value(_ key: String) -> String? {
            (Bundle.main.object(forInfoDictionaryKey: key) as? String)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 }
        }
        guard let id = value("StravaClientID"), let domain = value("StravaCallbackDomain"),
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let redirect = "\(bundleID.lowercased())://\(domain)/strava"
        if let server { return StravaOAuth(clientID: id, clientSecret: nil, redirectURI: redirect, relay: server) }
        guard let secret = value("StravaClientSecret") else { return nil }
        return StravaOAuth(clientID: id, clientSecret: secret, redirectURI: redirect)
    }

    var callbackScheme: String { String(redirectURI.prefix { $0 != ":" }) }

    struct Attempt: Sendable, Equatable {
        var state: String
        /// Opens the Strava app's own "Authorize" screen.
        var appURL: URL
        /// The same in a web sheet, for phones without the Strava app.
        var webURL: URL
    }

    func start() -> Attempt {
        let state = IntervalsOAuth.randomString(length: 24)
        func url(_ base: String) -> URL {
            var components = URLComponents(string: base)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "approval_prompt", value: "auto"),
                URLQueryItem(name: "scope", value: Self.scope),
                URLQueryItem(name: "state", value: state),
            ]
            return components.url!
        }
        return Attempt(state: state, appURL: url("strava://oauth/mobile/authorize"),
                       webURL: url("https://www.strava.com/oauth/mobile/authorize"))
    }

    /// Whether a URL opened in the app is Strava sending the athlete back.
    func isCallback(_ url: URL) -> Bool {
        url.absoluteString.lowercased().hasPrefix(redirectURI.lowercased())
    }

    /// The authorization code and what was allowed, after checking the redirect answers this attempt and upload
    /// was allowed (reading is optional: without it, watch runs simply aren't renamed).
    static func grant(from callback: URL, attempt: Attempt) throws -> (code: String, scope: String) {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == attempt.state, value("error") == nil, let code = value("code"), !code.isEmpty else {
            throw StravaError.signInFailed
        }
        // The athlete can untick permissions on Strava's screen; without upload there's no point connecting.
        let allowed = value("scope") ?? ""
        guard allowed.contains("activity:write") else { throw StravaError.unauthorized }
        return (code, allowed)
    }
}

/// Keeps the Strava connection in the Keychain (this device only).
nonisolated struct StravaKeychain: Sendable {
    var service = "io.github.nickcia.runcoach.strava"

    func load() -> StravaCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StravaCredentials.self, from: data)
    }

    func save(_ credentials: StravaCredentials) throws {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = try JSONEncoder().encode(credentials)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw StravaError.keychain(status) }
    }

    func delete() { SecItemDelete(baseQuery as CFDictionary) }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
    }
}

/// A run ready to send: a GPX track, or for a run with no GPS (location off), its time and distance.
nonisolated struct StravaUpload: Codable, Hashable, Sendable {
    var name: String
    var description: String
    /// Unique per run, so Strava refuses a second copy.
    var externalID: String
    var start: Date
    var elapsedSeconds: Double
    var meters: Double
    /// nil for runs without a route.
    var gpx: Data?
    /// For athletes with a watch: until when to wait for the watch's copy of this run to show up (Garmin syncs a few
    /// minutes after the run). If it does, this one isn't uploaded. nil to upload straight away.
    var checkWatchUntil: Date? = nil

    var interval: DateInterval { DateInterval(start: start, duration: max(0, elapsedSeconds)) }

    @MainActor init(recording: GuidedRunRecording, name: String, description: String) {
        self.name = name
        self.description = description
        externalID = "trackstar-\(Int(recording.start.timeIntervalSince1970))"
        start = recording.start
        elapsedSeconds = recording.end.timeIntervalSince(recording.start)
        meters = recording.meters
        gpx = recording.route.count >= 2 ? Self.gpx(route: recording.route, pauses: recording.pauses, name: name) : nil
    }

    /// GPX 1.1 with a timestamp on every point (Strava needs them). A new segment starts after each pause, so the
    /// paused stretch isn't counted as moving.
    static func gpx(route: [CLLocation], pauses: [DateInterval], name: String) -> Data {
        let time = ISO8601DateFormatter()
        time.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var segments: [[CLLocation]] = [[]]
        var pauseIndex = 0
        let sortedPauses = pauses.sorted { $0.start < $1.start }
        for point in route {
            // Passing the end of a pause starts a new segment.
            var crossed = false
            while pauseIndex < sortedPauses.count, point.timestamp >= sortedPauses[pauseIndex].end {
                pauseIndex += 1
                crossed = true
            }
            if crossed, !(segments.last?.isEmpty ?? true) { segments.append([]) }
            segments[segments.count - 1].append(point)
        }
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TrackStar" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata><time>\(time.string(from: route.first?.timestamp ?? .now))</time></metadata>
        <trk><name>\(escaped(name))</name><type>running</type>

        """
        for segment in segments where !segment.isEmpty {
            xml += "<trkseg>\n"
            for point in segment {
                let lat = String(format: "%.7f", point.coordinate.latitude)
                let lon = String(format: "%.7f", point.coordinate.longitude)
                xml += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\">"
                if point.verticalAccuracy > 0 { xml += "<ele>\(String(format: "%.1f", point.altitude))</ele>" }
                xml += "<time>\(time.string(from: point.timestamp))</time></trkpt>\n"
            }
            xml += "</trkseg>\n"
        }
        xml += "</trk>\n</gpx>\n"
        return Data(xml.utf8)
    }
}

/// Talks to the Strava API.
nonisolated struct StravaClient: Sendable {
    var baseURL = URL(string: "https://www.strava.com/")!
    var transport: any HTTPTransport = URLSessionTransport()

    private struct TokenResponse: Decodable {
        struct Athlete: Decodable { var id: Int; var firstname: String?; var lastname: String? }
        var access_token: String
        var refresh_token: String
        var expires_at: Double
        var athlete: Athlete?
    }

    /// Swaps the code from "Authorize" for tokens.
    func signIn(code: String, oauth: StravaOAuth) async throws -> StravaCredentials {
        let data = try await token(["grant_type": "authorization_code", "code": code], oauth: oauth)
        let reply = try JSONDecoder().decode(TokenResponse.self, from: data)
        let name = [reply.athlete?.firstname, reply.athlete?.lastname].compactMap { $0 }.joined(separator: " ")
        return StravaCredentials(accessToken: reply.access_token, refreshToken: reply.refresh_token,
                                 expiresAt: Date(timeIntervalSince1970: reply.expires_at),
                                 athleteID: reply.athlete?.id ?? 0, athleteName: name)
    }

    /// A fresh access token. Strava may also hand back a new refresh token; the old one then stops working.
    func refresh(_ credentials: StravaCredentials, oauth: StravaOAuth) async throws -> StravaCredentials {
        let data = try await token(["grant_type": "refresh_token", "refresh_token": credentials.refreshToken], oauth: oauth)
        let reply = try JSONDecoder().decode(TokenResponse.self, from: data)
        var updated = credentials
        updated.accessToken = reply.access_token
        updated.refreshToken = reply.refresh_token
        updated.expiresAt = Date(timeIntervalSince1970: reply.expires_at)
        return updated
    }

    /// Ends the connection on Strava's side too.
    func revoke(_ credentials: StravaCredentials, oauth: StravaOAuth) async {
        if let relay = oauth.relay {
            await relay.stravaRevoke(token: credentials.refreshToken)
            return
        }
        var request = URLRequest(url: baseURL.appending(path: "oauth/revoke"), timeoutInterval: 20)
        request.httpMethod = "POST"
        let basic = Data("\(oauth.clientID):\(oauth.clientSecret ?? "")".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["token": credentials.refreshToken])
        _ = try? await transport.send(request)
    }

    /// Sends a run and waits (briefly) for Strava to make it an activity. Returns the activity ID, or nil when Strava
    /// says it's a copy of one already there (which counts as done).
    func upload(_ upload: StravaUpload, credentials: StravaCredentials) async throws -> Int? {
        guard let gpx = upload.gpx else { return try await createManual(upload, credentials: credentials) }
        let boundary = "TrackStar-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("data_type", "gpx")
        field("sport_type", "Run")
        field("name", upload.name)
        field("description", upload.description)
        field("external_id", upload.externalID + ".gpx")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(upload.externalID).gpx\"\r\nContent-Type: application/gpx+xml\r\n\r\n".utf8))
        body.append(gpx)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appending(path: "api/v3/uploads"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var status = try decodeStatus(try await perform(request, credentials: credentials, body: body))
        // Strava usually finishes in a couple of seconds; check a few times, a second or two apart.
        for attempt in 0..<8 where status.activity_id == nil && status.error == nil {
            try? await Task.sleep(for: .seconds(attempt < 3 ? 1 : 2))
            let check = URLRequest(url: baseURL.appending(path: "api/v3/uploads/\(status.id_str ?? String(status.id ?? 0))"),
                                   timeoutInterval: 30)
            status = try decodeStatus(try await perform(check, credentials: credentials))
        }
        if let error = status.error {
            if error.localizedCaseInsensitiveContains("duplicate") { return nil }
            throw StravaError.rejected(Self.plainText(error))
        }
        guard let id = status.activity_id else { throw StravaError.server(202) }
        return id
    }

    /// The athlete's activities that started after `date`, newest first (up to 50).
    func activities(after date: Date, credentials: StravaCredentials) async throws -> [StravaActivity] {
        var url = baseURL.appending(path: "api/v3/athlete/activities")
        url.append(queryItems: [URLQueryItem(name: "after", value: String(Int(date.timeIntervalSince1970))),
                                URLQueryItem(name: "per_page", value: "50")])
        let data = try await perform(URLRequest(url: url, timeoutInterval: 30), credentials: credentials)
        return (try? JSONDecoder().decode([StravaActivity].self, from: data)) ?? []
    }

    /// One activity with its description (the list leaves descriptions out).
    func activity(_ id: Int, credentials: StravaCredentials) async throws -> StravaActivity {
        let data = try await perform(URLRequest(url: baseURL.appending(path: "api/v3/activities/\(id)"), timeoutInterval: 30),
                                     credentials: credentials)
        do { return try JSONDecoder().decode(StravaActivity.self, from: data) } catch { throw StravaError.server(200) }
    }

    /// Changes an activity's name and/or description.
    func update(_ id: Int, name: String?, description: String?, credentials: StravaCredentials) async throws {
        var fields: [String: String] = [:]
        if let name { fields["name"] = name }
        if let description { fields["description"] = description }
        guard !fields.isEmpty else { return }
        var request = URLRequest(url: baseURL.appending(path: "api/v3/activities/\(id)"), timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request, credentials: credentials, body: Self.form(fields))
    }

    /// A run with no route (location was off): time and distance only.
    private func createManual(_ upload: StravaUpload, credentials: StravaCredentials) async throws -> Int? {
        let local = ISO8601DateFormatter()
        local.timeZone = .current
        local.formatOptions = [.withFullDate, .withFullTime, .withColonSeparatorInTime]
        var fields = ["name": upload.name, "sport_type": "Run", "description": upload.description,
                      "start_date_local": String(local.string(from: upload.start).prefix(19)),
                      "elapsed_time": String(Int(upload.elapsedSeconds.rounded()))]
        if upload.meters > 0 { fields["distance"] = String(format: "%.1f", upload.meters) }
        var request = URLRequest(url: baseURL.appending(path: "api/v3/activities"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let data = try await perform(request, credentials: credentials, body: Self.form(fields))
        struct Created: Decodable { var id: Int }
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    private struct UploadStatus: Decodable {
        var id: Int?
        var id_str: String?
        var error: String?
        var status: String?
        var activity_id: Int?
    }

    private func decodeStatus(_ data: Data) throws -> UploadStatus {
        do { return try JSONDecoder().decode(UploadStatus.self, from: data) } catch { throw StravaError.server(200) }
    }

    private func token(_ fields: [String: String], oauth: StravaOAuth) async throws -> Data {
        if let relay = oauth.relay {
            let data: Data
            let status: Int
            do {
                (data, status) = try await relay.stravaToken(fields)
            } catch {
                throw StravaError.offline
            }
            switch status {
            case 200..<300: return data
            case 429: throw StravaError.server(429)
            case 400..<500: throw StravaError.signInFailed
            default: throw StravaError.server(status)
            }
        }
        var request = URLRequest(url: baseURL.appending(path: "api/v3/oauth/token"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields.merging(["client_id": oauth.clientID, "client_secret": oauth.clientSecret ?? ""]) { a, _ in a })
        return try await perform(request, failure: .signInFailed)
    }

    private func perform(_ request: URLRequest, credentials: StravaCredentials, body: Data? = nil) async throws -> Data {
        var request = request
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body }
        return try await perform(request, failure: .unauthorized)
    }

    private func perform(_ request: URLRequest, failure: StravaError) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw StravaError.offline
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw failure
        // Strava's rate limit (per app, shared by every TrackStar user): wait and try again later.
        case 429: throw StravaError.server(429)
        case 400..<500: throw failure == .signInFailed ? failure : StravaError.rejected(Self.message(in: data))
        default: throw StravaError.server(response.statusCode)
        }
    }

    /// Strava's error replies carry a message; fall back to a generic one.
    private static func message(in data: Data) -> String {
        struct Fault: Decodable { var message: String? }
        return (try? JSONDecoder().decode(Fault.self, from: data))?.message ?? String(localized: "it wasn't accepted")
    }

    /// Upload errors may contain HTML.
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
}

/// Runs waiting to go to Strava (no connection when they finished). Kept as files in Application Support, so they
/// survive the app closing, and sent the next time the app opens.
nonisolated struct StravaQueue: Sendable {
    var directory: URL = URL.applicationSupportDirectory.appending(path: "strava-queue", directoryHint: .isDirectory)

    func add(_ upload: StravaUpload) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(upload).write(to: file(upload), options: .atomic)
    }

    func remove(_ upload: StravaUpload) { try? FileManager.default.removeItem(at: file(upload)) }

    var pending: [StravaUpload] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? JSONDecoder().decode(StravaUpload.self, from: Data(contentsOf: $0)) }
            .sorted { $0.start < $1.start }
    }

    func clear() { try? FileManager.default.removeItem(at: directory) }

    private func file(_ upload: StravaUpload) -> URL { directory.appending(path: upload.externalID + ".json") }
}

/// An activity on the athlete's Strava account (only what TrackStar needs).
nonisolated struct StravaActivity: Decodable, Hashable, Sendable {
    var id: Int
    var name: String
    var description: String?
    var sport_type: String?
    var start_date: String
    var elapsed_time: Double?
    var distance: Double?
    var external_id: String?

    var isRun: Bool { ["Run", "TrailRun", "VirtualRun"].contains(sport_type ?? "") }
    /// Uploaded by TrackStar (from a phone run), so it already has the plan's name.
    var isFromTrackStar: Bool { external_id?.hasPrefix("trackstar-") ?? false }

    var start: Date? { ISO8601DateFormatter().date(from: start_date) }
    var interval: DateInterval? { start.map { DateInterval(start: $0, duration: max(0, elapsed_time ?? 0)) } }

    /// Still has the name Strava, Garmin or Apple gave it ("Morning Run", "Toronto Running"), or the planned workout's
    /// name as the watch sent it: safe to replace with the plan's name. Anything else, the athlete named it themselves.
    func hasDefaultName(plannedName: String) -> Bool {
        let name = self.name.trimmingCharacters(in: .whitespaces)
        if name.range(of: #"^(Morning|Lunch|Afternoon|Evening|Night) (Trail )?Run$"#, options: .regularExpression) != nil { return true }
        // Garmin: "Toronto Running", "Running".
        if name == "Run" || name == "Running" || name.hasSuffix(" Running") { return true }
        return !plannedName.isEmpty && name.localizedCaseInsensitiveContains(plannedName)
    }
}

extension DateInterval {
    /// Overlap of more than a minute, so back-to-back runs don't count.
    func overlapsMeaningfully(_ other: DateInterval) -> Bool {
        (intersection(with: other)?.duration ?? 0) > 60
    }
}

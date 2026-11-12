import Foundation
import Security

// TrackStar's small server (Cloudflare Workers). Only two things need it: Garmin Connect, which only lets apps
// connect through a server, and the Strava sign-in, whose client secret mustn't ship in the app. There are no
// accounts: the first time it's needed, this iPhone registers and gets a random ID and key, kept in its Keychain.
// The server's address comes from Config/App.xcconfig (TRACKSTAR_SERVER); builds without one hide Garmin.

/// This iPhone's identity on the server.
nonisolated struct ServerDevice: Codable, Hashable, Sendable {
    var id: String
    var secret: String

    var authorization: String { "Device \(id).\(secret)" }
}

/// Keeps the device's ID and key in the Keychain (this device only, not synced or backed up to other devices).
nonisolated struct ServerDeviceKeychain: Sendable {
    var service = "io.github.nickcia.runcoach.server"

    func load() -> ServerDevice? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ServerDevice.self, from: data)
    }

    func save(_ device: ServerDevice) throws {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = try JSONEncoder().encode(device)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ServerError.keychain(status) }
    }

    func delete() { SecItemDelete(baseQuery as CFDictionary) }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
    }
}

nonisolated enum ServerError: LocalizedError, Equatable {
    case offline
    case server(Int)
    /// Garmin isn't connected for this iPhone (any more).
    case notConnected
    /// The daily allowance for this iPhone is used up.
    case limit
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .offline: String(localized: "Couldn't reach TrackStar's server. Check your connection; it'll try again next time you open the app.")
        case .server(let code): String(localized: "TrackStar's server couldn't do that right now (error \(code)). It'll try again later.")
        case .notConnected: String(localized: "Garmin Connect isn't connected any more. Connect again in Settings.")
        case .limit: String(localized: "That's enough syncing for today. It'll carry on tomorrow.")
        case .keychain: String(localized: "Couldn't save this iPhone's connection to TrackStar's server.")
        }
    }

    var isTemporary: Bool {
        switch self {
        case .offline, .server, .limit: true
        default: false
        }
    }
}

/// How Garmin Connect is linked, as the server sees it.
nonisolated struct GarminStatus: Decodable, Hashable, Sendable {
    var connected: Bool
    /// Garmin stopped accepting the connection (e.g. the password changed): connect again.
    var needsReconnect: Bool? = nil
    /// The athlete allowed workouts to be sent (Garmin Connect lets them untick it).
    var sendsWorkouts: Bool? = nil
    /// The athlete allowed their activities to be shared.
    var sharesRuns: Bool? = nil
}

/// What a workout sync did.
nonisolated struct GarminSyncResult: Decodable, Hashable, Sendable {
    var added: Int
    var removed: Int
    /// Changes left for tomorrow (Garmin's daily allowance).
    var waiting: Int
    /// "permission" when the athlete hasn't allowed workouts in Garmin Connect.
    var error: String? = nil
}

/// A run Garmin sent, waiting on the server for this iPhone to collect it.
nonisolated struct GarminInboxItem: Decodable, Sendable {
    var id: String
    var run: GarminRun
}

/// Talks to TrackStar's server. An actor, so this iPhone only ever registers once.
actor TrackStarServer {
    let baseURL: URL
    private let transport: any HTTPTransport
    private let keychain: ServerDeviceKeychain
    private var device: ServerDevice?

    init(baseURL: URL, transport: any HTTPTransport = URLSessionTransport(), keychain: ServerDeviceKeychain = ServerDeviceKeychain()) {
        self.baseURL = baseURL
        self.transport = transport
        self.keychain = keychain
    }

    /// From Info.plist (TRACKSTAR_SERVER); nil in builds without a server.
    nonisolated static var configured: TrackStarServer? {
        guard let text = (Bundle.main.object(forInfoDictionaryKey: "TrackStarServer") as? String)?
                .trimmingCharacters(in: .whitespaces),
              text.hasPrefix("https://"), let url = URL(string: text) else { return nil }
        return TrackStarServer(baseURL: url)
    }

    // MARK: Garmin Connect

    /// The Garmin page to open for "Connect with Garmin Connect".
    func garminSignInURL() async throws -> URL {
        struct Reply: Decodable { var url: URL }
        return try JSONDecoder().decode(Reply.self, from: try await send("v1/garmin/start", method: "POST")).url
    }

    func garminStatus() async throws -> GarminStatus {
        try JSONDecoder().decode(GarminStatus.self, from: try await send("v1/garmin", method: "GET"))
    }

    /// Takes TrackStar's workouts off the Garmin calendar, ends the connection at Garmin and deletes it on the server.
    func disconnectGarmin() async throws {
        _ = try await send("v1/garmin", method: "DELETE")
    }

    /// Makes the Garmin Connect calendar match these workouts (the server keeps the next two weeks).
    func syncGarminWorkouts(_ workouts: [GarminPlanWorkout]) async throws -> GarminSyncResult {
        let body = try JSONEncoder().encode(["workouts": workouts])
        return try JSONDecoder().decode(GarminSyncResult.self, from: try await send("v1/garmin/workouts", method: "PUT", body: body))
    }

    /// Runs waiting for this iPhone (up to 20 at a time).
    func garminRuns() async throws -> [GarminInboxItem] {
        struct Reply: Decodable { var runs: [GarminInboxItem] }
        return try JSONDecoder().decode(Reply.self, from: try await send("v1/garmin/runs", method: "GET")).runs
    }

    /// This iPhone has these runs: the server deletes its copies.
    func acknowledgeGarminRuns(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await send("v1/garmin/runs/received", method: "POST", body: try JSONEncoder().encode(["ids": ids]))
    }

    // MARK: Strava sign-in

    /// Passes a Strava token request through the server, which adds the client secret. Returns Strava's reply as is.
    func stravaToken(_ fields: [String: String]) async throws -> (Data, Int) {
        let (data, response) = try await raw("v1/strava/token", method: "POST", body: try JSONEncoder().encode(fields))
        return (data, response.statusCode)
    }

    func stravaRevoke(token: String) async {
        _ = try? await raw("v1/strava/revoke", method: "POST", body: try? JSONEncoder().encode(["token": token]))
    }

    // MARK: HTTP

    private func send(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        let (data, response) = try await raw(path, method: method, body: body)
        switch response.statusCode {
        case 200..<300: return data
        case 409: throw ServerError.notConnected
        case 429: throw ServerError.limit
        default: throw ServerError.server(response.statusCode)
        }
    }

    /// Sends as this device. If the server doesn't know the device (its records were reset), registers again once.
    private func raw(_ path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var result = try await attempt(path, method: method, body: body, device: try await registered())
        if result.1.statusCode == 401 {
            device = nil
            keychain.delete()
            result = try await attempt(path, method: method, body: body, device: try await registered())
        }
        return result
    }

    private func attempt(_ path: String, method: String, body: Data?, device: ServerDevice) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(device.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            return try await transport.send(request)
        } catch {
            throw ServerError.offline
        }
    }

    /// This iPhone's ID and key, registering the first time.
    private func registered() async throws -> ServerDevice {
        if let device { return device }
        if let stored = keychain.load() {
            device = stored
            return stored
        }
        var request = URLRequest(url: baseURL.appending(path: "v1/devices"), timeoutInterval: 30)
        request.httpMethod = "POST"
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) } catch { throw ServerError.offline }
        guard response.statusCode == 201 || response.statusCode == 200 else { throw ServerError.server(response.statusCode) }
        let new = try JSONDecoder().decode(ServerDevice.self, from: data)
        try keychain.save(new)
        device = new
        return new
    }
}

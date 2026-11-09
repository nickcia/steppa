import CoreLocation
import Foundation
import Testing
import PlanEngine
@testable import TrackStar

/// A pretend Strava: swaps codes for tokens and turns uploads into activities.
nonisolated final class FakeStrava: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []
    private var _bodies: [String] = []
    private var _externalIDs: Set<String> = []
    private var _offline = false
    private var _busy = false
    private var _accessToken = "token-1"
    private var nextActivity = 500

    var requests: [String] { lock.withLock { _requests } }
    var bodies: [String] { lock.withLock { _bodies } }
    func setOffline(_ offline: Bool) { lock.withLock { _offline = offline } }
    /// Answers uploads with Strava's rate-limit reply.
    func setBusy(_ busy: Bool) { lock.withLock { _busy = busy } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try lock.withLock { try handle(request) }
    }

    private func handle(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        if _offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        _requests.append("\(method) \(url.path)")
        _bodies.append(body)

        if url.path == "/api/v3/oauth/token" {
            let form = URLComponents(string: "?" + body)?.queryItems ?? []
            func field(_ name: String) -> String? { form.first { $0.name == name }?.value }
            guard field("client_id") == "42", field("client_secret") == "shh" else { return reply(401, "{}") }
            switch field("grant_type") {
            case "authorization_code" where field("code") == "good-code":
                return reply(200, #"{"access_token":"token-1","refresh_token":"refresh-1","expires_at":\#(Int(Date.now.timeIntervalSince1970) + 21600),"athlete":{"id":7,"firstname":"Test","lastname":"Runner"}}"#)
            case "refresh_token" where field("refresh_token") == "refresh-1":
                _accessToken = "token-2"
                return reply(200, #"{"access_token":"token-2","refresh_token":"refresh-2","expires_at":\#(Int(Date.now.timeIntervalSince1970) + 21600)}"#)
            default:
                return reply(400, #"{"message":"Bad Request"}"#)
            }
        }
        if url.path == "/oauth/revoke" { return reply(200, "") }

        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(_accessToken)" else { return reply(401, "{}") }
        switch (method, url.path) {
        case ("POST", "/api/v3/uploads"):
            if _busy { return reply(429, #"{"message":"Rate Limit Exceeded"}"#) }
            guard body.contains("name=\"data_type\"\r\n\r\ngpx"), body.contains("name=\"sport_type\"\r\n\r\nRun"),
                  body.contains("<trkpt"), let external = body.firstMatch(of: /name="external_id"\r\n\r\n([^\r]+)/)?.1 else {
                return reply(400, #"{"message":"Bad Request"}"#)
            }
            if !_externalIDs.insert(String(external)).inserted {
                return reply(201, #"{"id":1,"id_str":"1","error":"run.gpx duplicate of <a href='/activities/500'>activity 500</a>","status":"There was an error processing your activity.","activity_id":null}"#)
            }
            return reply(201, #"{"id":2,"id_str":"2","error":null,"status":"Your activity is still being processed.","activity_id":null}"#)
        case ("GET", "/api/v3/uploads/2"):
            nextActivity += 1
            return reply(200, #"{"id":2,"id_str":"2","error":null,"status":"Your activity is ready.","activity_id":\#(nextActivity)}"#)
        case ("POST", "/api/v3/activities"):
            return reply(201, #"{"id":900}"#)
        default:
            return reply(404, "{}")
        }
    }

    private func reply(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://www.strava.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
struct StravaTests {
    let oauth = StravaOAuth(clientID: "42", clientSecret: "shh", redirectURI: "io.github.nickcia.runcoach://nickcia.github.io/strava")

    func makeModel(_ fake: FakeStrava) throws -> AppModel {
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { AppModelTests.start.adding(days: 3) },
                             strava: StravaClient(transport: fake), stravaOAuth: oauth,
                             stravaKeychain: StravaKeychain(service: "trackstar-tests-\(UUID().uuidString)"),
                             stravaQueue: StravaQueue(directory: URL.temporaryDirectory.appending(path: "strava-\(UUID().uuidString)")))
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(AppModelTests.inputs()))
        return model
    }

    func connect(_ model: AppModel) async throws {
        let attempt = oauth.start()
        let callback = URL(string: "\(oauth.redirectURI)?state=\(attempt.state)&code=good-code&scope=read,activity:write")!
        try await model.finishStravaSignIn(callback: callback, attempt: attempt)
    }

    /// Ten minutes due north at about 3 m/s, with a minute's pause in the middle.
    func recording(route: Bool = true) -> GuidedRunRecording {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let points = (0..<600).filter { !(300..<360).contains($0) }.map { i in
            CLLocation(coordinate: .init(latitude: 51.5 + Double(i) * 3 / 111_320, longitude: -0.12), altitude: 20,
                       horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 3, timestamp: start.addingTimeInterval(Double(i)))
        }
        return GuidedRunRecording(workoutID: "w", start: start, end: start.addingTimeInterval(600),
                                  pauses: [DateInterval(start: start.addingTimeInterval(300), duration: 60)],
                                  meters: 1620, segments: [], route: route ? points : [])
    }

    @Test func signInURLsAskOnlyToUpload() {
        let attempt = oauth.start()
        for url in [attempt.appURL, attempt.webURL] {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(items.contains(URLQueryItem(name: "scope", value: "activity:write")))
            #expect(items.contains(URLQueryItem(name: "response_type", value: "code")))
            #expect(items.contains(URLQueryItem(name: "redirect_uri", value: oauth.redirectURI)))
        }
        #expect(attempt.appURL.scheme == "strava")
        #expect(oauth.isCallback(URL(string: "io.github.nickcia.runcoach://nickcia.github.io/strava?code=x")!))
        #expect(!oauth.isCallback(URL(string: "io.github.nickcia.runcoach://intervals-oauth?code=x")!))
    }

    @Test func callbackMustMatchAndAllowUploads() {
        let attempt = oauth.start()
        let base = oauth.redirectURI
        #expect(throws: StravaError.signInFailed) {
            try StravaOAuth.code(from: URL(string: "\(base)?state=wrong&code=c&scope=activity:write")!, attempt: attempt)
        }
        #expect(throws: StravaError.signInFailed) {
            try StravaOAuth.code(from: URL(string: "\(base)?state=\(attempt.state)&error=access_denied")!, attempt: attempt)
        }
        // Upload permission unticked on Strava's screen.
        #expect(throws: StravaError.unauthorized) {
            try StravaOAuth.code(from: URL(string: "\(base)?state=\(attempt.state)&code=c&scope=read")!, attempt: attempt)
        }
    }

    @Test func connectsAndUploadsARunWithItsRoute() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake)
        try await connect(model)
        #expect(model.stravaAccount?.athleteName == "Test Runner")
        let workout = try #require(model.plan?.workouts.first)
        let outcome = await model.uploadToStrava(recording(), workout: workout)
        #expect(outcome == .uploaded(501))
        let upload = try #require(fake.bodies.first { $0.contains("<gpx") })
        #expect(upload.contains("name=\"name\"\r\n\r\n\(workout.name)"))
        // Uploading the same run again is recognised as already there.
        #expect(await model.uploadToStrava(recording(), workout: workout) == .uploaded(nil))
    }

    @Test func expiredTokensAreRefreshedFirst() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake)
        try await connect(model)
        var stale = try #require(model.stravaAccount)
        stale.expiresAt = .now.addingTimeInterval(-60)
        model.debugSetStravaAccount(stale)
        let outcome = await model.uploadToStrava(recording(), workout: try #require(model.plan?.workouts.first))
        #expect(outcome == .uploaded(501))
        #expect(model.stravaAccount?.refreshToken == "refresh-2")
    }

    @Test func offlineRunsWaitAndGoLater() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake)
        try await connect(model)
        fake.setOffline(true)
        let workout = try #require(model.plan?.workouts.first)
        #expect(await model.uploadToStrava(recording(), workout: workout) == .queued)
        #expect(model.stravaQueuedCount == 1)
        fake.setOffline(false)
        await model.sendQueuedStravaUploads()
        #expect(model.stravaQueuedCount == 0)
        #expect(fake.requests.contains("GET /api/v3/uploads/2"))
    }

    @Test func rateLimitedRunsWaitInsteadOfBeingDropped() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake)
        try await connect(model)
        fake.setBusy(true)
        let workout = try #require(model.plan?.workouts.first)
        #expect(await model.uploadToStrava(recording(), workout: workout) == .queued)
        #expect(model.stravaQueuedCount == 1)
        fake.setBusy(false)
        await model.sendQueuedStravaUploads()
        #expect(model.stravaQueuedCount == 0)
    }

    @Test func runsWithoutGPSBecomeManualActivities() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake)
        try await connect(model)
        let outcome = await model.uploadToStrava(recording(route: false), workout: try #require(model.plan?.workouts.first))
        #expect(outcome == .uploaded(900))
        let body = try #require(fake.bodies.last)
        #expect(body.contains("elapsed_time=600") && body.contains("distance=1620.0") && body.contains("sport_type=Run"))
    }

    @Test func disconnectingForgetsEverything() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake)
        try await connect(model)
        fake.setOffline(true)
        _ = await model.uploadToStrava(recording(), workout: try #require(model.plan?.workouts.first))
        fake.setOffline(false)
        await model.disconnectStrava()
        #expect(model.stravaAccount == nil)
        #expect(model.stravaQueuedCount == 0)
        #expect(fake.requests.contains("POST /oauth/revoke"))
    }

    @Test func gpxHasTimesAndBreaksAtPauses() throws {
        let upload = StravaUpload(recording: recording(), name: "Easy & steady", description: "")
        let gpx = String(decoding: try #require(upload.gpx), as: UTF8.self)
        #expect(gpx.components(separatedBy: "<trkseg>").count - 1 == 2)
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 540)
        #expect(gpx.components(separatedBy: "<time>").count - 1 == 541)  // every point, plus the metadata
        #expect(gpx.contains("Easy &amp; steady"))
        #expect(upload.externalID == "trackstar-1800000000")
    }
}

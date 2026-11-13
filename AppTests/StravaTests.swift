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
    /// Activities already on the account (as Strava lists them).
    private var _activities: [[String: Any]] = []
    private var _updates: [(id: String, body: String)] = []

    func addActivity(id: Int, name: String, start: Date, seconds: Double, meters: Double, description: String? = nil,
                     externalID: String? = nil) {
        lock.withLock {
            var activity: [String: Any] = ["id": id, "name": name, "sport_type": "Run", "elapsed_time": seconds, "distance": meters,
                                           "start_date": ISO8601DateFormatter().string(from: start)]
            activity["description"] = description
            activity["external_id"] = externalID
            _activities.append(activity)
        }
    }
    var updates: [(id: String, body: String)] { lock.withLock { _updates } }

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
        case ("GET", "/api/v3/athlete/activities"):
            let list = _activities.map { $0.filter { $0.key != "description" } }
            return reply(200, String(decoding: try JSONSerialization.data(withJSONObject: list), as: UTF8.self))
        case ("GET", let path) where path.hasPrefix("/api/v3/activities/"):
            guard let found = _activities.first(where: { "\($0["id"]!)" == url.lastPathComponent }) else { return reply(404, "{}") }
            return reply(200, String(decoding: try JSONSerialization.data(withJSONObject: found), as: UTF8.self))
        case ("PUT", let path) where path.hasPrefix("/api/v3/activities/"):
            _updates.append((url.lastPathComponent, body))
            return reply(200, "{}")
        default:
            return reply(404, "{}")
        }
    }

    private func reply(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://www.strava.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

// Serialized: these tests share the "already named" list in UserDefaults.
@MainActor @Suite(.serialized)
struct StravaTests {
    let oauth = StravaOAuth(clientID: "42", clientSecret: "shh", redirectURI: "io.github.nickcia.runcoach://nickcia.github.io/strava")

    func makeModel(_ fake: FakeStrava, health: FakeRunSource? = nil) throws -> AppModel {
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { AppModelTests.start.adding(days: 3) },
                             runSource: health,
                             strava: StravaClient(transport: fake), stravaOAuth: oauth,
                             stravaKeychain: StravaKeychain(service: "trackstar-tests-\(UUID().uuidString)"),
                             stravaQueue: StravaQueue(directory: URL.temporaryDirectory.appending(path: "strava-\(UUID().uuidString)")))
        // Whether this simulator "has" an Apple Watch is remembered between runs; tests decide it themselves.
        model.appleWatchPaired = false
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(AppModelTests.inputs()))
        return model
    }

    /// `reading`: also allowed to read activities (as asked for now); without it, as connections made before.
    func connect(_ model: AppModel, reading: Bool = false) async throws {
        let attempt = oauth.start()
        let scope = reading ? "read,activity:write,activity:read_all" : "read,activity:write"
        let callback = URL(string: "\(oauth.redirectURI)?state=\(attempt.state)&code=good-code&scope=\(scope)")!
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

    @Test func signInURLsAskToUploadAndRead() {
        let attempt = oauth.start()
        for url in [attempt.appURL, attempt.webURL] {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(items.contains(URLQueryItem(name: "scope", value: "activity:write,activity:read_all")))
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
            try StravaOAuth.grant(from: URL(string: "\(base)?state=wrong&code=c&scope=activity:write")!, attempt: attempt)
        }
        #expect(throws: StravaError.signInFailed) {
            try StravaOAuth.grant(from: URL(string: "\(base)?state=\(attempt.state)&error=access_denied")!, attempt: attempt)
        }
        // Upload permission unticked on Strava's screen.
        #expect(throws: StravaError.unauthorized) {
            try StravaOAuth.grant(from: URL(string: "\(base)?state=\(attempt.state)&code=c&scope=read")!, attempt: attempt)
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
        #expect(upload.contains("name=\"name\"\r\n\r\nWeek 1 - \(workout.name)"))
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

    // MARK: Titles

    @Test func titlesAndDescriptionsComeFromThePlan() throws {
        let model = try makeModel(FakeStrava())
        let plan = try #require(model.plan)
        let easy = try #require(plan.weeks[1].workouts.first { $0.kind == .easy })
        #expect(model.stravaTitle(for: easy) == "Week 2 - \(easy.name) \(model.format.distance(easy.totalMeters))")
        // Easy runs that finish with strides say so.
        let withStrides = try #require(plan.workouts.first { $0.kind == .easy && $0.hasStrides })
        #expect(withStrides.name == "Easy run with strides")
        let plain = try #require(plan.workouts.first { $0.kind == .easy && !$0.hasStrides })
        #expect(plain.name == "Easy run")
        let tempo = try #require(plan.workouts.first { $0.kind == .tempo })
        let description = model.stravaDescription(for: tempo)
        #expect(description.hasPrefix("Week "))
        #expect(description.contains(" of \(plan.weeks.count) · "))
        #expect(description.contains(plan.inputs.goal.name))
        #expect(description.contains("Warm up"))
        #expect(description.contains("/km"))
        #expect(description.hasSuffix("Planned with TrackStar"))
        let custom = try #require(model.addWorkout(WorkoutTemplate(name: "Hill blast", blocks: [.preset(.tempo)]),
                                                   on: model.today.adding(days: 1)))
        #expect(model.stravaTitle(for: custom).hasSuffix(" - Hill blast"))
    }

    @Test func phoneUploadsUseThePlansTitle() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake)
        try await connect(model)
        let workout = try #require(model.plan?.workouts.first)
        _ = await model.uploadToStrava(recording(), workout: workout)
        let upload = try #require(fake.bodies.first { $0.contains("<gpx") })
        #expect(upload.contains("name=\"name\"\r\n\r\nWeek 1 - \(workout.name)"))
    }

    // MARK: Duplicates

    @Test func aRunTheWatchAlreadySentToStravaIsntUploadedAgain() async throws {
        let fake = FakeStrava()
        let run = recording()
        fake.addActivity(id: 77, name: "Morning Run", start: run.start.addingTimeInterval(20), seconds: 620, meters: 1700)
        let model = try makeModel(fake)
        try await connect(model, reading: true)
        #expect(await model.uploadToStrava(run, workout: try #require(model.plan?.workouts.first)) == .fromWatch)
        #expect(!fake.requests.contains("POST /api/v3/uploads"))
    }

    @Test func aRunTheWatchRecordedInHealthIsntUploadedEither() async throws {
        let fake = FakeStrava()
        let run = recording()
        let health = FakeRunSource(runs: [])
        health.otherRunIntervals = [DateInterval(start: run.start.addingTimeInterval(5), duration: 600)]
        let model = try makeModel(fake, health: health)
        try await connect(model)
        #expect(await model.uploadToStrava(run, workout: try #require(model.plan?.workouts.first)) == .fromWatch)
        #expect(!fake.requests.contains("POST /api/v3/uploads"))
    }

    @Test func withAWatchThePhoneWaitsForItsCopyThenUploads() async throws {
        let fake = FakeStrava()
        let run = recording()
        let health = FakeRunSource(runs: [])
        // Runs with a watch now and then, but didn't record this one.
        health.otherRunIntervals = [DateInterval(start: run.start.addingTimeInterval(-5 * 86_400), duration: 1800)]
        let model = try makeModel(fake, health: health)
        try await connect(model)
        let workout = try #require(model.plan?.workouts.first)
        #expect(await model.uploadToStrava(run, workout: workout) == .waitingForWatch)
        #expect(model.stravaQueuedCount == 1)
        #expect(!fake.requests.contains("POST /api/v3/uploads"))
        // Still nothing from the watch once the wait is over: the phone's copy goes.
        // (The test run is dated in the future, so "the wait is over" means a deadline well before now.)
        model.stravaWatchWait = -run.end.timeIntervalSinceNow - 3600
        _ = await model.uploadToStrava(run, workout: workout)
        await model.sendQueuedStravaUploads()
        #expect(fake.requests.contains("POST /api/v3/uploads"))
        #expect(model.stravaQueuedCount == 0)
    }

    @Test func aPairedAppleWatchMeansWaitingForItsCopy() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake, health: FakeRunSource(runs: []))
        model.appleWatchPaired = true
        defer { model.appleWatchPaired = false }
        try await connect(model)
        #expect(await model.uploadToStrava(recording(), workout: try #require(model.plan?.workouts.first)) == .waitingForWatch)
        #expect(!fake.requests.contains("POST /api/v3/uploads"))
    }

    @Test func withoutAWatchThereIsNoWait() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake, health: FakeRunSource(runs: []))
        try await connect(model)
        #expect(await model.uploadToStrava(recording(), workout: try #require(model.plan?.workouts.first)) == .uploaded(501))
    }

    // MARK: Naming watch runs

    func modelWithWatchRun(_ fake: FakeStrava) async throws -> (AppModel, Workout) {
        let probe = try makeModel(fake)
        let workout = try #require(probe.plan?.workouts.last { $0.date < probe.today && $0.date >= probe.today.adding(days: -3) })
        let health = FakeRunSource(runs: [HealthIntegrationTests.run(for: workout, id: "hk-\(UUID().uuidString)")])
        let model = try makeModel(fake, health: health)
        await model.connectHealth()
        return (model, workout)
    }

    func noon(_ date: LocalDate) -> Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date.date())! }

    @Test func watchRunsGetThePlansNameAndSteps() async throws {
        let fake = FakeStrava()
        let (model, workout) = try await modelWithWatchRun(fake)
        fake.addActivity(id: 31, name: "Morning Run", start: noon(workout.date), seconds: workout.totalSeconds,
                         meters: workout.totalMeters * 1.03)
        try await connect(model, reading: true)
        let update = try #require(fake.updates.first)
        #expect(update.id == "31")
        let form = URLComponents(string: "?" + update.body)!.queryItems!
        #expect(form.first { $0.name == "name" }?.value == model.stravaTitle(for: workout))
        #expect(form.first { $0.name == "description" }?.value?.contains("Planned with TrackStar") == true)
        // Only once.
        await model.nameWatchRunsOnStrava()
        #expect(fake.updates.count == 1)
    }

    @Test func namesTheAthleteChoseAreKept() async throws {
        let fake = FakeStrava()
        let (model, workout) = try await modelWithWatchRun(fake)
        fake.addActivity(id: 32, name: "Hills with Sam", start: noon(workout.date), seconds: workout.totalSeconds,
                         meters: workout.totalMeters, description: "Legs were heavy")
        try await connect(model, reading: true)
        #expect(fake.updates.isEmpty)
    }

    @Test func nothingIsRenamedWithoutReadPermissionOrWhenTurnedOff() async throws {
        let fake = FakeStrava()
        let (model, workout) = try await modelWithWatchRun(fake)
        fake.addActivity(id: 33, name: "Morning Run", start: noon(workout.date), seconds: workout.totalSeconds, meters: workout.totalMeters)
        try await connect(model)
        await model.nameWatchRunsOnStrava()
        #expect(fake.updates.isEmpty)
        #expect(!fake.requests.contains("GET /api/v3/athlete/activities"))
    }

    @Test func defaultNamesAreRecognised() {
        func activity(_ name: String) -> StravaActivity {
            StravaActivity(id: 1, name: name, start_date: "2026-11-09T07:00:00Z")
        }
        for name in ["Morning Run", "Evening Trail Run", "Toronto Running", "Running", "Threshold · 2 × 1600 m threshold"] {
            #expect(activity(name).hasDefaultName(plannedName: "Threshold"), "\(name)")
        }
        for name in ["Tempo Run", "Hills with Sam", "Parkrun PB!"] {
            #expect(!activity(name).hasDefaultName(plannedName: "Threshold"), "\(name)")
        }
    }

    @Test func matchingNeedsTheSameDayAndASimilarDistance() {
        let run = CompletedRun(id: "r", date: LocalDate(year: 2026, month: 11, day: 9), distanceMeters: 8000, durationSeconds: 2700)
        func activity(_ id: Int, _ meters: Double, day: Int = 9) -> StravaActivity {
            StravaActivity(id: id, name: "Run", start_date: "2026-11-\(String(format: "%02d", day))T12:00:00Z", distance: meters)
        }
        #expect(AppModel.stravaActivity(for: run, in: [activity(1, 8300), activity(2, 5000)])?.id == 1)
        #expect(AppModel.stravaActivity(for: run, in: [activity(1, 8000, day: 10)]) == nil)
        // Two that fit about as well: don't guess.
        #expect(AppModel.stravaActivity(for: run, in: [activity(1, 8100), activity(2, 7950)]) == nil)
    }

    @Test func markingAWorkoutDoneNeverTouchesStrava() async throws {
        let fake = FakeStrava()
        let model = try makeModel(fake, health: FakeRunSource(runs: []))
        try await connect(model, reading: true)
        // A planned workout ticked off by hand, with a default-named run on Strava that day that it must not claim.
        let workout = try #require(model.plan?.workouts.last { $0.date < model.today })
        fake.addActivity(id: 40, name: "Morning Run", start: noon(workout.date), seconds: workout.totalSeconds,
                         meters: workout.totalMeters)
        let before = fake.requests.count
        model.setStatus(.done, for: workout)
        await model.nameWatchRunsOnStrava()
        await model.sendQueuedStravaUploads()
        #expect(fake.requests.count == before)
        #expect(fake.updates.isEmpty)
        #expect(model.stravaQueuedCount == 0)
    }
}

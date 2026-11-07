import Foundation
import Testing
import PlanEngine
@testable import Steppa

/// A pretend Intervals.icu: keeps a calendar and athlete settings in memory and answers the app's requests.
nonisolated final class FakeIntervals: HTTPTransport, @unchecked Sendable {
    struct Stored: Codable { var id: Int; var external_id: String?; var date: String; var description: String }

    private let lock = NSLock()
    private var nextID = 1
    private var _events: [Stored] = []
    private var _requests: [String] = []
    private var _settings: [String: Any] = ["id": "i123", "name": "Test Runner"]
    private var _activities: [[String: Any]] = []
    private var _streams: [String: [[String: Any]]] = [:]
    func addActivity(_ activity: [String: Any], streams: [[String: Any]] = []) {
        lock.withLock {
            _activities.append(activity)
            _streams[activity["id"] as! String] = streams
        }
    }
    static let apiKey = "good-key"
    static let token = "good-token"
    static let code = "good-code"

    init(events: [Stored] = []) {
        self._events = events
        self.nextID = (events.map(\.id).max() ?? 0) + 1
    }

    var events: [Stored] { lock.withLock { _events } }
    var requests: [String] { lock.withLock { _requests } }
    func setting(_ key: String) -> Any? { lock.withLock { _settings[key] } }
    func set(_ key: String, _ value: Any?) { lock.withLock { _settings[key] = value } }
    /// Links Garmin as Intervals.icu does: granted permissions, upload off until switched on.
    func linkGarmin() { set("icu_garmin_training", true); set("icu_garmin_health", true) }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try lock.withLock { try handle(request) }
    }

    private func handle(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        _requests.append("\(method) \(url.path)")

        if method == "POST", url.path == "/api/oauth/token" {
            let form = URLComponents(string: "?" + String(decoding: request.httpBody ?? Data(), as: UTF8.self))?.queryItems ?? []
            func field(_ name: String) -> String? { form.first { $0.name == name }?.value }
            guard field("client_id") == "client-1", field("code") == Self.code, (field("code_verifier")?.count ?? 0) >= 43,
                  field("client_secret") == nil else { return reply(400, Data()) }
            return reply(200, Data(#"{"token_type":"Bearer","access_token":"good-token","scope":"CALENDAR:WRITE,SETTINGS:WRITE","athlete":{"id":"i123","name":"Test Runner"}}"#.utf8))
        }

        let auth = request.value(forHTTPHeaderField: "Authorization")
        guard auth == "Basic \(Data("API_KEY:\(Self.apiKey)".utf8).base64EncodedString())" || auth == "Bearer \(Self.token)" else {
            return reply(401, Data())
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch (method, url.path) {
        case ("GET", "/api/v1/athlete/0"):
            return reply(200, try JSONSerialization.data(withJSONObject: _settings))
        case ("PUT", "/api/v1/athlete/0"):
            let changes = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            _settings.merge(changes) { _, new in new }
            return reply(200, try JSONSerialization.data(withJSONObject: _settings))
        case ("GET", "/api/v1/athlete/i123/activities"):
            return reply(200, try JSONSerialization.data(withJSONObject: _activities))
        case ("GET", let path) where path.hasPrefix("/api/v1/activity/") && path.hasSuffix("/streams.json"):
            let id = path.dropFirst("/api/v1/activity/".count).dropLast("/streams.json".count)
            return reply(200, try JSONSerialization.data(withJSONObject: _streams[String(id)] ?? []))
        case ("GET", "/api/v1/athlete/i123/events"):
            let oldest = param("oldest")!, newest = param("newest")!
            let inRange = _events.filter { String($0.date.prefix(10)) >= oldest && String($0.date.prefix(10)) <= newest }
            return reply(200, try JSONEncoder().encode(inRange))
        case ("PUT", "/api/v1/athlete/i123/events/bulk-delete"):
            let doomed = try JSONDecoder().decode([[String: Int]].self, from: request.httpBody!).compactMap { $0["id"] }
            _events.removeAll { doomed.contains($0.id) }
            return reply(200, Data("[]".utf8))
        case ("POST", "/api/v1/athlete/i123/events/bulk"):
            for event in try JSONDecoder().decode([IntervalsEvent].self, from: request.httpBody!) {
                _events.append(Stored(id: nextID, external_id: event.external_id, date: event.start_date_local,
                                      description: event.description))
                nextID += 1
            }
            return reply(200, Data("[]".utf8))
        default:
            return reply(404, Data())
        }
    }

    private func reply(_ status: Int, _ data: Data) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: URL(string: "https://intervals.icu")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
struct IntervalsWorkoutTextTests {
    @Test func amounts() {
        #expect(IntervalsWorkoutBuilder.amount(.distance(meters: 400)) == "0.4km")
        #expect(IntervalsWorkoutBuilder.amount(.distance(meters: 16_000)) == "16km")
        #expect(IntervalsWorkoutBuilder.amount(.distance(meters: 1609.344)) == "1.609km")
        #expect(IntervalsWorkoutBuilder.amount(.time(seconds: 600)) == "10m")
        #expect(IntervalsWorkoutBuilder.amount(.time(seconds: 90)) == "90s")
    }

    @Test func pacesAreAbsoluteAndInTheAthletesUnits() {
        let range = PaceRange(fast: 240, slow: 250) // 4:00–4:10 per km
        #expect(IntervalsWorkoutBuilder.pace(range, units: .metric) == "4:10-4:00/km Pace")
        #expect(IntervalsWorkoutBuilder.pace(range, units: .imperial) == "6:42-6:26/mi Pace")
    }

    @Test func workoutTextFollowsThePlan() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let session = try #require(plan.workouts.first { $0.kind == .intervals && $0.blocks.contains { $0.iterations > 1 } })
        let text = IntervalsWorkoutBuilder.description(for: session, units: .metric)
        let block = try #require(session.blocks.first { $0.iterations > 1 })
        #expect(text.contains("\(block.iterations)x"))
        #expect(text.contains("/km Pace"))
        #expect(text.hasPrefix(session.warmup == nil ? "Main set" : "Warmup\n- "))
        if session.cooldown != nil { #expect(text.contains("\n\nCooldown\n- ")) }
        // Every step line is "- <amount>[ <pace>]"; a bare "m" would mean minutes, so distances use km.
        for line in text.split(separator: "\n") where line.hasPrefix("- ") {
            #expect(line.range(of: #"^- [0-9.]+(km|m|s)( [0-9:]+-[0-9:]+/km Pace)?$"#, options: .regularExpression) != nil,
                    "\(line)")
        }
    }

    @Test func externalIDChangesWithTheWorkout() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let workout = try #require(plan.workouts.first)
        let format = DisplayFormat(units: .metric)
        let original = IntervalsWorkoutBuilder.event(for: workout, format: format)
        #expect(original.external_id.hasPrefix("steppa-\(workout.id)-"))
        #expect(IntervalsWorkoutBuilder.event(for: workout, format: format) == original)

        var moved = workout
        moved.date = workout.date.adding(days: 1)
        #expect(IntervalsWorkoutBuilder.event(for: moved, format: format).external_id != original.external_id)
        #expect(IntervalsWorkoutBuilder.event(for: workout, format: DisplayFormat(units: .imperial)).external_id
                != original.external_id)
    }
}

@MainActor
struct IntervalsSyncTests {
    static let today = AppModelTests.start
    static let oauth = IntervalsOAuth(clientID: "client-1", redirectURI: "io.github.nickcia.runcoach://intervals-oauth")

    func model(_ fake: FakeIntervals) throws -> AppModel {
        let keychain = IntervalsKeychain(service: "steppa-tests-\(UUID().uuidString)")
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.today },
                             intervals: IntervalsClient(transport: fake), intervalsOAuth: Self.oauth,
                             intervalsKeychain: keychain)
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(AppModelTests.inputs()))
        return model
    }

    /// Signs in the way the app does after the browser sheet returns.
    func signIn(_ model: AppModel) async throws {
        let attempt = Self.oauth.start()
        let callback = URL(string: "io.github.nickcia.runcoach://intervals-oauth?code=\(FakeIntervals.code)&state=\(attempt.state)")!
        try await model.finishIntervalsSignIn(callback: callback, attempt: attempt)
    }

    @Test func authorizeURLUsesPKCE() throws {
        // RFC 7636, appendix B.
        #expect(IntervalsOAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let attempt = Self.oauth.start()
        let items = try #require(URLComponents(url: attempt.url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(attempt.url.absoluteString.hasPrefix("https://intervals.icu/oauth/authorize?"))
        #expect(value("client_id") == "client-1")
        #expect(value("redirect_uri") == "io.github.nickcia.runcoach://intervals-oauth")
        #expect(value("scope") == "CALENDAR:WRITE,SETTINGS:WRITE,ACTIVITY:READ")
        #expect(value("code_challenge") == IntervalsOAuth.challenge(for: attempt.verifier))
        #expect(value("code_challenge_method") == "S256")
        #expect(value("state") == attempt.state)
        #expect(Self.oauth.callbackScheme == "io.github.nickcia.runcoach")
    }

    @Test func callbackMustMatchTheAttempt() throws {
        let attempt = Self.oauth.start()
        let base = "io.github.nickcia.runcoach://intervals-oauth"
        #expect(try IntervalsOAuth.code(from: URL(string: "\(base)?code=abc&state=\(attempt.state)")!, attempt: attempt) == "abc")
        #expect(throws: IntervalsError.signInFailed) {
            try IntervalsOAuth.code(from: URL(string: "\(base)?code=abc&state=other")!, attempt: attempt)
        }
        #expect(throws: IntervalsError.signInFailed) {
            try IntervalsOAuth.code(from: URL(string: "\(base)?error=access_denied&state=\(attempt.state)")!, attempt: attempt)
        }
    }

    @Test func diffOnlyTouchesThisAppsEvents() {
        let wanted = [IntervalsEvent(start_date_local: "2026-01-01T00:00:00", name: "A", description: "- 10m", external_id: "steppa-a-1"),
                      IntervalsEvent(start_date_local: "2026-01-02T00:00:00", name: "B", description: "- 10m", external_id: "steppa-b-2")]
        let existing: [IntervalsClient.ExistingEvent] = [
            .init(id: 1, external_id: "steppa-a-1"),   // unchanged: keep
            .init(id: 2, external_id: "steppa-b-1"),   // old version of B: remove
            .init(id: 3, external_id: nil),            // the athlete's own: keep
            .init(id: 4, external_id: "other-app-1"),  // another app's: keep
            .init(id: 5, external_id: "steppa-a-1"),   // duplicate: remove
        ]
        let diff = IntervalsClient.diff(wanted: wanted, existing: existing)
        #expect(diff.add.map(\.external_id) == ["steppa-b-2"])
        #expect(diff.remove.sorted() == [2, 5])
    }

    @Test func wrongKeyIsRejected() async throws {
        let model = try model(FakeIntervals())
        await #expect(throws: IntervalsError.unauthorized) { try await model.connectIntervals(apiKey: "nope") }
        #expect(model.intervalsAccount == nil)
    }

    @Test func apiKeyStillWorks() async throws {
        let fake = FakeIntervals()
        let model = try model(fake)
        try await model.connectIntervals(apiKey: " good-key\n")
        #expect(model.intervalsAccount?.kind == .apiKey)
        #expect(fake.events.count == model.plan?.workouts.count)
    }

    @Test func signingInSendsThePlanAndSwitchesOnGarmin() async throws {
        let mine = FakeIntervals.Stored(id: 900, external_id: nil, date: "\(Self.today.adding(days: 3))T00:00:00", description: "My own run")
        let fake = FakeIntervals(events: [mine])
        fake.linkGarmin()
        let model = try model(fake)
        try await signIn(model)

        #expect(model.intervalsAccount?.kind == .oauth)
        #expect(model.intervalsAccount?.athleteName == "Test Runner")
        #expect(fake.setting("icu_garmin_upload_workouts") as? Bool == true)
        #expect(model.intervalsAthlete?.links == [.init(service: .garmin, uploading: true)])
        let plan = try #require(model.plan)
        #expect(fake.events.count == plan.workouts.count + 1)
        #expect(fake.events.contains { $0.id == 900 })

        // Nothing changed: coming back to the app makes no further calendar requests.
        let before = fake.requests.filter { $0.contains("/events") }.count
        await model.syncIntervals()
        #expect(fake.requests.filter { $0.contains("/events") }.count == before)
    }

    @Test func linkingGarminLaterSwitchesItOn() async throws {
        let fake = FakeIntervals()
        let model = try model(fake)
        try await signIn(model)
        #expect(model.intervalsAthlete?.links.isEmpty == true)

        // The athlete links Garmin on Intervals.icu and comes back to the app.
        fake.linkGarmin()
        await model.becameActive()
        #expect(fake.setting("icu_garmin_upload_workouts") as? Bool == true)

        // Turned off by hand later: it stays off.
        fake.set("icu_garmin_upload_workouts", false)
        await model.becameActive()
        #expect(fake.setting("icu_garmin_upload_workouts") as? Bool == false)
        #expect(model.intervalsAthlete?.links == [.init(service: .garmin, uploading: false)])
    }

    @Test func reopeningTheAppDoesNotOverrideSettings() async throws {
        let fake = FakeIntervals()
        let keychain = IntervalsKeychain(service: "steppa-tests-\(UUID().uuidString)")
        defer { keychain.delete() }
        let container = Persistence.makeContainer(inMemory: true)
        let first = AppModel(container: container, clock: { Self.today }, intervals: IntervalsClient(transport: fake),
                             intervalsOAuth: Self.oauth, intervalsKeychain: keychain)
        try await signIn(first)

        // Garmin is linked with upload off while the app isn't running.
        fake.linkGarmin()
        fake.set("icu_garmin_upload_workouts", false)
        let reopened = AppModel(container: container, clock: { Self.today }, intervals: IntervalsClient(transport: fake),
                                intervalsOAuth: Self.oauth, intervalsKeychain: keychain)
        #expect(reopened.intervalsAccount?.athleteID == "i123")
        await reopened.becameActive()
        #expect(fake.setting("icu_garmin_upload_workouts") as? Bool == false)
        #expect(reopened.intervalsAthlete?.links == [.init(service: .garmin, uploading: false)])
    }

    @Test func planChangesReplaceOnlyChangedWorkouts() async throws {
        let fake = FakeIntervals()
        let model = try model(fake)
        try await signIn(model)
        let plan = try #require(model.plan)
        let before = Set(fake.events.map(\.id))

        let workout = try #require(plan.workouts.first { $0.date > Self.today && $0.kind == .easy })
        let free = try #require((1...6).map { workout.date.adding(days: $0) }.first { model.workout(on: $0) == nil
            && model.week(containing: $0)?.workouts.contains { $0.id == workout.id } == true })
        #expect(model.move(workout, to: free))
        await model.syncIntervals()

        let after = Set(fake.events.map(\.id))
        #expect(fake.events.count == plan.workouts.count)
        #expect(before.subtracting(after).count == 1)
        #expect(fake.events.contains { $0.date.hasPrefix(free.description) })
    }

    @Test func disconnectingRemovesUpcomingWorkouts() async throws {
        let mine = FakeIntervals.Stored(id: 900, external_id: nil, date: "\(Self.today.adding(days: 3))T00:00:00", description: "My own run")
        let fake = FakeIntervals(events: [mine])
        let model = try model(fake)
        try await signIn(model)
        await model.disconnectIntervals()
        #expect(model.intervalsAccount == nil)
        #expect(fake.events.map(\.id) == [900])
    }
}

@MainActor
struct IntervalsActivityTests {
    static let today = AppModelTests.start.adding(days: 9)

    @Test func streamsLineUpWithTimeAndSkipGaps() throws {
        let series = try #require(IntervalsClient.series(from: [
            "time": [0, 5, 10, nil, 20],
            "distance": [0, 15, 30, 45, 60],
            "heartrate": [120, nil, 130, 131, 132],
            "cadence": [84, 85, 86, 85, 84], // per foot, as Garmin records it
        ]))
        #expect(series.distance.map(\.t) == [0, 5, 10, 20])
        #expect(series.heartRate.map(\.v) == [120, 130, 132])
        #expect(series.cadence.first?.v == 168)
        #expect(series.power.isEmpty)
        #expect(IntervalsClient.series(from: ["distance": [1, 2]]) == nil)
    }

    func model(_ fake: FakeIntervals, health: [CompletedRun] = []) async throws -> (AppModel, FakeRunSource) {
        let keychain = IntervalsKeychain(service: "steppa-tests-\(UUID().uuidString)")
        let source = FakeRunSource(runs: health)
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.today },
                             runSource: source, intervals: IntervalsClient(transport: fake),
                             intervalsKeychain: keychain)
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(AppModelTests.inputs()))
        try await model.connectIntervals(apiKey: FakeIntervals.apiKey)
        return (model, source)
    }

    static func activity(_ id: String, _ workout: Workout, scale: Double = 1) -> [String: Any] {
        ["id": id, "start_date_local": "\(workout.date)T07:00:00", "type": "Run",
         "distance": workout.totalMeters * scale, "moving_time": workout.totalSeconds * scale]
    }

    static let streams: [[String: Any]] = [
        ["type": "time", "data": Array(stride(from: 0.0, through: 1800, by: 10))],
        ["type": "distance", "data": Array(stride(from: 0.0, through: 1800, by: 10)).map { $0 * 3 }],
        ["type": "heartrate", "data": Array(repeating: 145.0, count: 181)],
    ]

    @Test func intervalsOnlyRunsTickOffWorkoutsWithTheirData() async throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let first = try #require(plan.workouts.first)
        let fake = FakeIntervals()
        fake.addActivity(Self.activity("i9", first), streams: Self.streams)
        let (model, _) = try await model(fake)

        await model.refreshHealth()
        let run = try #require(model.healthRuns.first { $0.id == "icu-i9" })
        #expect(model.status(of: first) == .done)
        #expect(model.workout(for: run)?.id == first.id)
        #expect(model.runSeries[run.id]?.heartRate.isEmpty == false)
        #expect(model.analysis(for: run).averageHeartRate == 145)
    }

    @Test func theSameRunInHealthAndIntervalsCountsOnceWithIntervalsData() async throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let first = try #require(plan.workouts.first)
        let healthRun = HealthIntegrationTests.run(for: first, id: "hk1", scale: 1.02)
        let fake = FakeIntervals()
        fake.addActivity(Self.activity("i9", first), streams: Self.streams)
        let (model, source) = try await model(fake, health: [healthRun])
        source.series["hk1"] = RunSeries(heartRate: [.init(0, 150), .init(10, 150)])
        await model.connectHealth()

        #expect(model.healthRuns.map(\.id) == ["hk1"])
        // Intervals.icu's fuller recording is used for the Health run.
        #expect(model.runSeries["hk1"]?.distance.isEmpty == false)
        #expect(model.dataSource(for: healthRun) == "intervals")
    }

    @Test func healthDataIsUsedWithoutIntervals() async throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let first = try #require(plan.workouts.first)
        let healthRun = HealthIntegrationTests.run(for: first, id: "hk1")
        let source = FakeRunSource(runs: [healthRun])
        source.series["hk1"] = RunSeries(heartRate: [.init(0, 150), .init(10, 150)])
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.today }, runSource: source)
        model.acceptDisclaimer()
        model.start(plan)
        await model.connectHealth()
        #expect(model.runSeries["hk1"]?.heartRate.count == 2)
        #expect(model.dataSource(for: healthRun) == "health")
    }
}
